import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('CohereProvider', () {
    test('creates language model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider('command-r-plus');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'command-r-plus');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.embedding('embed-english-v3.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'embed-english-v3.0');
      expect(model.specificationVersion, 'v2');
    });

    test('creates rerank model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.rerank('rerank-english-v3.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'rerank-english-v3.0');
      expect(model.specificationVersion, 'v1');
    });

    test('default cohere instance is a CohereProvider', () {
      expect(cohere, isA<CohereProvider>());
    });

    test('custom baseUrl is accepted', () {
      final provider = CohereProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.cohere.example.com/v2',
      );
      // Just verify construction and model creation don't throw.
      final model = provider('command-r');
      expect(model.modelId, 'command-r');
    });
  });

  group('RerankModelV1 interface', () {
    test('implements RerankModelV1', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider.rerank('rerank-english-v3.0');
      expect(model, isA<RerankModelV1>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('implements EmbeddingModelV2<String>', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider.embedding('embed-english-v3.0');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });

  group('LanguageModelV3 interface', () {
    test('implements LanguageModelV3', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider('command-r-plus');
      expect(model, isA<LanguageModelV3>());
    });
  });
}
