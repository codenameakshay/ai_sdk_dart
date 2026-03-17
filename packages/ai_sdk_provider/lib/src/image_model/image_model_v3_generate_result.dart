import 'dart:typed_data';

import '../shared/provider_metadata.dart';

/// A generated image file.
class GeneratedImage {
  const GeneratedImage({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String mediaType;
}

/// Usage stats for image generation.
class ImageModelV3Usage {
  const ImageModelV3Usage({this.imagesGenerated});
  final int? imagesGenerated;
}

/// Response metadata for each provider call.
class ImageModelV3ResponseMetadata {
  const ImageModelV3ResponseMetadata({
    this.timestamp,
    this.modelId,
    this.headers,
  });

  final DateTime? timestamp;
  final String? modelId;
  final Map<String, String>? headers;
}

/// Image generation result.
class ImageModelV3GenerateResult {
  const ImageModelV3GenerateResult({
    required this.images,
    this.usage,
    this.warnings = const [],
    this.providerMetadata,
    this.responses = const [],
  });

  final List<GeneratedImage> images;
  final ImageModelV3Usage? usage;
  final List<String> warnings;
  final ProviderMetadata? providerMetadata;
  final List<ImageModelV3ResponseMetadata> responses;
}
