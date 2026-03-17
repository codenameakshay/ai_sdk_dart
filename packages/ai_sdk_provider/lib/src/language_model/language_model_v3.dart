import 'language_model_v3_call_options.dart';
import 'language_model_v3_generate_result.dart';
import 'language_model_v3_stream_result.dart';

/// Core provider contract for language models.
///
/// Provider packages (OpenAI, Anthropic, Google, etc.) implement this
/// interface so the `ai` core package can operate provider-agnostically.
abstract interface class LanguageModelV3 {
  /// Specification version this model implements.
  String get specificationVersion;

  /// Provider identifier (e.g., 'openai', 'anthropic').
  String get provider;

  /// Provider-specific model identifier.
  String get modelId;

  /// Generate a complete, non-streaming response.
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  );

  /// Generate a streaming response.
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  );
}
