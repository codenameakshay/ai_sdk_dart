/// Typed provider options for OpenAI language models.
///
/// Pass the result of [toMap] in [LanguageModelV3CallOptions.providerOptions]
/// under the `'openai'` key:
///
/// ```dart
/// await generateText(
///   model: openai('o3-mini'),
///   prompt: 'Solve this problem',
///   providerOptions: {
///     'openai': OpenAILanguageModelOptions(
///       reasoningEffort: 'high',
///     ).toMap(),
///   },
/// );
/// ```
class OpenAILanguageModelOptions {
  const OpenAILanguageModelOptions({
    this.reasoningEffort,
    this.reasoningSummary,
  });

  /// Controls how much reasoning the model does before responding.
  ///
  /// Supported values: `'low'`, `'medium'`, `'high'`.
  /// Only supported by reasoning models (e.g. `o3`, `o3-mini`, `o1`).
  final String? reasoningEffort;

  /// Controls the format of the reasoning summary returned by the model.
  ///
  /// Supported values: `'auto'`, `'concise'`, `'detailed'`.
  /// Only supported by reasoning models that expose a reasoning summary.
  final String? reasoningSummary;

  /// Serialises this object to the map format expected by the OpenAI API.
  Map<String, dynamic> toMap() => {
    if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    if (reasoningSummary != null) 'reasoning_summary': reasoningSummary,
  };
}
