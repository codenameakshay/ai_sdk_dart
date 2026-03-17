import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Base class for all AI SDK errors.
sealed class AiSdkError implements Exception {
  const AiSdkError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class AiApiCallError extends AiSdkError {
  const AiApiCallError(super.message);
}

class AiNoSuchToolError extends AiSdkError {
  const AiNoSuchToolError(super.message);
}

class AiInvalidToolInputError extends AiSdkError {
  const AiInvalidToolInputError(super.message);
}

class AiNoContentGeneratedError extends AiSdkError {
  const AiNoContentGeneratedError(super.message);
}

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
