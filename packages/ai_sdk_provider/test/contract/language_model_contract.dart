import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

typedef CaptureRequestBody =
    Future<Map<String, dynamic>> Function(LanguageModelV4Prompt prompt);

typedef BodyExpectation = void Function(Map<String, dynamic> body);

void runProviderContractTests({
  required String providerName,
  required CaptureRequestBody captureRequestBody,
  required BodyExpectation expectMultimodalBody,
  required BodyExpectation expectToolResultBody,
}) {
  group('$providerName contract fixtures', () {
    test('multimodal prompt is serialized', () async {
      final body = await captureRequestBody(_multimodalPrompt());
      expectMultimodalBody(body);
    });

    test('tool result prompt is serialized', () async {
      final body = await captureRequestBody(_toolResultPrompt());
      expectToolResultBody(body);
    });
  });
}

LanguageModelV4Prompt _multimodalPrompt() {
  return LanguageModelV4Prompt(
    messages: [
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [
          LanguageModelV4TextPart(text: 'Analyze these assets'),
          LanguageModelV4ImagePart(
            image: DataContentBytes(Uint8List.fromList(utf8.encode('img'))),
            mediaType: 'image/png',
          ),
          LanguageModelV4FilePart(
            data: DataContentBytes(Uint8List.fromList(utf8.encode('audio'))),
            mediaType: 'audio/wav',
            filename: 'clip.wav',
          ),
        ],
      ),
    ],
  );
}

LanguageModelV4Prompt _toolResultPrompt() {
  return LanguageModelV4Prompt(
    messages: [
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: 'Use weather tool')],
      ),
      LanguageModelV4Message(
        role: LanguageModelV4Role.tool,
        content: [
          LanguageModelV4ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'weather',
            isError: true,
            output: ToolResultOutputContent([
              LanguageModelV4TextPart(text: 'city not found'),
            ]),
          ),
        ],
      ),
    ],
  );
}
