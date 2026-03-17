import '../shared/json_value.dart';

/// Call options for text-to-speech models.
class SpeechModelV1CallOptions {
  const SpeechModelV1CallOptions({
    required this.text,
    this.voice,
    this.format,
    this.speed,
    this.headers,
    this.providerOptions,
  });

  final String text;
  final String? voice;
  final String? format;
  final double? speed;
  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
}
