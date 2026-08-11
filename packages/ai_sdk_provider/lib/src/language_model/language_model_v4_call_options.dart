import '../shared/json_value.dart';
import 'language_model_v3_prompt.dart';
import 'language_model_v3_tool.dart';
import 'language_model_v3_tool_choice.dart';

/// Call options for [LanguageModelV3] generation.
///
/// Contains [prompt], [tools], [toolChoice], [maxOutputTokens], [temperature],
/// and other provider-agnostic settings.
class LanguageModelV3CallOptions {
  const LanguageModelV3CallOptions({
    required this.prompt,
    this.tools = const [],
    this.providerDefinedTools = const [],
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
    this.outputSchema,
  });

  final LanguageModelV3Prompt prompt;
  final List<LanguageModelV3FunctionTool> tools;
  final List<LanguageModelV3ProviderDefinedTool> providerDefinedTools;
  final LanguageModelV3ToolChoice? toolChoice;
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

  /// JSON Schema for the expected response structure.
  ///
  /// When set, capable providers (e.g. OpenAI with `response_format:
  /// json_schema`) use native structured-output APIs rather than relying solely
  /// on prompt engineering. Providers that do not implement native structured
  /// output safely ignore this field.
  final Map<String, dynamic>? outputSchema;
}
