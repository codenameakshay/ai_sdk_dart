import 'language_model_v3_content.dart';

/// Message roles supported by language model prompts.
enum LanguageModelV3Role { system, user, assistant, tool }

/// A single prompt message in language-model-native format.
class LanguageModelV3Message {
  const LanguageModelV3Message({required this.role, required this.content});

  final LanguageModelV3Role role;
  final List<LanguageModelV3ContentPart> content;
}

/// A normalized prompt for LanguageModelV3 calls.
class LanguageModelV3Prompt {
  const LanguageModelV3Prompt({this.system, required this.messages});

  final String? system;
  final List<LanguageModelV3Message> messages;
}
