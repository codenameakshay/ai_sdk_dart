/// Standardized reasoning effort levels (AI SDK v7).
///
/// A single, portable setting that controls model reasoning behavior across
/// providers. Each provider maps these levels to its native reasoning API:
/// providers exposing enums map directly (coercing to the nearest supported
/// level with a warning where needed); providers using token budgets receive a
/// mapped percentage of the maximum output tokens.
///
/// Mirrors the v7 top-level `reasoning` option on `generateText` / `streamText`.
/// Provider-specific `providerOptions` reasoning settings take precedence over
/// this value when both are supplied.
enum LanguageModelV3ReasoningEffort {
  /// Use the provider's default reasoning behavior (equivalent to omitting the
  /// option entirely).
  providerDefault,

  /// Disable reasoning where the provider supports turning it off.
  none,

  /// Minimal reasoning effort — fastest, most concise.
  minimal,

  /// Low reasoning effort.
  low,

  /// Medium reasoning effort.
  medium,

  /// High reasoning effort.
  high,

  /// Maximum reasoning effort — slowest, most thorough.
  xhigh,
}
