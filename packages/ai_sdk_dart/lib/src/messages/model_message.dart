import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Message role for [ModelMessage].
enum ModelMessageRole { system, user, assistant, tool }

/// User-facing message for [generateText] and [streamText].
///
/// Use [content] for simple text or [parts] for multimodal content
/// (images, tool calls, etc.).
class ModelMessage {
  const ModelMessage({required this.role, required String this.content})
    : parts = null;

  const ModelMessage.parts({
    required this.role,
    required List<LanguageModelV4ContentPart> this.parts,
  }) : content = null;

  factory ModelMessage.fromProvider(LanguageModelV4Message message) =>
      ModelMessage.parts(
        role: switch (message.role) {
          LanguageModelV4Role.system => ModelMessageRole.system,
          LanguageModelV4Role.user => ModelMessageRole.user,
          LanguageModelV4Role.assistant => ModelMessageRole.assistant,
          LanguageModelV4Role.tool => ModelMessageRole.tool,
        },
        parts: List.unmodifiable(message.content),
      );

  final ModelMessageRole role;
  final String? content;
  final List<LanguageModelV4ContentPart>? parts;
}
