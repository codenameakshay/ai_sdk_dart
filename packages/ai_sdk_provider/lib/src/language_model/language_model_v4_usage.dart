/// Token usage statistics for a language model call.
class LanguageModelV4Usage {
  const LanguageModelV4Usage({
    this.inputTokens = const LanguageModelV4InputTokenUsage(),
    this.outputTokens = const LanguageModelV4OutputTokenUsage(),
    this.raw,
  });

  /// Grouped input (prompt) token usage.
  final LanguageModelV4InputTokenUsage inputTokens;

  /// Grouped output (completion) token usage.
  final LanguageModelV4OutputTokenUsage outputTokens;

  /// Raw usage data from the provider.
  final Object? raw;

  @override
  String toString() =>
      'LanguageModelV4Usage(input: ${inputTokens.total}, output: ${outputTokens.total})';
}

/// Grouped input token usage.
class LanguageModelV4InputTokenUsage {
  const LanguageModelV4InputTokenUsage({
    this.total,
    this.noCache,
    this.cacheRead,
    this.cacheWrite,
  });

  /// Total input tokens used.
  final int? total;

  /// Non-cached input tokens.
  final int? noCache;

  /// Cached tokens that were read (cheaper).
  final int? cacheRead;

  /// Tokens written to cache.
  final int? cacheWrite;
}

/// Grouped output token usage.
class LanguageModelV4OutputTokenUsage {
  const LanguageModelV4OutputTokenUsage({
    this.total,
    this.text,
    this.reasoning,
  });

  /// Total output tokens used.
  final int? total;

  /// Text tokens generated.
  final int? text;

  /// Reasoning tokens generated (for reasoning models).
  final int? reasoning;
}
