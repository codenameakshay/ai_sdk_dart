import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'streamed hosted results are replayed once in the assistant role',
    () async {
      final model = _HostedModel();
      var localExecutions = 0;
      final result = await streamText(
        model: model,
        prompt: 'search',
        maxSteps: 2,
        tools: {
          'search': dynamicTool<String>(
            execute: (_, _) async {
              localExecutions++;
              return 'local';
            },
          ),
        },
      );
      expect(await result.text, 'answer');
      expect(localExecutions, 0);
      final results = model.history!
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>();
      expect(results, hasLength(1));
      expect(
        model.history!.where(
          (message) => message.role == LanguageModelV4Role.tool,
        ),
        isEmpty,
      );
      expect((await result.response).messages.map((message) => message.role), [
        LanguageModelV4Role.assistant,
        LanguageModelV4Role.assistant,
      ]);
    },
  );
}

class _HostedModel extends FakeTextModel {
  _HostedModel() : super('answer');
  var calls = 0;
  List<LanguageModelV4Message>? history;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (calls++ > 0) {
      history = options.prompt.messages;
      return super.doStream(options);
    }
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable(const [
        StreamPartToolCall(
          toolCall: LanguageModelV4ToolCallPart(
            toolCallId: 'hosted',
            toolName: 'search',
            input: {},
            providerExecuted: true,
          ),
        ),
        StreamPartToolResult(
          toolResult: LanguageModelV4ToolResultPart(
            toolCallId: 'hosted',
            toolName: 'search',
            output: ToolResultOutputText('remote'),
          ),
        ),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.toolCalls),
      ]),
    );
  }
}
