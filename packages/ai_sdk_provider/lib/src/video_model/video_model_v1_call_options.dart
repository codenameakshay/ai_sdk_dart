import '../shared/json_value.dart';

/// Call options for video generation models.
class VideoModelV1CallOptions {
  const VideoModelV1CallOptions({
    required this.prompt,
    this.durationSeconds,
    this.aspectRatio,
    this.fps,
    this.seed,
    this.headers,
    this.providerOptions,
  });

  /// Text description of the video to generate.
  final String prompt;

  /// Requested duration in seconds.
  final double? durationSeconds;

  /// Aspect ratio, e.g. `'16:9'` or `'1:1'`.
  final String? aspectRatio;

  /// Frames per second.
  final int? fps;

  /// Random seed for reproducible results.
  final int? seed;

  /// Per-call HTTP headers.
  final Map<String, String>? headers;

  /// Provider-specific options.
  final ProviderOptions? providerOptions;
}
