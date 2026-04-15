import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [transcribe].
///
/// Contains the transcribed [text].
class TranscribeResult {
  const TranscribeResult({required this.text});

  /// The transcribed text.
  final String text;
}

/// Transcribes [audio] bytes using the provided [model].
///
/// Mirrors `experimental_transcribe` from the JS AI SDK v6.
Future<TranscribeResult> transcribe({
  required TranscriptionModelV1 model,
  required Uint8List audio,
  String? audioMediaType,
  String? language,
  String? prompt,
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
  Duration? timeout,
}) async {
  final call = model.doGenerate(
    TranscriptionModelV1CallOptions(
      audio: audio,
      audioMediaType: audioMediaType,
      language: language,
      prompt: prompt,
      headers: headers,
      providerOptions: providerOptions,
    ),
  );
  final result = await (timeout != null ? call.timeout(timeout) : call);
  return TranscribeResult(text: result.text);
}
