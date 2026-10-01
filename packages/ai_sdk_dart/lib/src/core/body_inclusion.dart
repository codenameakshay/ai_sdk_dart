import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Controls retention and delivery of provider payloads that may contain
/// prompts, attachments, credentials, or other content-heavy data.
class BodyInclusionPolicy {
  const BodyInclusionPolicy({
    this.requestBody = false,
    this.responseBody = false,
    this.rawChunks = false,
  });

  const BodyInclusionPolicy.none()
    : requestBody = false,
      responseBody = false,
      rawChunks = false;

  const BodyInclusionPolicy.all()
    : requestBody = true,
      responseBody = true,
      rawChunks = true;

  final bool requestBody;
  final bool responseBody;
  final bool rawChunks;
}

/// Strips the response body from [metadata] unless retained by [policy].
LanguageModelV4ResponseMetadata? filterResponseMetadata(
  LanguageModelV4ResponseMetadata? metadata,
  BodyInclusionPolicy policy,
) => metadata == null
    ? null
    : LanguageModelV4ResponseMetadata(
        id: metadata.id,
        modelId: metadata.modelId,
        timestamp: metadata.timestamp,
        headers: metadata.headers,
        body: policy.responseBody ? metadata.body : null,
      );

/// Removes provider payloads from actionable API errors unless explicitly
/// retained by the caller's response-body policy.
Object filterBodyBearingError(Object error, BodyInclusionPolicy policy) {
  if (policy.responseBody || error is! AiApiCallError) return error;
  return AiApiCallError(
    error.message,
    statusCode: error.statusCode,
    url: error.url,
    responseHeaders: error.responseHeaders,
    type: error.type,
    code: error.code,
    isRetryable: error.isRetryable,
  );
}
