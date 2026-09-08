import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// [ToolLoopAgent] is pure forwarding to [generateText]/[streamText] (zero
/// branches of its own), so this file only checks the happy paths and that
/// every constructor/call parameter actually reaches the underlying call —
/// not the generateText/streamText loop machinery itself, which is covered
/// by its own conformance tests.
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

  group('ToolLoopAgent.generate', () {
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

    test('forwards instructions as the system prompt', () async {
      final capturing = FakeCapturingModel(responseText: 'ok');
      final agent = ToolLoopAgent(model: capturing, instructions: 'be helpful');
      await agent.generate(prompt: 'hi');
      expect(capturing.capturedOptions.single.prompt.system, 'be helpful');
    });

    test('forwards tools to the underlying call options', () async {
      final capturing = FakeCapturingModel(responseText: 'ok');
      final agent = ToolLoopAgent(
        model: capturing,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      await agent.generate(prompt: 'hi');
      final names = capturing.capturedOptions.single.tools
          .whereType<LanguageModelV4FunctionTool>()
          .map((t) => t.name);
      expect(names, contains('echo'));
    });

    test('forwards maxSteps to the tool loop', () async {
      final model = _AgentLoopModel([
        _toolCall('echo', const {}),
        _toolCall('echo', const {}),
        _toolCall('echo', const {}),
      ]);
      final agent = ToolLoopAgent(
        model: model,
        maxSteps: 2,
        tools: {'echo': echoTool((_) => 'ok')},
      );
      await agent.generate(prompt: 'go');
      expect(model.callCount, 2);
    });

    test('forwards stopConditions to the tool loop', () async {
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
      await agent.generate(prompt: 'go');
      expect(model.callCount, 1);
    });

    test(
      'forwards pre-cancelled abortSignal in direct generate path',
      () async {
        final token = CancellationToken()..cancel();
        final agent = ToolLoopAgent(model: FakeTextModel('unexpected'));

        await expectLater(
          () => agent.generate(prompt: 'hi', abortSignal: token),
          throwsA(isA<AiOperationCancelledError>()),
        );
      },
    );
  });

  group('ToolLoopAgent.stream', () {
    test(
      'stream delegates to streamText with tools and stop conditions',
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
      },
    );

    test('forwards timeout through stream()', () async {
      final agent = ToolLoopAgent(
        model: FakeSlowStartModel(const Duration(milliseconds: 50)),
      );
      final result = await agent.stream(
        prompt: 'go',
        timeout: const TimeoutConfiguration(step: Duration(milliseconds: 10)),
      );

      await expectLater(result.text, throwsA(isA<TimeoutException>()));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LanguageModelV4GenerateResult _text(String text) =>
    LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
    );

LanguageModelV4GenerateResult _toolCall(
  String name,
  Map<String, dynamic> input,
) => LanguageModelV4GenerateResult(
  content: [
    LanguageModelV4ToolCallPart(toolCallId: 'tc', toolName: name, input: input),
  ],
  finishReason: LanguageModelV4FinishReason.toolCalls,
);

/// Cycles through [responses] across successive doGenerate calls.
class _AgentLoopModel extends LanguageModelV4 {
  _AgentLoopModel(this.responses);
  final List<LanguageModelV4GenerateResult> responses;
  int _i = 0;
  int callCount = 0;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'agent-loop';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    callCount++;
    final r = responses[_i < responses.length ? _i : responses.length - 1];
    _i++;
    return r;
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => throw UnimplementedError();
}
