import 'package:ai_sdk_groq/ai_sdk_groq.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('GroqProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = GroqProvider(apiKey: 'test-key');
      final model = provider('llama3-8b-8192');
      expect(model.provider, 'groq');
      expect(model.modelId, 'llama3-8b-8192');
      expect(model.specificationVersion, 'v3');
    });

    test('default groq constant is a GroqProvider', () {
      expect(groq, isA<GroqProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = GroqProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.groq.example.com/openai/v1',
      );
      final model = provider('mixtral-8x7b-32768');
      expect(model.modelId, 'mixtral-8x7b-32768');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = GroqProvider(apiKey: 'key');
      final model = provider('llama3-70b-8192');
      expect(model, isA<LanguageModelV3>());
    });
  });
}
