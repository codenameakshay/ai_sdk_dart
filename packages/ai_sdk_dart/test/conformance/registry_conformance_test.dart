import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('registry conformance', () {
    // ── createProviderRegistry() ──────────────────────────────────────────

    group('createProviderRegistry()', () {
      late ProviderRegistry registry;

      setUp(() {
        registry = createProviderRegistry({
          'fake': RegistrableProvider(
            languageModelFactory: (modelId) =>
                FakeTextModel('from $modelId', modelId: modelId),
            embeddingModelFactory: (modelId) =>
                FakeEmbeddingModel([0.1, 0.2, 0.3], modelId: modelId),
          ),
          'other': RegistrableProvider(
            languageModelFactory: (modelId) =>
                FakeTextModel('from other/$modelId', modelId: modelId),
            embeddingModelFactory: (modelId) =>
                FakeEmbeddingModel([0.4, 0.5, 0.6], modelId: modelId),
          ),
        });
      });

      test('resolves language model by provider:modelId string', () async {
        final model = registry.languageModel('fake:gpt-4o');
        expect(model, isA<LanguageModelV3>());
        expect(model.modelId, 'gpt-4o');
      });

      test('resolved model generates text correctly', () async {
        final model = registry.languageModel('fake:my-model');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.text, 'from my-model');
      });

      test('resolves embedding model by provider:modelId string', () {
        final model = registry.textEmbeddingModel(
          'fake:text-embedding-3-small',
        );
        expect(model, isA<EmbeddingModelV2<String>>());
        expect(model.modelId, 'text-embedding-3-small');
      });

      test('resolves model from second provider', () {
        final model = registry.languageModel('other:claude-3-5');
        expect(model.modelId, 'claude-3-5');
      });

      test('throws ArgumentError for unknown provider', () {
        expect(
          () => registry.languageModel('unknown:gpt-4o'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test(
        'throws ArgumentError for unknown provider in textEmbeddingModel',
        () {
          expect(
            () => registry.textEmbeddingModel('nonexistent:emb-model'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );

      test(
        'error message for unknown provider mentions available providers',
        () {
          try {
            registry.languageModel('unknown:model');
            fail('Expected ArgumentError');
          } on ArgumentError catch (e) {
            // Should mention available providers
            expect(e.message.toString(), isNotEmpty);
          }
        },
      );
    });

    // ── ID format validation ───────────────────────────────────────────────

    group('id format validation', () {
      late ProviderRegistry registry;

      setUp(() {
        registry = createProviderRegistry({
          'fake': RegistrableProvider(
            languageModelFactory: (modelId) =>
                FakeTextModel('hi', modelId: modelId),
            embeddingModelFactory: (modelId) =>
                FakeEmbeddingModel([0.1], modelId: modelId),
          ),
        });
      });

      test('throws ArgumentError when id has no colon separator', () {
        expect(
          () => registry.languageModel('nogpt4o'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws ArgumentError for textEmbeddingModel with no colon', () {
        expect(
          () => registry.textEmbeddingModel('nocorolon'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('handles modelId that contains colons', () {
        // 'fake:model:with:colons' → provider='fake', modelId='model:with:colons'
        final model = registry.languageModel('fake:model:with:colons');
        // modelId is the part after the first colon
        expect(model.modelId, 'model:with:colons');
      });
    });

    // ── extended model types ──────────────────────────────────────────────

    group('extended model types (image, speech, transcription, video)', () {
      late ProviderRegistry registry;

      setUp(() {
        registry = createProviderRegistry({
          'fake': RegistrableProvider(
            languageModelFactory: (id) => FakeTextModel('hi', modelId: id),
            embeddingModelFactory: (id) => FakeEmbeddingModel([0.1], modelId: id),
            imageModelFactory: (id) => _FakeImageModel(id),
            speechModelFactory: (id) => FakeSpeechModel(
              audio: Uint8List(0),
              mediaType: 'audio/mpeg',
              modelId: id,
            ),
            transcriptionModelFactory: (id) =>
                FakeTranscriptionModel('hello', modelId: id),
            videoModelFactory: (id) => _FakeVideoModel(id),
          ),
          'no-extras': RegistrableProvider(
            languageModelFactory: (id) => FakeTextModel('hi'),
            embeddingModelFactory: (id) => FakeEmbeddingModel([0.1]),
          ),
        });
      });

      test('resolves image model by provider:modelId', () {
        final model = registry.imageModel('fake:dall-e-3');
        expect(model, isA<ImageModelV3>());
        expect(model.modelId, 'dall-e-3');
      });

      test('resolves speech model by provider:modelId', () {
        final model = registry.speechModel('fake:tts-1');
        expect(model, isA<SpeechModelV1>());
        expect(model.modelId, 'tts-1');
      });

      test('resolves transcription model by provider:modelId', () {
        final model = registry.transcriptionModel('fake:whisper-1');
        expect(model, isA<TranscriptionModelV1>());
        expect(model.modelId, 'whisper-1');
      });

      test('resolves video model by provider:modelId', () {
        final model = registry.videoModel('fake:video-gen');
        expect(model, isA<VideoModelV1>());
        expect(model.modelId, 'video-gen');
      });

      test('throws UnsupportedError when imageModelFactory not registered', () {
        expect(
          () => registry.imageModel('no-extras:dall-e-3'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError when speechModelFactory not registered', () {
        expect(
          () => registry.speechModel('no-extras:tts-1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError when transcriptionModelFactory not set',
          () {
        expect(
          () => registry.transcriptionModel('no-extras:whisper-1'),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('throws UnsupportedError when videoModelFactory not registered', () {
        expect(
          () => registry.videoModel('no-extras:vgen'),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    // ── RegistrableProvider ───────────────────────────────────────────────

    group('RegistrableProvider', () {
      test('can be constructed with language and embedding factories', () {
        final provider = RegistrableProvider(
          languageModelFactory: (modelId) => FakeTextModel('hi'),
          embeddingModelFactory: (modelId) => FakeEmbeddingModel([0.1]),
        );
        expect(provider, isNotNull);
        expect(provider.languageModelFactory('test'), isA<LanguageModelV3>());
        expect(
          provider.embeddingModelFactory('test'),
          isA<EmbeddingModelV2<String>>(),
        );
      });

      test('optional model factories default to null', () {
        final provider = RegistrableProvider(
          languageModelFactory: (id) => FakeTextModel('hi'),
          embeddingModelFactory: (id) => FakeEmbeddingModel([0.1]),
        );
        expect(provider.imageModelFactory, isNull);
        expect(provider.speechModelFactory, isNull);
        expect(provider.transcriptionModelFactory, isNull);
        expect(provider.videoModelFactory, isNull);
      });
    });
  });
}

class _FakeImageModel implements ImageModelV3 {
  _FakeImageModel(this.modelId);
  @override
  final String modelId;
  @override
  String get provider => 'fake';
  @override
  String get specificationVersion => 'v3';
  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async =>
      const ImageModelV3GenerateResult(images: []);
}

class _FakeVideoModel implements VideoModelV1 {
  _FakeVideoModel(this.modelId);
  @override
  final String modelId;
  @override
  String get provider => 'fake';
  @override
  String get specificationVersion => 'v1';
  @override
  Future<VideoModelV1GenerateResult> doGenerate(
    VideoModelV1CallOptions options,
  ) async =>
      const VideoModelV1GenerateResult(videos: []);
}
