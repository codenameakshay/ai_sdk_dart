import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Covers the image/speech/transcription fallback paths of [customProvider]
/// and the corresponding `_FunctionFallback` delegations not hit by the
/// existing language/embedding tests.
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

    test('registered speech/transcription models resolve directly', () {
      final speech = FakeSpeechModel(audio: Uint8List(0));
      final transcription = FakeTranscriptionModel('t');
      final provider = customProvider(
        speechModels: {'tts': speech},
        transcriptionModels: {'asr': transcription},
      );
      expect(provider.speechModel('tts'), same(speech));
      expect(provider.transcriptionModel('asr'), same(transcription));
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

    test('image model not found (with unrelated fallback) throws', () {
      // A speech fallback does not satisfy image lookups.
      final provider = customProvider(
        fallbackSpeechModel: (id) => FakeSpeechModel(audio: Uint8List(0)),
      );
      expect(() => provider.imageModel('dalle'), throwsArgumentError);
    });

    test('language model not found (with unrelated fallback) throws', () {
      final provider = customProvider(
        fallbackImageModel: (id) => _FakeImageModel(),
      );
      expect(() => provider.languageModel('gpt'), throwsArgumentError);
    });

    test('embedding model not found (with unrelated fallback) throws', () {
      final provider = customProvider(
        fallbackImageModel: (id) => _FakeImageModel(),
      );
      expect(() => provider.textEmbeddingModel('embed'), throwsArgumentError);
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
  ) async =>
      const ImageModelV3GenerateResult(images: []);
}
