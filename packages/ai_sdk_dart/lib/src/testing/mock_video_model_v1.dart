import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A mock implementation of [VideoModelV1] for use in tests.
///
/// Records all calls made to [doGenerate] in [generateCalls].
/// Throws [doGenerateError] if set.
///
/// Example:
/// ```dart
/// final model = MockVideoModelV1(
///   videos: [GeneratedVideo(base64: 'abc123', mediaType: 'video/mp4')],
/// );
/// final result = await experimentalGenerateVideo(model: model, prompt: 'A sunset');
/// expect(result.video.base64, 'abc123');
/// ```
class MockVideoModelV1 implements VideoModelV1 {
  MockVideoModelV1({
    this.videos = const [],
    this.warnings = const [],
    this.doGenerateError,
  });

  final List<GeneratedVideo> videos;
  final List<String> warnings;
  final Object? doGenerateError;

  final List<VideoModelV1CallOptions> generateCalls = [];

  @override
  String get specificationVersion => 'v1';

  @override
  String get provider => 'mock';

  @override
  String get modelId => 'mock-video-model';

  @override
  Future<VideoModelV1GenerateResult> doGenerate(
    VideoModelV1CallOptions options,
  ) async {
    generateCalls.add(options);
    if (doGenerateError != null) {
      throw doGenerateError!;
    }
    return VideoModelV1GenerateResult(videos: videos, warnings: warnings);
  }
}
