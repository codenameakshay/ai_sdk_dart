import '../shared/json_value.dart';
import '../shared/provider_metadata.dart';
import 'language_model_v4_content.dart';
import 'language_model_v4_finish_reason.dart';
import 'language_model_v4_usage.dart';
import 'language_model_v4_warning.dart';

/// Request metadata from the underlying provider.
///
/// Contains the provider request [body].
class LanguageModelV4RequestMetadata {
  const LanguageModelV4RequestMetadata({this.body});

  final JsonValue body;
}

/// Response metadata from the underlying provider.
///
/// Contains [id], [modelId], [timestamp], [headers], and [body].
class LanguageModelV4ResponseMetadata {
  const LanguageModelV4ResponseMetadata({
    this.id,
    this.modelId,
    this.timestamp,
    this.headers,
    this.body,
  });

  final String? id;
  final String? modelId;
  final DateTime? timestamp;
  final Map<String, String>? headers;
  final JsonValue body;
}

/// Non-streaming generation result from a [LanguageModelV4] provider.
///
/// Contains [content], [finishReason], [usage], [warnings], [request],
/// and [response].
class LanguageModelV4GenerateResult {
  const LanguageModelV4GenerateResult({
    this.content = const [],
    this.finishReason = LanguageModelV4FinishReason.unknown,
    this.rawFinishReason,
    LanguageModelV4Usage? usage,
    this.warnings = const [],
    this.request,
    this.response,
    this.providerMetadata,
  }) : usage = usage ?? const LanguageModelV4Usage();

  final List<LanguageModelV4ContentPart> content;
  final LanguageModelV4FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV4Usage usage;
  final List<LanguageModelV4Warning> warnings;
  final LanguageModelV4RequestMetadata? request;
  final LanguageModelV4ResponseMetadata? response;
  final ProviderMetadata? providerMetadata;
}
