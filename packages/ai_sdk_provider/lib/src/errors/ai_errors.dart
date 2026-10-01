import 'dart:convert';

import '../language_model/language_model_v4_generate_result.dart';
import '../language_model/language_model_v4_usage.dart';

/// Base class for all AI SDK errors.
sealed class AiSdkError implements Exception {
  const AiSdkError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A provider returned embeddings that cannot be associated with every input.
class AiInvalidEmbeddingResponseError extends AiSdkError {
  const AiInvalidEmbeddingResponseError(
    super.message, {
    required this.expectedCount,
    required this.actualCount,
    this.index,
  });

  final int expectedCount;
  final int actualCount;
  final int? index;
}

/// Thrown when a provider API call fails.
///
/// For non-2xx HTTP responses this carries the provider's parsed [message]
/// along with the [statusCode], request [url], raw [responseBody], parsed
/// provider [type]/[code] fields, [responseHeaders], whether the failure
/// [isRetryable], and the underlying [cause] (typically the `DioException`).
///
/// Mirrors `APICallError` from the JS AI SDK. Use [AiApiCallError.fromResponse]
/// to build one from a raw provider error response.
class AiApiCallError extends AiSdkError {
  const AiApiCallError(
    super.message, {
    this.statusCode,
    this.url,
    this.responseBody,
    this.responseHeaders,
    this.type,
    this.code,
    this.isRetryable = false,
    this.cause,
  });

  /// HTTP status code of the failing response, if known.
  final int? statusCode;

  /// The request URL that failed, if known.
  final String? url;

  /// The raw response body (decoded to a string) for debugging.
  final String? responseBody;

  /// The response headers, if captured.
  final Map<String, String>? responseHeaders;

  /// Provider-specific error `type` (e.g. `invalid_request_error`), or the
  /// Google `status` string, when present.
  final String? type;

  /// Provider-specific error `code` (e.g. `unknown_parameter`), when present.
  final String? code;

  /// Whether the request can reasonably be retried (408/409/429/5xx).
  final bool isRetryable;

  /// The underlying error (typically a `DioException`), when wrapped.
  final Object? cause;

  static bool isInstance(Object error) => error is AiApiCallError;

  /// Builds an [AiApiCallError] from a materialized provider HTTP error
  /// response. Transport-agnostic: [body] may be a decoded JSON [Map], a raw
  /// JSON or plain [String], a `List<int>` of bytes, or `null`.
  ///
  /// Handles the error-body shapes used across providers:
  /// - OpenAI / openai-compatible / Groq / Mistral: `{error:{message,type,code}}`
  /// - Anthropic: `{type:"error",error:{type,message}}`
  /// - Google: `{error:{code,message,status}}` (status preserved as [type])
  /// - Cohere: `{message}`
  /// - Ollama: `{error:"..."}`
  factory AiApiCallError.fromResponse({
    required int? statusCode,
    String? url,
    Object? body,
    Map<String, String>? responseHeaders,
    String? provider,
    Object? cause,
  }) {
    String? rawBody;
    Map<String, dynamic>? map;

    Object? decoded = body;
    if (decoded is List<int>) {
      try {
        decoded = utf8.decode(decoded);
      } catch (_) {
        decoded = null;
      }
    }
    if (decoded is String) {
      rawBody = decoded;
      final trimmed = decoded.trim();
      if (trimmed.isNotEmpty) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is Map) map = parsed.cast<String, dynamic>();
        } catch (_) {
          // Not JSON — keep [rawBody] as the message fallback below.
        }
      }
    } else if (decoded is Map) {
      map = decoded.cast<String, dynamic>();
      rawBody = jsonEncode(decoded);
    }

    String? message;
    String? type;
    String? code;

    if (map != null) {
      final error = map['error'];
      if (error is Map) {
        final e = error.cast<String, dynamic>();
        message = e['message']?.toString();
        type = e['type']?.toString() ?? e['status']?.toString();
        code = e['code']?.toString();
      } else if (error is String) {
        message = error;
      }
      message ??= map['message']?.toString();
    }

    if (message == null || message.isEmpty) {
      if (map == null && rawBody != null && rawBody.trim().isNotEmpty) {
        // Non-JSON string body — surface it verbatim.
        message = rawBody.trim();
      } else {
        final label = provider != null ? '$provider ' : '';
        message =
            '${label}API error${statusCode != null ? ' ($statusCode)' : ''}';
      }
    }

    final retryable =
        statusCode != null &&
        (statusCode == 408 ||
            statusCode == 409 ||
            statusCode == 429 ||
            statusCode >= 500);

    return AiApiCallError(
      message,
      statusCode: statusCode,
      url: url,
      responseBody: rawBody,
      responseHeaders: responseHeaders,
      type: type,
      code: code,
      isRetryable: retryable,
      cause: cause,
    );
  }
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

/// Thrown when the caller aborts an in-flight SDK operation.
class AiOperationCancelledError extends AiSdkError {
  const AiOperationCancelledError([super.message = 'Operation cancelled.']);

  static bool isInstance(Object error) => error is AiOperationCancelledError;
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
  final LanguageModelV4ResponseMetadata? response;
  final LanguageModelV4Usage? usage;
  final Object? cause;

  static bool isInstance(Object error) => error is AiNoObjectGeneratedError;
}

/// Thrown when image generation produces no output.
///
/// Mirrors `AI_NoImageGeneratedError` from the JS AI SDK v6.
class AiNoImageGeneratedError extends AiSdkError {
  const AiNoImageGeneratedError({required String message, this.cause})
    : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoImageGeneratedError;
}

/// Thrown when speech synthesis produces no audio output.
///
/// Mirrors `AI_NoSpeechGeneratedError` from the JS AI SDK v6.
class AiNoSpeechGeneratedError extends AiSdkError {
  const AiNoSpeechGeneratedError({required String message, this.cause})
    : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoSpeechGeneratedError;
}

/// Thrown when audio transcription produces no text output.
///
/// Mirrors `AI_NoTranscriptGeneratedError` from the JS AI SDK v6.
class AiNoTranscriptGeneratedError extends AiSdkError {
  const AiNoTranscriptGeneratedError({required String message, this.cause})
    : super(message);

  final Object? cause;

  static bool isInstance(Object error) => error is AiNoTranscriptGeneratedError;
}

/// Thrown when all retry attempts are exhausted.
///
/// Mirrors `AI_RetryError` from the JS AI SDK v6.
/// [errors] contains the errors from each attempt in order.
class AiRetryError extends AiSdkError {
  const AiRetryError({
    required String message,
    required this.attempts,
    required this.lastError,
    this.errors = const [],
  }) : super(message);

  /// Number of attempts made (including the first try).
  final int attempts;

  /// The error from the final attempt.
  final Object lastError;

  /// The errors from each attempt, in order.
  ///
  /// The SDK populates this list when [withRetry] exhausts retryable provider
  /// failures. It is optional for compatibility with manually constructed
  /// errors from earlier releases.
  final List<Object> errors;

  static bool isInstance(Object error) => error is AiRetryError;
}
