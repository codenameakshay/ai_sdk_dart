import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('MistralProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider('mistral-large-latest');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-large-latest');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider.embedding('mistral-embed');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-embed');
      expect(model.specificationVersion, 'v2');
    });

    test('default mistral constant is a MistralProvider', () {
      expect(mistral, isA<MistralProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = MistralProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.mistral.example.com/v1',
      );
      final model = provider('mistral-small');
      expect(model.modelId, 'mistral-small');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = MistralProvider(apiKey: 'key');
      final model = provider('mistral-medium');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = MistralProvider(apiKey: 'key');
      final model = provider.embedding('mistral-embed');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });
}
