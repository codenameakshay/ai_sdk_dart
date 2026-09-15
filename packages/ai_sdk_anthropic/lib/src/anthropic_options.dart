/// Typed provider options for Anthropic language models.
///
/// Pass the result of [toMap] in [LanguageModelV4CallOptions.providerOptions]
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

/// Typed prompt cache control for Anthropic messages and content parts.
class AnthropicCacheControlOptions {
  const AnthropicCacheControlOptions({this.ttl});

  /// Cache lifetime. Anthropic supports `'5m'` and `'1h'`.
  final String? ttl;

  /// Serialises this object to the Anthropic `cache_control` map.
  Map<String, dynamic> toMap() => {
    'cache_control': {'type': 'ephemeral', if (ttl != null) 'ttl': ttl},
  };
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
  const AnthropicLanguageModelOptions({this.thinking, this.cacheControl});

  /// Extended thinking configuration.
  final AnthropicThinkingOptions? thinking;

  /// Prompt cache breakpoint configuration.
  final AnthropicCacheControlOptions? cacheControl;

  /// Serialises this object to a map for use in [providerOptions].
  Map<String, dynamic> toMap() => {
    if (thinking != null) ...thinking!.toMap(),
    if (cacheControl != null) ...cacheControl!.toMap(),
  };
}
