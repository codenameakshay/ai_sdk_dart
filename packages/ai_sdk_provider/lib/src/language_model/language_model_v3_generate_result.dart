import '../shared/provider_metadata.dart';
import 'language_model_v3_content.dart';
import 'language_model_v3_finish_reason.dart';
import 'language_model_v3_usage.dart';

/// Response metadata from the underlying provider.
class LanguageModelV3ResponseMetadata {
  const LanguageModelV3ResponseMetadata({
    this.id,
    this.modelId,
    this.timestamp,
    this.headers,
    this.body,
    this.requestBody,
  });

  final String? id;
  final String? modelId;
  final DateTime? timestamp;
  final Map<String, String>? headers;
  final Object? body;
  final Object? requestBody;
}

/// Non-streaming generation result from a LanguageModelV3 provider.
class LanguageModelV3GenerateResult {
  const LanguageModelV3GenerateResult({
    this.content = const [],
    this.finishReason = LanguageModelV3FinishReason.unknown,
    this.rawFinishReason,
    this.usage,
    this.warnings = const [],
    this.response,
    this.providerMetadata,
  });

  final List<LanguageModelV3ContentPart> content;
  final LanguageModelV3FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV3Usage? usage;
  final List<String> warnings;
  final LanguageModelV3ResponseMetadata? response;
  final ProviderMetadata? providerMetadata;
}
