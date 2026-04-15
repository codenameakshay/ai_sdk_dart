import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A controllable mock image model for testing.
///
/// ```dart
/// final model = MockImageModelV3(
///   images: [Uint8List.fromList([0, 1, 2])],
/// );
/// final result = await generateImage(model: model, prompt: 'A cat');
/// expect(result.image.uint8Array, isNotEmpty);
/// ```
class MockImageModelV3 implements ImageModelV3 {
  MockImageModelV3({
    this.images = const [],
    this.doGenerateError,
    this.provider = 'mock',
    this.modelId = 'mock-image-model',
  });

  /// The image bytes to return from every call.
  final List<Uint8List> images;

  /// If set, [doGenerate] throws this instead of returning images.
  final Object? doGenerateError;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v3';

  /// All call options passed to [doGenerate] in the order they were called.
  final List<ImageModelV3CallOptions> generateCalls = [];

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    generateCalls.add(options);
    if (doGenerateError != null) throw doGenerateError!;
    return ImageModelV3GenerateResult(
      images: images
          .map((bytes) => GeneratedImage(bytes: bytes, mediaType: 'image/png'))
          .toList(),
    );
  }
}

