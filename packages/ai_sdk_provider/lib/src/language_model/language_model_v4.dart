import 'dart:async';

import 'language_model_v4_call_options.dart';
import 'language_model_v4_generate_result.dart';
import 'language_model_v4_stream_result.dart';

/// Core provider contract for language models.
///
/// Provider packages (OpenAI, Anthropic, Google, etc.) implement this
/// interface so the `ai` core package can operate provider-agnostically.
abstract class LanguageModelV4 {
  const LanguageModelV4();

  /// Specification version this model implements.
  String get specificationVersion => 'v4';

  /// Provider identifier (e.g., 'openai', 'anthropic').
  String get provider;

  /// Provider-specific model identifier.
  String get modelId;

  /// URL patterns this model can consume without the SDK downloading them.
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  /// Generate a complete, non-streaming response.
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  );

  /// Generate a streaming response.
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  );
}
