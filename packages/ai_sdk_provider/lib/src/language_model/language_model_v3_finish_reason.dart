/// The reason a language model generation finished.
enum LanguageModelV3FinishReason {
  /// The model reached a natural stop point.
  stop,

  /// The model reached the maximum token limit.
  length,

  /// The model stopped due to a content filter.
  contentFilter,

  /// The model stopped because it made tool calls.
  toolCalls,

  /// The model stopped due to an error.
  error,

  /// The model stopped for another reason.
  other,

  /// The finish reason is unknown.
  unknown,
}
