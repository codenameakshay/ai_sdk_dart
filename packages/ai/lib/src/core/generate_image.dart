import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Image generation result in AI core format.
class GenerateImageResult {
  const GenerateImageResult({required this.images, this.usage});

  final List<GeneratedImage> images;
  final ImageModelV3Usage? usage;

  GeneratedImage get image => images.first;
}

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

Uint8List decodeBase64Image(String base64) {
  return Uint8List.fromList(const Base64Decoder().convert(base64));
}
