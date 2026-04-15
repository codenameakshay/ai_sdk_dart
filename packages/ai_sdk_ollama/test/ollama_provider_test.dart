import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'llama3');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'nomic-embed-text');
      expect(model.specificationVersion, 'v2');
    });

    test('default ollama constant is an OllamaProvider', () {
      expect(ollama, isA<OllamaProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = OllamaProvider(
        baseUrl: 'http://192.168.1.100:11434/api',
      );
      final model = provider('phi3');
      expect(model.modelId, 'phi3');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });
}
