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

  final ModelMessageRole role;
  final String? content;
  final List<LanguageModelV4ContentPart>? parts;
}
