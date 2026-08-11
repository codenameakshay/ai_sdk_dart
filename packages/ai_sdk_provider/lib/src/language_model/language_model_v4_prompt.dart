import 'language_model_v4_content.dart';

/// Message roles supported by language model prompts.
enum LanguageModelV4Role { system, user, assistant, tool }

/// A single prompt message in provider-native format.
class LanguageModelV4Message {
  const LanguageModelV4Message({required this.role, required this.content});

  final LanguageModelV4Role role;
  final List<LanguageModelV4ContentPart> content;
}

/// Normalized prompt for [LanguageModelV4] calls.
///
/// Contains optional [system] instruction and [messages].
class LanguageModelV4Prompt {
  const LanguageModelV4Prompt({this.system, required this.messages});

  final String? system;
  final List<LanguageModelV4Message> messages;
}
