import 'image_model_v3_call_options.dart';
import 'image_model_v3_generate_result.dart';

/// Provider contract for image generation models.
///
/// Used by [generateImage] from ai_sdk_dart.
abstract interface class ImageModelV3 {
  String get specificationVersion;
  String get provider;
  String get modelId;

  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  );
}
