/// Typed provider options for Anthropic language models.
///
/// Pass the result of [toMap] in [LanguageModelV3CallOptions.providerOptions]
/// under the `'anthropic'` key:
///
/// ```dart
/// await generateText(
///   model: anthropic('claude-3-7-sonnet-20250219'),
///   prompt: 'Think step by step…',
///   providerOptions: {
///     'anthropic': AnthropicThinkingOptions(
///       budgetTokens: 10000,
///     ).toMap(),
///   },
/// );
/// ```
class AnthropicThinkingOptions {
  const AnthropicThinkingOptions({
    this.budgetTokens,
    this.enabled = true,
    this.speed,
  });

  /// Token budget for extended thinking.
  ///
  /// When set, the model may use up to this many tokens for internal reasoning
  /// before producing its response. Must be at least 1024.
  ///
  /// If [enabled] is `false` this field is ignored.
  final int? budgetTokens;

  /// Whether extended thinking is enabled.
  ///
  /// Defaults to `true`. Set to `false` to explicitly disable thinking and
  /// prefer a faster, non-thinking response.
  final bool enabled;

  /// Request a faster response at the cost of thinking depth.
  ///
  /// When set to `'fast'`, thinking is disabled ([enabled] is treated as
  /// `false`). Use this when latency matters more than reasoning quality.
  /// Any other value (or `null`) uses the default behaviour determined by
  /// [enabled] and [budgetTokens].
  final String? speed;

  /// Serialises this object to the `thinking` map expected by the Anthropic API.
  ///
  /// Returns a map suitable for use as the value of `providerOptions['anthropic']`.
  Map<String, dynamic> toMap() {
    final isEnabled = speed == 'fast' ? false : enabled;
    return {
      'thinking': {
        'type': isEnabled ? 'enabled' : 'disabled',
        if (isEnabled && budgetTokens != null) 'budget_tokens': budgetTokens,
      },
    };
  }
}

/// Typed provider options for Anthropic language models — general purpose.
///
/// Wraps common Anthropic-specific request parameters.
///
/// ```dart
/// await generateText(
///   model: anthropic('claude-3-5-sonnet-20241022'),
///   prompt: 'Hello',
///   providerOptions: {
///     'anthropic': AnthropicLanguageModelOptions(
///       thinking: AnthropicThinkingOptions(budgetTokens: 5000),
///     ).toMap(),
///   },
/// );
/// ```
class AnthropicLanguageModelOptions {
  const AnthropicLanguageModelOptions({this.thinking});

  /// Extended thinking configuration.
  final AnthropicThinkingOptions? thinking;

  /// Serialises this object to a map for use in [providerOptions].
  Map<String, dynamic> toMap() => {
    if (thinking != null) ...thinking!.toMap(),
  };
}
