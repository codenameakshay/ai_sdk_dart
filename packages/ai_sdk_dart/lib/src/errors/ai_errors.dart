import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Base class for all AI SDK errors.
sealed class AiSdkError implements Exception {
  const AiSdkError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a provider API call fails.
class AiApiCallError extends AiSdkError {
  const AiApiCallError(super.message);
}

/// Thrown when a requested tool is not found.
class AiNoSuchToolError extends AiSdkError {
  const AiNoSuchToolError(super.message);
}

/// Thrown when tool input fails validation.
class AiInvalidToolInputError extends AiSdkError {
  const AiInvalidToolInputError(super.message);
}

/// Thrown when the model produces no content.
class AiNoContentGeneratedError extends AiSdkError {
  const AiNoContentGeneratedError(super.message);
}

/// Thrown when structured object generation fails.
///
/// Contains [text], [response], [usage], and [cause].
/// Use [isInstance] to check if an error is this type.
class AiNoObjectGeneratedError extends AiSdkError {
  const AiNoObjectGeneratedError({
    required String message,
    required this.text,
    required this.response,
    required this.usage,
    this.cause,
  }) : super(message);

  final String text;
  final LanguageModelV3ResponseMetadata? response;
  final LanguageModelV3Usage? usage;
  final Object? cause;

  static bool isInstance(Object error) => error is AiNoObjectGeneratedError;
}

/// Thrown when a tool call cannot be repaired after a validation failure.
///
/// Mirrors `AI_ToolCallRepairError` from the JS AI SDK v6.
/// Contains the [toolCall] that failed, the [cause], and any [repairAttempts]
/// made before giving up.
class AiToolCallRepairError extends AiSdkError {
  const AiToolCallRepairError({
    required String message,
    required this.toolName,
    required this.cause,
    this.repairAttempts = 0,
  }) : super(message);

  /// The name of the tool whose call could not be repaired.
  final String toolName;

  /// The underlying error that triggered the repair attempt.
  final Object cause;

  /// How many repair attempts were made before giving up.
  final int repairAttempts;

  static bool isInstance(Object error) => error is AiToolCallRepairError;
}

/// Thrown when image generation produces no output.
///
/// Mirrors `AI_NoImageGeneratedError` from the JS AI SDK v6.
class AiNoImageGeneratedError extends AiSdkError {
  const AiNoImageGeneratedError({
    required String message,
    this.cause,
  }) : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoImageGeneratedError;
}

/// Thrown when video generation produces no output.
///
/// Mirrors `AI_NoVideoGeneratedError` from the JS AI SDK v6.
class AiNoVideoGeneratedError extends AiSdkError {
  const AiNoVideoGeneratedError({
    required String message,
    this.cause,
  }) : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoVideoGeneratedError;
}

/// Thrown when speech synthesis produces no audio output.
///
/// Mirrors `AI_NoSpeechGeneratedError` from the JS AI SDK v6.
class AiNoSpeechGeneratedError extends AiSdkError {
  const AiNoSpeechGeneratedError({
    required String message,
    this.cause,
  }) : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoSpeechGeneratedError;
}

/// Thrown when audio transcription produces no text output.
///
/// Mirrors `AI_NoTranscriptGeneratedError` from the JS AI SDK v6.
class AiNoTranscriptGeneratedError extends AiSdkError {
  const AiNoTranscriptGeneratedError({
    required String message,
    this.cause,
  }) : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoTranscriptGeneratedError;
}

/// Thrown when all retry attempts are exhausted.
///
/// Mirrors `AI_RetryError` from the JS AI SDK v6.
/// [attempts] contains the errors from each attempt in order.
class AiRetryError extends AiSdkError {
  const AiRetryError({
    required String message,
    required this.attempts,
    required this.lastError,
  }) : super(message);

  /// Number of attempts made (including the first try).
  final int attempts;

  /// The error from the final attempt.
  final Object lastError;

  static bool isInstance(Object error) => error is AiRetryError;
}

/// Thrown when a required file or URL download fails.
///
/// Mirrors `AI_DownloadError` from the JS AI SDK v6.
/// Typically raised when a transcription URL cannot be fetched.
class AiDownloadError extends AiSdkError {
  const AiDownloadError({
    required String message,
    required this.url,
    this.statusCode,
    this.cause,
  }) : super(message);

  /// The URL that failed to download.
  final String url;

  /// HTTP status code, if available.
  final int? statusCode;

  /// The underlying error.
  final Object? cause;

  static bool isInstance(Object error) => error is AiDownloadError;
}
