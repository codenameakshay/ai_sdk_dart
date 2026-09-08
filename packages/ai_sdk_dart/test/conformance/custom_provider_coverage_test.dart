import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Covers the image/speech/transcription fallback paths of [customProvider]
/// and the direct nullable factory delegations not hit by the existing
/// language/embedding tests.
void main() {
  group('customProvider fallback delegations', () {
    test('fallbackImageModel resolves unknown image ids', () {
      final fallbackImage = _FakeImageModel();
      final provider = customProvider(
        imageModels: {'known': _FakeImageModel()},
        fallbackImageModel: (id) => fallbackImage,
      );
      expect(provider.imageModel('unknown'), same(fallbackImage));
    });

    test('fallbackSpeechModel resolves unknown speech ids', () {
      final fallbackSpeech = FakeSpeechModel(audio: Uint8List(0));
      final provider = customProvider(
        speechModels: {'known': FakeSpeechModel(audio: Uint8List(0))},
        fallbackSpeechModel: (id) => fallbackSpeech,
      );
      expect(provider.speechModel('unknown'), same(fallbackSpeech));
    });

    test('fallbackTranscriptionModel resolves unknown transcription ids', () {
      final fallbackT = FakeTranscriptionModel('hi');
      final provider = customProvider(
        transcriptionModels: {'known': FakeTranscriptionModel('x')},
        fallbackTranscriptionModel: (id) => fallbackT,
      );
      expect(provider.transcriptionModel('unknown'), same(fallbackT));
    });
  });

  group('customProvider missing-model errors without a fallback', () {
    test('speech model not found throws ArgumentError', () {
      final provider = customProvider();
      expect(() => provider.speechModel('tts'), throwsArgumentError);
    });

    test('transcription model not found throws ArgumentError', () {
      final provider = customProvider();
      expect(() => provider.transcriptionModel('asr'), throwsArgumentError);
    });
  });
}

class _FakeImageModel implements ImageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'fake-image';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async => const ImageModelV3GenerateResult(images: []);
}
