import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? "streamText" : "generateText"} includes local results once in chronological content',
      () async {
        final model = FakeToolModel(toolName: 'lookup', toolInput: {});
        final tools = {
          'lookup': dynamicTool<String>(execute: (_, _) async => 'found'),
        };
        late List<LanguageModelV4ContentPart> content;
        late GenerateTextStep step;
        late List<LanguageModelV4Message> messages;
        if (streaming) {
          final result = await streamText(
            model: model,
            prompt: 'go',
            tools: tools,
          );
          content = await result.content;
          step = await result.finalStep;
          messages = (await result.response).messages;
        } else {
          final result = await generateText(
            model: model,
            prompt: 'go',
            tools: tools,
          );
          content = result.content;
          step = result.finalStep;
          messages = result.responseMessages;
        }
        expect(content.map((part) => part.runtimeType), [
          LanguageModelV4ToolCallPart,
          LanguageModelV4ToolResultPart,
        ]);
        expect(
          step.content.whereType<LanguageModelV4ToolResultPart>(),
          hasLength(1),
        );
        expect(
          messages.first.content.whereType<LanguageModelV4ToolResultPart>(),
          isEmpty,
        );
        expect(messages.last.role, LanguageModelV4Role.tool);
        expect(
          messages.last.content.whereType<LanguageModelV4ToolResultPart>(),
          hasLength(1),
        );
      },
    );
  }
}
