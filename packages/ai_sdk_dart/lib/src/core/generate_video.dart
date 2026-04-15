import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [experimentalGenerateVideo].
///
/// Contains [videos] and optional [warnings]. Use [video] for the first result.
class GenerateVideoResult {
  const GenerateVideoResult({required this.videos, this.warnings = const []});

  final List<GeneratedVideo> videos;
  final List<String> warnings;

  /// Convenience accessor for the first generated video.
  GeneratedVideo get video => videos.first;
}

/// Generates a video from a text prompt.
///
/// This is an experimental API — the interface may change in future versions.
/// Mirrors `experimental_generateVideo` from the JS AI SDK v6.
///
/// Example:
/// ```dart
/// final result = await experimentalGenerateVideo(
///   model: videoModel,
///   prompt: 'A sunset timelapse over the ocean',
///   durationSeconds: 5,
///   aspectRatio: '16:9',
/// );
/// final video = result.video;
/// print('Generated ${video.bytes.length} bytes (${video.mediaType})');
/// ```
Future<GenerateVideoResult> experimentalGenerateVideo({
  required VideoModelV1 model,
  required String prompt,
  double? durationSeconds,
  String? aspectRatio,
  int? fps,
  int? seed,
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
  Duration? timeout,
}) async {
  final call = model.doGenerate(
    VideoModelV1CallOptions(
      prompt: prompt,
      durationSeconds: durationSeconds,
      aspectRatio: aspectRatio,
      fps: fps,
      seed: seed,
      headers: headers,
      providerOptions: providerOptions,
    ),
  );
  final result = await (timeout != null ? call.timeout(timeout) : call);

  return GenerateVideoResult(
    videos: result.videos,
    warnings: result.warnings,
  );
}
