import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('AzureOpenAIProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider('my-gpt4-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-gpt4-deployment');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider.embedding('my-ada-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-ada-deployment');
      expect(model.specificationVersion, 'v2');
    });

    test('default azureOpenAI constant is an AzureOpenAIProvider', () {
      expect(azureOpenAI, isA<AzureOpenAIProvider>());
    });

    test('uses default api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      expect(provider.apiVersion, '2024-02-15-preview');
    });

    test('accepts custom api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
        apiVersion: '2024-05-01-preview',
      );
      expect(provider.apiVersion, '2024-05-01-preview');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      final model = provider('gpt-4');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      final model = provider.embedding('text-embedding-ada-002');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });
}
