import 'dart:typed_data';

import 'speech_model_v1_call_options.dart';

/// Speech synthesis result.
class SpeechModelV1GenerateResult {
  const SpeechModelV1GenerateResult({
    required this.audio,
    required this.mediaType,
  });

  final Uint8List audio;
  final String mediaType;
}

/// Provider contract for speech models.
abstract interface class SpeechModelV1 {
  String get specificationVersion;
  String get provider;
  String get modelId;

  Future<SpeechModelV1GenerateResult> doGenerate(
    SpeechModelV1CallOptions options,
  );
}
