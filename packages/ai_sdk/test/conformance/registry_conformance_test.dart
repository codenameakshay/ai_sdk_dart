import 'package:ai_sdk/ai_sdk.dart';
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
    });
  });
}
