import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Drives the tool-execution error branches, structured-output system
/// instructions, array parsing, and message-conversion paths inside
/// `generateText`.
void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  group('generateText messages conversion', () {
    test('messages of every role are forwarded to the model', () async {
      final capturing = FakeCapturingModel(responseText: 'ok');
      await generateText(
        model: capturing,
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

  group('generateText structured output system instruction', () {
    test('system is combined with object/array/choice/json schema text',
        () async {
      // object
      final objModel = FakeCapturingModel(responseText: '{"a":1}');
      await generateText<Map<String, dynamic>>(
        model: objModel,
        system: 'be terse',
        prompt: 'go',
        output: Output.object(schema: objectSchema()),
      );
      expect(objModel.capturedOptions.single.prompt.system, contains('be terse'));

      // array
      final arrModel = FakeCapturingModel(responseText: '[]');
      await generateText<List<dynamic>>(
        model: arrModel,
        system: 'arr-sys',
        prompt: 'go',
        output: Output.array(element: objectSchema()),
      );
      expect(arrModel.capturedOptions.single.prompt.system, contains('arr-sys'));

      // choice
      final choiceModel = FakeCapturingModel(responseText: 'a');
      await generateText<String>(
        model: choiceModel,
        system: 'choice-sys',
        prompt: 'go',
        output: Output.choice(options: const ['a', 'b']),
      );
      expect(
        choiceModel.capturedOptions.single.prompt.system,
        contains('choice-sys'),
      );

      // json
      final jsonModel = FakeCapturingModel(responseText: '{}');
      await generateText<Object?>(
        model: jsonModel,
        system: 'json-sys',
        prompt: 'go',
        output: Output.json(),
      );
      expect(
        jsonModel.capturedOptions.single.prompt.system,
        contains('json-sys'),
      );
    });

    test('array output rejects scalar elements', () async {
      final model = FakeTextModel('[1, 2, 3]');
      await expectLater(
        generateText<List<dynamic>>(
          model: model,
          prompt: 'go',
          output: Output.array(element: objectSchema()),
        ),
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    });

    test('object output rejects a non-object JSON value', () async {
      final model = FakeTextModel('[1, 2]');
      await expectLater(
        generateText<Map<String, dynamic>>(
          model: model,
          prompt: 'go',
          output: Output.object(schema: objectSchema()),
        ),
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    });

    test('array output parses elements that are maps', () async {
      final model = FakeTextModel('[{"name":"A"},{"name":"B"}]');
      final result = await generateText<List<dynamic>>(
        model: model,
        prompt: 'go',
        output: Output.array(element: objectSchema()),
      );
      expect(result.output.length, 2);
    });

    test('object output extracts JSON from a fenced code block', () async {
      final model = FakeTextModel('```json\n{"a":1}\n```');
      final result = await generateText<Map<String, dynamic>>(
        model: model,
        prompt: 'go',
        output: Output.object(schema: objectSchema()),
      );
      expect(result.output, {'a': 1});
    });
  });

  group('generateText tool execution errors', () {
    Tool<Map<String, dynamic>, Object?> errTool(Object error) {
      return tool<Map<String, dynamic>, Object?>(
        inputSchema: objectSchema(),
        execute: (_, __) async => throw error,
      );
    }

    test('throwing executor produces an error tool result', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'boom',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'recovered')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'boom': errTool(StateError('boom'))},
      );
      expect(result.text, 'recovered');
      final toolResult = result.steps.first.toolResults.single;
      expect(toolResult.isError, isTrue);
    });

    test('tool with no executor produces an error tool result', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'noexec',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'after')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'noexec': tool<Map<String, dynamic>, String>(
            inputSchema: objectSchema(),
          ),
        },
      );
      expect(result.text, 'after');
      expect(result.steps.first.toolResults.single.isError, isTrue);
    });

    test('non-object tool input produces an error tool result', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'echo',
              input: 'a bare string',
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'after')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'echo': tool<Map<String, dynamic>, String>(
            inputSchema: objectSchema(),
            execute: (_, __) async => 'ok',
          ),
        },
      );
      expect(result.steps.first.toolResults.single.isError, isTrue);
    });

    test('non-string tool output is JSON-encoded into the result', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'obj',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'done')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'obj': tool<Map<String, dynamic>, Object?>(
            inputSchema: objectSchema(),
            execute: (_, __) async => {'k': 'v'},
          ),
        },
      );
      final output =
          result.steps.first.toolResults.single.output as ToolResultOutputText;
      expect(output.text, contains('"k":"v"'));
    });

    test('streaming tool output resolves to the last emitted value', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'stream',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'done')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {
          'stream': tool<Map<String, dynamic>, Object?>(
            inputSchema: objectSchema(),
            execute: (_, __) async => Stream.fromIterable(['first', 'last']),
          ),
        },
      );
      final output =
          result.steps.first.toolResults.single.output as ToolResultOutputText;
      expect(output.text, 'last');
    });

    test('onToolCallStart / onToolCallFinish fire (success and failure)',
        () async {
      var startCount = 0;
      final finishes = <bool>[];
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'boom',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'after')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'boom': errTool(StateError('x'))},
        experimentalOnToolCallStart: (_) => startCount++,
        experimentalOnToolCallFinish: (e) => finishes.add(e.success),
      );
      expect(startCount, 1);
      expect(finishes, [false]);
    });
  });

  group('generateText toolChoice specific validation', () {
    test('specific tool mismatch throws AiApiCallError', () async {
      // Expose both tools, force "a", but the model calls "b".
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'b',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
      ]);
      await expectLater(
        generateText(
          model: model,
          prompt: 'go',
          maxSteps: 3,
          toolChoice: const ToolChoiceSpecific(toolName: 'a'),
          tools: {
            'a': tool<Map<String, dynamic>, String>(
              inputSchema: objectSchema(),
              execute: (_, __) async => 'a',
            ),
            'b': tool<Map<String, dynamic>, String>(
              inputSchema: objectSchema(),
              execute: (_, __) async => 'b',
            ),
          },
        ),
        throwsA(isA<AiApiCallError>()),
      );
    });
  });

  group('generateText tool approval flow', () {
    Tool<Map<String, dynamic>, Object?> approvalTool({
      required bool needs,
    }) {
      return tool<Map<String, dynamic>, Object?>(
        inputSchema: objectSchema(),
        execute: (_, __) async => 'executed',
        needsApproval: (_, __) async => needs,
      );
    }

    test('tool requiring approval with no response emits an approval request',
        () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'danger',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'danger': approvalTool(needs: true)},
      );
      expect(result.toolApprovalRequests, isNotEmpty);
      // No execution happened (the request awaits a decision).
      expect(result.steps.first.toolResults, isEmpty);
    });

    test('approved tool executes and reports its output', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'danger',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'after')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        // evaluator returns false → once approved, the tool executes.
        tools: {'danger': approvalTool(needs: false)},
        toolApprovalResponses: const [
          LanguageModelV3ToolApprovalResponse(
            approvalId: 'approval_c1',
            approved: true,
          ),
        ],
      );
      final toolResult = result.steps.first.toolResults.single;
      expect(toolResult.isError, isFalse);
      expect((toolResult.output as ToolResultOutputText).text, 'executed');
    });

    test('denied tool returns an error result with the reason', () async {
      final model = FakeMultiStepModel([
        const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3ToolCallPart(
              toolCallId: 'c1',
              toolName: 'danger',
              input: {},
            ),
          ],
          finishReason: LanguageModelV3FinishReason.toolCalls,
        ),
        const LanguageModelV3GenerateResult(
          content: [LanguageModelV3TextPart(text: 'after')],
          finishReason: LanguageModelV3FinishReason.stop,
        ),
      ]);
      final result = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: {'danger': approvalTool(needs: false)},
        toolApprovalResponses: const [
          LanguageModelV3ToolApprovalResponse(
            approvalId: 'approval_c1',
            approved: false,
            reason: 'denied!',
          ),
        ],
      );
      final toolResult = result.steps.first.toolResults.single;
      expect(toolResult.isError, isTrue);
      expect(
        (toolResult.output as ToolResultOutputText).text,
        'denied!',
      );
    });
  });

  group('generateText active tool errors', () {
    test('unknown active tool name throws AiNoSuchToolError', () async {
      await expectLater(
        generateText(
          model: FakeTextModel('x'),
          prompt: 'go',
          activeToolNames: const ['missing'],
          tools: {
            'a': tool<Map<String, dynamic>, String>(
              inputSchema: objectSchema(),
              execute: (_, __) async => 'a',
            ),
          },
        ),
        throwsA(isA<AiNoSuchToolError>()),
      );
    });
  });
}
