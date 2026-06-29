import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Exercises the [ToolLoopAgent] generate/stream paths and the tool-execution
/// error branches that the single existing happy-path test does not reach.
void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  Tool<Map<String, dynamic>, Object?> echoTool(
    Object? Function(Map<String, dynamic>) fn,
  ) {
    return tool<Map<String, dynamic>, Object?>(
      inputSchema: objectSchema(),
      execute: (input, _) async => fn(input),
    );
  }

  group('ToolLoopAgent.generate single-shot path', () {
    test('no tools delegates directly to generateText (prompt)', () async {
      final agent = ToolLoopAgent(
        model: FakeTextModel('plain answer'),
        instructions: 'be helpful',
      );
      final result = await agent.generate(prompt: 'hi');
      expect(result.text, 'plain answer');
    });

    test('maxSteps <= 1 delegates directly even with tools', () async {
      final agent = ToolLoopAgent(
        model: FakeTextModel('direct'),
        tools: {'echo': echoTool((_) => 'x')},
      );
      final result = await agent.generate(prompt: 'hi');
      expect(result.text, 'direct');
    });

    test('delegates with messages (all roles converted)', () async {
      final capturing = FakeCapturingModel(responseText: 'ok');
      final agent = ToolLoopAgent(model: capturing);
      await agent.generate(
        messages: const [
          ModelMessage(role: ModelMessageRole.system, content: 's'),
          ModelMessage(role: ModelMessageRole.user, content: 'u'),
          ModelMessage(role: ModelMessageRole.assistant, content: 'a'),
          ModelMessage(role: ModelMessageRole.tool, content: 't'),
        ],
      );
      final roles = capturing.capturedOptions.single.prompt.messages
          .map((m) => m.role.name)
          .toList();
      expect(roles, ['system', 'user', 'assistant', 'tool']);
    });
  });

  group('ToolLoopAgent.generate tool loop', () {
    test('runs the tool loop and returns the final text', () async {
      final model = _AgentLoopModel([
        _toolCall('echo', {'msg': 'hi'}),
        _text('final answer'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 4,
        tools: {'echo': echoTool((input) => 'echoed:${input['msg']}')},
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'final answer');
    });

    test('converts messages inside the loop path', () async {
      final model = _AgentLoopModel([
        _toolCall('echo', const {}),
        _text('done'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 4,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(
        messages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'u'),
          ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: [LanguageModelV3TextPart(text: 'prior')],
          ),
        ],
      );
      expect(result.text, 'done');
    });

    test('stop condition halts the loop and returns current response',
        () async {
      // Always returns a tool call, but a stop condition fires after step 1.
      final model = _AgentLoopModel([
        _toolCall('echo', const {}),
        _toolCall('echo', const {}),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 5,
        stopConditions: [(snapshot) => snapshot.stepCount >= 1],
        tools: {'echo': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(prompt: 'go');
      // The response that triggered the stop carried a tool call (no text).
      expect(result.toolCalls, isNotEmpty);
    });

    test('maxSteps exhausted with continuous tool calls returns last response',
        () async {
      final model = _AgentLoopModel([
        _toolCall('echo', const {}),
        _toolCall('echo', const {}),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 2,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.toolCalls, isNotEmpty);
    });
  });

  group('ToolLoopAgent tool execution errors', () {
    test('unknown tool name yields an error tool result', () async {
      final model = _AgentLoopModel([
        _toolCall('missing', const {}),
        _text('after'),
      ]);
      // Expose a known tool so the loop runs; the call targets an unknown one.
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {'known': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'after');
    });

    test('non-object tool input yields an error tool result', () async {
      final model = _AgentLoopModel([
        _toolCallRaw('echo', 'a bare string'),
        _text('after'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'after');
    });

    test('tool with no executor yields an error tool result', () async {
      final model = _AgentLoopModel([
        _toolCall('noexec', const {}),
        _text('after'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {
          'noexec': tool<Map<String, dynamic>, String>(
            inputSchema: objectSchema(),
          ),
        },
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'after');
    });

    test('throwing tool executor is captured as an error result', () async {
      final model = _AgentLoopModel([
        _toolCall('boom', const {}),
        _text('recovered'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {'boom': echoTool((_) => throw StateError('kaboom'))},
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'recovered');
    });

    test('non-string tool output is JSON-encoded', () async {
      final model = _AgentLoopModel([
        _toolCall('obj', const {}),
        _text('done'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {
          'obj': echoTool((_) => {'k': 'v'}),
        },
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'done');
    });

    test('unencodable tool output falls back to toString', () async {
      final model = _AgentLoopModel([
        _toolCall('obj', const {}),
        _text('done'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {
          'obj': echoTool((_) => _AgentUnencodable()),
        },
      );
      final result = await agent.generate(prompt: 'go');
      expect(result.text, 'done');
    });

    test('loop converts a tool-role message in the prompt history', () async {
      final model = _AgentLoopModel([
        _toolCall('echo', const {}),
        _text('done'),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      final result = await agent.generate(
        messages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'u'),
          ModelMessage.parts(
            role: ModelMessageRole.tool,
            parts: [
              LanguageModelV3ToolResultPart(
                toolCallId: 'prev',
                toolName: 'echo',
                output: ToolResultOutputText('prior result'),
              ),
            ],
          ),
        ],
      );
      expect(result.text, 'done');
    });
  });

  group('ToolLoopAgent.stream', () {
    test('stream delegates to streamText with tools and stop conditions',
        () async {
      final model = FakeTextModel('streamed answer');
      final agent = ToolLoopAgent(
        model: model,
        instructions: 'guidance',
        maxSteps: 2,
        tools: {'echo': echoTool((_) => 'ok')},
        stopConditions: [(s) => false],
      );
      final result = await agent.stream(prompt: 'go');
      expect(await result.text, 'streamed answer');
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LanguageModelV3GenerateResult _text(String text) =>
    LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
    );

LanguageModelV3GenerateResult _toolCall(
  String name,
  Map<String, dynamic> input,
) =>
    LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3ToolCallPart(
          toolCallId: 'tc',
          toolName: name,
          input: input,
        ),
      ],
      finishReason: LanguageModelV3FinishReason.toolCalls,
    );

LanguageModelV3GenerateResult _toolCallRaw(String name, Object input) =>
    LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3ToolCallPart(
          toolCallId: 'tc',
          toolName: name,
          input: input,
        ),
      ],
      finishReason: LanguageModelV3FinishReason.toolCalls,
    );

/// A value that is not JSON-encodable but has a stable toString.
class _AgentUnencodable {
  @override
  String toString() => 'AgentUnencodable()';
}

/// Cycles through [responses] across successive doGenerate calls.
class _AgentLoopModel implements LanguageModelV3 {
  _AgentLoopModel(this.responses);
  final List<LanguageModelV3GenerateResult> responses;
  int _i = 0;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'agent-loop';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    final r = responses[_i < responses.length ? _i : responses.length - 1];
    _i++;
    return r;
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();
}
