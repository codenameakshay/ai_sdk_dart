import 'dart:typed_data';

import '../shared/provider_metadata.dart';

/// A generated video file.
class GeneratedVideo {
  const GeneratedVideo({required this.bytes, required this.mediaType});

  /// Raw video bytes (e.g. MP4).
  final Uint8List bytes;

  /// IANA media type, e.g. `'video/mp4'`.
  final String mediaType;
}

/// Video generation result.
class VideoModelV1GenerateResult {
  const VideoModelV1GenerateResult({
    required this.videos,
    this.warnings = const [],
    this.providerMetadata,
  });

  final List<GeneratedVideo> videos;
  final List<String> warnings;
  final ProviderMetadata? providerMetadata;

  /// Convenience accessor for the first generated video.
  GeneratedVideo get video => videos.first;
}
