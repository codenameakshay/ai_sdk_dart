import 'language_model_v4_stream_part.dart';
import 'language_model_v4_generate_result.dart';
import 'language_model_v4_warning.dart';

/// Streaming generation result wrapper.
class LanguageModelV4StreamResult {
  const LanguageModelV4StreamResult({
    required this.stream,
    this.warnings = const [],
    this.request,
    this.response,
  });

  /// The provider stream of structured parts.
  final Stream<LanguageModelV4StreamPart> stream;

  /// Warnings surfaced while preparing or executing the stream.
  final List<LanguageModelV4Warning> warnings;

  /// Request metadata from the provider call.
  final LanguageModelV4RequestMetadata? request;

  /// Response metadata from the provider call.
  final LanguageModelV4ResponseMetadata? response;
}
