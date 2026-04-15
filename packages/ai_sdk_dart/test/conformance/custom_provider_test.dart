import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('customProvider conformance', () {
    // ── basic construction ────────────────────────────────────────────────

    group('basic construction', () {
      test('empty provider with no models throws on resolution', () {
        final provider = customProvider();
        expect(() => provider.languageModel('gpt-4o'), throwsArgumentError);
        expect(
          () => provider.textEmbeddingModel('embed'),
          throwsArgumentError,
        );
      });

      test('resolves registered language model by id', () {
        final model = FakeTextModel('hello');
        final provider = customProvider(
          languageModels: {'my-model': model},
        );
        expect(provider.languageModel('my-model'), same(model));
      });

      test('resolves registered embedding model by id', () {
        final model = FakeEmbeddingModel([0.1, 0.2]);
        final provider = customProvider(
          embeddingModels: {'embed': model},
        );
        expect(provider.textEmbeddingModel('embed'), same(model));
      });

      test('throws ArgumentError for unregistered language model', () {
        final provider = customProvider(
          languageModels: {'model-a': FakeTextModel('a')},
        );
        expect(
          () => provider.languageModel('model-b'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for unregistered embedding model', () {
        final provider = customProvider(
          embeddingModels: {'embed-a': FakeEmbeddingModel([0.1])},
        );
        expect(
          () => provider.textEmbeddingModel('embed-b'),
          throwsArgumentError,
        );
      });
    });

    // ── multiple model types ──────────────────────────────────────────────

    group('multiple model types', () {
      test('resolves image model', () {
        final imageModel = _FakeImageModel();
        final provider = customProvider(imageModels: {'dalle': imageModel});
        expect(provider.imageModel('dalle'), same(imageModel));
      });

      test('resolves speech model', () {
        final speechModel = FakeSpeechModel(
          audio: _emptyAudio,
          mediaType: 'audio/mp3',
        );
        final provider = customProvider(speechModels: {'tts': speechModel});
        expect(provider.speechModel('tts'), same(speechModel));
      });

      test('resolves transcription model', () {
        final transcriptionModel = FakeTranscriptionModel('hello');
        final provider = customProvider(
          transcriptionModels: {'whisper': transcriptionModel},
        );
        expect(provider.transcriptionModel('whisper'), same(transcriptionModel));
      });

      test('throws for unregistered image model', () {
        final provider = customProvider();
        expect(() => provider.imageModel('dalle'), throwsArgumentError);
      });
    });

    // ── fallback providers ────────────────────────────────────────────────

    group('fallback providers', () {
      test('fallbackLanguageModel is called for unknown ids', () {
        final fallbackModel = FakeTextModel('fallback');
        final provider = customProvider(
          languageModels: {'local': FakeTextModel('local')},
          fallbackLanguageModel: (id) => fallbackModel,
        );
        final resolved = provider.languageModel('unknown-model');
        expect(resolved, same(fallbackModel));
      });

      test('explicit map takes priority over fallback', () {
        final explicitModel = FakeTextModel('explicit');
        final fallbackModel = FakeTextModel('fallback');
        final provider = customProvider(
          languageModels: {'fast': explicitModel},
          fallbackLanguageModel: (id) => fallbackModel,
        );
        final resolved = provider.languageModel('fast');
        expect(resolved, same(explicitModel));
      });

      test('fallbackEmbeddingModel is called for unknown ids', () {
        final fallbackEmbed = FakeEmbeddingModel([0.9]);
        final provider = customProvider(
          fallbackEmbeddingModel: (id) => fallbackEmbed,
        );
        final resolved = provider.textEmbeddingModel('any-embed');
        expect(resolved, same(fallbackEmbed));
      });

      test('fallback receives the model id', () {
        String? receivedId;
        final provider = customProvider(
          fallbackLanguageModel: (id) {
            receivedId = id;
            return FakeTextModel('fallback');
          },
        );
        provider.languageModel('gpt-4o-mini');
        expect(receivedId, 'gpt-4o-mini');
      });

      test('throws when fallback is null and model not registered', () {
        final provider = customProvider(
          languageModels: {'a': FakeTextModel('a')},
        );
        expect(() => provider.languageModel('b'), throwsArgumentError);
      });
    });

    // ── integration with generateText ─────────────────────────────────────

    group('integration with generateText()', () {
      test('model resolved from customProvider works with generateText', () async {
        final model = FakeTextModel('Hello from custom provider!');
        final provider = customProvider(
          languageModels: {'chat': model},
        );
        final result = await generateText(
          model: provider.languageModel('chat'),
          prompt: 'hi',
        );
        expect(result.text, 'Hello from custom provider!');
      });
    });
  });
}

final _emptyAudio = Uint8List(0);

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
  ) async {
    return const ImageModelV3GenerateResult(images: []);
  }
}
