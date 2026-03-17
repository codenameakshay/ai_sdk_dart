import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result from `generateSpeech`.
class GenerateSpeechResult {
  const GenerateSpeechResult({required this.audio, required this.mediaType});

  /// Raw audio bytes.
  final Uint8List audio;

  /// IANA media type of the audio (e.g. `'audio/mpeg'`).
  final String mediaType;
}

/// Converts [text] to speech using the provided [model].
///
/// Mirrors `experimental_generateSpeech` from the JS AI SDK v6.
Future<GenerateSpeechResult> generateSpeech({
  required SpeechModelV1 model,
  required String text,
  String? voice,
  String? format,
  double? speed,
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
}) async {
  final result = await model.doGenerate(
    SpeechModelV1CallOptions(
      text: text,
      voice: voice,
      format: format,
      speed: speed,
      headers: headers,
      providerOptions: providerOptions,
    ),
  );
  return GenerateSpeechResult(audio: result.audio, mediaType: result.mediaType);
}
