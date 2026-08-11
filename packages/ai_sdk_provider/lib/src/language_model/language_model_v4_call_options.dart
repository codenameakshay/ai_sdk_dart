import '../shared/json_value.dart';
import 'language_model_v4_prompt.dart';
import 'language_model_v4_response_format.dart';
import 'language_model_v4_tool.dart';
import 'language_model_v4_tool_choice.dart';

/// Call options for [LanguageModelV4] generation.
///
/// Contains [prompt], [tools], [toolChoice], [maxOutputTokens], [temperature],
/// and other provider-agnostic settings.
class LanguageModelV4CallOptions {
  const LanguageModelV4CallOptions({
    required this.prompt,
    this.tools = const [],
    this.toolChoice,
    this.maxOutputTokens,
    this.temperature,
    this.topP,
    this.topK,
    this.presencePenalty,
    this.frequencyPenalty,
    this.stopSequences = const [],
    this.seed,
    this.headers,
    this.providerOptions,
    this.responseFormat,
    this.includeRawChunks = false,
    this.abortSignal,
    this.reasoning = LanguageModelV4Reasoning.providerDefault,
  });

  final LanguageModelV4Prompt prompt;
  final List<LanguageModelV4Tool> tools;
  final LanguageModelV4ToolChoice? toolChoice;
  final int? maxOutputTokens;
  final double? temperature;
  final double? topP;
  final int? topK;
  final double? presencePenalty;
  final double? frequencyPenalty;
  final List<String> stopSequences;
  final int? seed;
  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
  final LanguageModelV4ResponseFormat? responseFormat;
  final bool includeRawChunks;
  final LanguageModelV4AbortSignal? abortSignal;
  final LanguageModelV4Reasoning reasoning;
}

extension LanguageModelV4ToolGroups on LanguageModelV4CallOptions {
  Iterable<LanguageModelV4FunctionTool> get functionTools =>
      tools.whereType<LanguageModelV4FunctionTool>();

  Iterable<LanguageModelV4ProviderDefinedTool> get providerTools =>
      tools.whereType<LanguageModelV4ProviderDefinedTool>();
}

/// Provider-facing cancellation signal.
abstract interface class LanguageModelV4AbortSignal {
  bool get isCancelled;
  Future<void> get onCancelled;
}

/// Provider-independent reasoning effort.
enum LanguageModelV4Reasoning {
  providerDefault,
  none,
  minimal,
  low,
  medium,
  high,
  xhigh,
}
