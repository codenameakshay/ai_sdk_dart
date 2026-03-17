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
