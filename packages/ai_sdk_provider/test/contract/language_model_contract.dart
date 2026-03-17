import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

typedef CaptureRequestBody =
    Future<Map<String, dynamic>> Function(LanguageModelV3Prompt prompt);

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

LanguageModelV3Prompt _multimodalPrompt() {
  return LanguageModelV3Prompt(
    messages: [
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [
          LanguageModelV3TextPart(text: 'Analyze these assets'),
          LanguageModelV3ImagePart(
            image: DataContentBytes(Uint8List.fromList(utf8.encode('img'))),
            mediaType: 'image/png',
          ),
          LanguageModelV3FilePart(
            data: DataContentBytes(Uint8List.fromList(utf8.encode('audio'))),
            mediaType: 'audio/wav',
            filename: 'clip.wav',
          ),
        ],
      ),
    ],
  );
}

LanguageModelV3Prompt _toolResultPrompt() {
  return LanguageModelV3Prompt(
    messages: [
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: 'Use weather tool')],
      ),
      LanguageModelV3Message(
        role: LanguageModelV3Role.tool,
        content: [
          LanguageModelV3ToolResultPart(
            toolCallId: 'call_1',
            toolName: 'weather',
            isError: true,
            output: ToolResultOutputContent([
              LanguageModelV3TextPart(text: 'city not found'),
            ]),
          ),
        ],
      ),
    ],
  );
}
