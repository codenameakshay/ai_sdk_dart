import 'transcription_model_v1_call_options.dart';

/// Transcription result.
class TranscriptionModelV1GenerateResult {
  const TranscriptionModelV1GenerateResult({required this.text});

  final String text;
}

/// Provider contract for transcription (speech-to-text) models.
///
/// Used by [transcribe] from ai_sdk_dart.
abstract interface class TranscriptionModelV1 {
  String get specificationVersion;
  String get provider;
  String get modelId;

  Future<TranscriptionModelV1GenerateResult> doGenerate(
    TranscriptionModelV1CallOptions options,
  );
}
