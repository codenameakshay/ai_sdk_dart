import 'dart:typed_data';

import '../shared/json_value.dart';

/// Call options for transcription models.
class TranscriptionModelV1CallOptions {
  const TranscriptionModelV1CallOptions({
    required this.audio,
    this.audioMediaType,
    this.language,
    this.prompt,
    this.headers,
    this.providerOptions,
  });

  final Uint8List audio;
  final String? audioMediaType;
  final String? language;
  final String? prompt;
  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
}
