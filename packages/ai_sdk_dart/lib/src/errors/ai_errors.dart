import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// The AI SDK error hierarchy lives in `ai_sdk_provider` so that provider
/// packages (which depend on `ai_sdk_provider`, not on `ai_sdk_dart`) can throw
/// the same typed errors — in particular [AiApiCallError] for non-2xx provider
/// HTTP responses. This file re-exports the hierarchy to preserve the
/// `ai_sdk_dart` public surface and existing internal imports.
export 'package:ai_sdk_provider/ai_sdk_provider.dart'
    show
        AiSdkError,
        AiApiCallError,
        AiNoSuchToolError,
        AiInvalidToolInputError,
        AiNoContentGeneratedError,
        AiNoObjectGeneratedError,
        AiToolCallRepairError,
        AiNoImageGeneratedError,
        AiNoSpeechGeneratedError,
        AiNoTranscriptGeneratedError,
        AiRetryError,
        AiDownloadError;

/// Thrown when the caller aborts an in-flight SDK operation.
class AiOperationCancelledError implements Exception {
  const AiOperationCancelledError([
    this.message = 'Operation cancelled.',
  ]);

  final String message;

  @override
  String toString() => '$runtimeType: $message';

  static bool isInstance(Object error) => error is AiOperationCancelledError;
}
