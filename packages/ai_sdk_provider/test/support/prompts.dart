import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A single-message prompt containing just [text] from the user.
LanguageModelV4Prompt userPrompt(String text) {
  return LanguageModelV4Prompt(
    messages: [
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: text)],
      ),
    ],
  );
}

/// A single-message prompt containing text plus an inline `image/png` part.
LanguageModelV4Prompt imagePrompt() => LanguageModelV4Prompt(
  messages: [
    LanguageModelV4Message(
      role: LanguageModelV4Role.user,
      content: [
        LanguageModelV4TextPart(text: 'describe'),
        LanguageModelV4ImagePart(
          image: DataContentBytes(Uint8List.fromList(utf8.encode('img'))),
          mediaType: 'image/png',
        ),
      ],
    ),
  ],
);
