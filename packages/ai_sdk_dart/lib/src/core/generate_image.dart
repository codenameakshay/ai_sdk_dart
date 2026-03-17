import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [generateImage].
///
/// Contains [images] and optional [usage]. Use [image] for the first result.
class GenerateImageResult {
  const GenerateImageResult({required this.images, this.usage});

  final List<GeneratedImage> images;
  final ImageModelV3Usage? usage;

  GeneratedImage get image => images.first;
}

/// Generates images from a text prompt.
///
/// Mirrors `generateImage` from the JS AI SDK v6.
///
/// Example:
/// ```dart
/// final result = await generateImage(
///   model: imageModel,
///   prompt: 'A sunset over the ocean',
/// );
/// print(result.image);
/// ```
Future<GenerateImageResult> generateImage({
  required ImageModelV3 model,
  required String prompt,
  int? n,
  String? size,
  String? aspectRatio,
  int? seed,
}) async {
  final result = await model.doGenerate(
    ImageModelV3CallOptions(
      prompt: prompt,
      n: n,
      size: size,
      aspectRatio: aspectRatio,
      seed: seed,
    ),
  );

  return GenerateImageResult(images: result.images, usage: result.usage);
}

/// Decodes a base64-encoded image string to raw bytes.
Uint8List decodeBase64Image(String base64) {
  return Uint8List.fromList(const Base64Decoder().convert(base64));
}
