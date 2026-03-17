import 'language_model_v3_stream_part.dart';

/// Streaming generation result wrapper.
class LanguageModelV3StreamResult {
  const LanguageModelV3StreamResult({required this.stream, this.rawResponse});

  /// The provider stream of structured parts.
  final Stream<LanguageModelV3StreamPart> stream;

  /// Optional raw response object from the provider SDK/HTTP layer.
  final Object? rawResponse;
}
