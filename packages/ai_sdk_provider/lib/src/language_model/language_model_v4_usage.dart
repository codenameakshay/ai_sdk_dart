/// Token usage statistics for a language model call.
class LanguageModelV3Usage {
  const LanguageModelV3Usage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.inputTokenDetails,
    this.outputTokenDetails,
    this.raw,
  });

  /// Total number of input (prompt) tokens used.
  final int? inputTokens;

  /// Total number of output (completion) tokens used.
  final int? outputTokens;

  /// Total tokens used (input + output).
  final int? totalTokens;

  /// Detailed breakdown of input token usage.
  final LanguageModelV3InputTokenDetails? inputTokenDetails;

  /// Detailed breakdown of output token usage.
  final LanguageModelV3OutputTokenDetails? outputTokenDetails;

  /// Raw usage data from the provider.
  final Object? raw;

  @override
  String toString() =>
      'LanguageModelV3Usage(input: $inputTokens, output: $outputTokens, total: $totalTokens)';
}

/// Detailed input token breakdown.
class LanguageModelV3InputTokenDetails {
  const LanguageModelV3InputTokenDetails({
    this.noCacheTokens,
    this.cacheReadTokens,
    this.cacheWriteTokens,
  });

  /// Non-cached input tokens.
  final int? noCacheTokens;

  /// Cached tokens that were read (cheaper).
  final int? cacheReadTokens;

  /// Tokens written to cache.
  final int? cacheWriteTokens;
}

/// Detailed output token breakdown.
class LanguageModelV3OutputTokenDetails {
  const LanguageModelV3OutputTokenDetails({
    this.textTokens,
    this.reasoningTokens,
  });

  /// Text tokens generated.
  final int? textTokens;

  /// Reasoning tokens generated (for reasoning models).
  final int? reasoningTokens;
}
