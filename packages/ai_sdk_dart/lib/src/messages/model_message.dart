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

  /// The plain text of this message.
  ///
  /// For a [content] message, this is [content]. For a [parts] message, this
  /// is the text of each [LanguageModelV4TextPart] in order, joined with no
  /// separator. Reasoning, tool calls, tool results, approvals, files, images,
  /// and sources are excluded. A message with no text parts returns `''`.
  String get text =>
      content ??
      parts!
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join();
}
