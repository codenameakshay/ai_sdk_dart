import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? "streamText" : "generateText"} preserves new turns after context compaction',
      () async {
        final model = FakeMultiStepModel(const [
          LanguageModelV4GenerateResult(
            content: [
              LanguageModelV4ToolCallPart(
                toolCallId: 'call',
                toolName: 'lookup',
                input: {},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
          LanguageModelV4GenerateResult(
            content: [LanguageModelV4TextPart(text: 'answer')],
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]);
        final tools = {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: Schema(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'found',
          ),
        };
        Future<GenerateTextPrepareStepResult?> compact(
          GenerateTextPrepareStepContext context,
        ) async => context.stepNumber == 1
            ? const GenerateTextPrepareStepResult(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.user,
                    content: [LanguageModelV4TextPart(text: 'compacted')],
                  ),
                ],
              )
            : null;
        final messages = streaming
            ? (await (await streamText(
                model: model,
                prompt: 'lookup',
                tools: tools,
                maxSteps: 2,
                prepareStep: compact,
              )).response).messages
            : (await generateText(
                model: model,
                prompt: 'lookup',
                tools: tools,
                maxSteps: 2,
                prepareStep: compact,
              )).responseMessages;
        expect(messages.map((message) => message.role), [
          LanguageModelV4Role.assistant,
          LanguageModelV4Role.tool,
          LanguageModelV4Role.assistant,
        ]);
        expect(
          messages.first.content
              .whereType<LanguageModelV4ToolCallPart>()
              .single
              .toolCallId,
          'call',
        );
        expect(
          messages[1].content
              .whereType<LanguageModelV4ToolResultPart>()
              .single
              .toolCallId,
          'call',
        );
      },
    );

    test(
      '${streaming ? "streamText" : "generateText"} returns only new messages',
      () async {
        final model = FakeTextModel('new answer');
        const history = [
          ModelMessage(role: ModelMessageRole.assistant, content: 'old answer'),
          ModelMessage(role: ModelMessageRole.user, content: 'new question'),
        ];
        final messages = streaming
            ? (await (await streamText(
                model: model,
                messages: history,
              )).response).messages
            : (await generateText(
                model: model,
                messages: history,
              )).responseMessages;
        expect(messages, hasLength(1));
        expect(
          messages.single.content
              .whereType<LanguageModelV4TextPart>()
              .single
              .text,
          'new answer',
        );
        expect(model.lastCallOptions!.prompt.messages, hasLength(2));
      },
    );
  }
}
