import 'video_model_v1_call_options.dart';
import 'video_model_v1_generate_result.dart';

/// Provider contract for video generation models.
///
/// Used by [experimental_generateVideo] from ai_sdk_dart.
///
/// Mirrors the JS AI SDK v6 experimental video model interface.
abstract interface class VideoModelV1 {
  String get specificationVersion;
  String get provider;
  String get modelId;

  Future<VideoModelV1GenerateResult> doGenerate(
    VideoModelV1CallOptions options,
  );
}
