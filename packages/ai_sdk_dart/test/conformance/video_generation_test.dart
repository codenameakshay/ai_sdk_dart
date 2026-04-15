import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('experimentalGenerateVideo', () {
    final sampleBytes = Uint8List.fromList([1, 2, 3, 4]);

    test('returns video from model', () async {
      final model = MockVideoModelV1(
        videos: [GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4')],
      );

      final result = await experimentalGenerateVideo(
        model: model,
        prompt: 'A sunset timelapse',
      );

      expect(result.videos.length, 1);
      expect(result.video.bytes, sampleBytes);
      expect(result.video.mediaType, 'video/mp4');
    });

    test('returns multiple videos', () async {
      final model = MockVideoModelV1(
        videos: [
          GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4'),
          GeneratedVideo(
            bytes: Uint8List.fromList([5, 6, 7, 8]),
            mediaType: 'video/webm',
          ),
        ],
      );

      final result = await experimentalGenerateVideo(
        model: model,
        prompt: 'Dual output test',
      );

      expect(result.videos.length, 2);
      expect(result.videos[1].mediaType, 'video/webm');
    });

    test('forwards prompt to model', () async {
      final model = MockVideoModelV1(
        videos: [GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4')],
      );

      await experimentalGenerateVideo(
        model: model,
        prompt: 'Flying over mountains',
      );

      expect(model.generateCalls.length, 1);
      expect(model.generateCalls.first.prompt, 'Flying over mountains');
    });

    test('forwards optional parameters to model', () async {
      final model = MockVideoModelV1(
        videos: [GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4')],
      );

      await experimentalGenerateVideo(
        model: model,
        prompt: 'Test',
        durationSeconds: 10.0,
        aspectRatio: '16:9',
        fps: 30,
        seed: 42,
        headers: {'x-custom': 'header'},
        providerOptions: {
          'test': {'key': 'value'},
        },
      );

      final call = model.generateCalls.first;
      expect(call.durationSeconds, 10.0);
      expect(call.aspectRatio, '16:9');
      expect(call.fps, 30);
      expect(call.seed, 42);
      expect(call.headers, {'x-custom': 'header'});
      expect(call.providerOptions, {
        'test': {'key': 'value'},
      });
    });

    test('returns warnings from model', () async {
      final model = MockVideoModelV1(
        videos: [GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4')],
        warnings: ['fps clamped to 24', 'duration limited to 5s'],
      );

      final result = await experimentalGenerateVideo(
        model: model,
        prompt: 'Test',
      );

      expect(result.warnings, [
        'fps clamped to 24',
        'duration limited to 5s',
      ]);
    });

    test('propagates model errors', () async {
      final model = MockVideoModelV1(
        videos: [],
        doGenerateError: Exception('generation failed'),
      );

      expect(
        () => experimentalGenerateVideo(model: model, prompt: 'Test'),
        throwsA(isA<Exception>()),
      );
    });

    test('video accessor throws StateError when no videos', () async {
      final model = MockVideoModelV1(videos: []);

      final result = await experimentalGenerateVideo(
        model: model,
        prompt: 'Test',
      );

      expect(() => result.video, throwsStateError);
    });

    test('optional parameters default to null', () async {
      final model = MockVideoModelV1(
        videos: [GeneratedVideo(bytes: sampleBytes, mediaType: 'video/mp4')],
      );

      await experimentalGenerateVideo(model: model, prompt: 'Minimal call');

      final call = model.generateCalls.first;
      expect(call.durationSeconds, isNull);
      expect(call.aspectRatio, isNull);
      expect(call.fps, isNull);
      expect(call.seed, isNull);
      expect(call.headers, isNull);
      expect(call.providerOptions, isNull);
    });
  });

  group('MockVideoModelV1', () {
    test('records generate calls', () async {
      final model = MockVideoModelV1(
        videos: [
          GeneratedVideo(bytes: Uint8List.fromList([1]), mediaType: 'video/mp4'),
        ],
      );

      await model.doGenerate(
        const VideoModelV1CallOptions(prompt: 'first call'),
      );
      await model.doGenerate(
        const VideoModelV1CallOptions(prompt: 'second call'),
      );

      expect(model.generateCalls.length, 2);
      expect(model.generateCalls[0].prompt, 'first call');
      expect(model.generateCalls[1].prompt, 'second call');
    });

    test('has correct provider metadata', () {
      final model = MockVideoModelV1(videos: []);
      expect(model.specificationVersion, 'v1');
      expect(model.provider, 'mock');
      expect(model.modelId, 'mock-video-model');
    });

    test('throws configured error', () async {
      final model = MockVideoModelV1(
        videos: [],
        doGenerateError: StateError('mock error'),
      );

      expect(
        () => model.doGenerate(
          const VideoModelV1CallOptions(prompt: 'Test'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
