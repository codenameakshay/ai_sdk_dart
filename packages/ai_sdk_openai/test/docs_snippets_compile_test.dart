// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:test/test.dart';

void main() {
  test('openai README and example snippets compile', () {
    Future<void> streaming() async {
      final result = await streamText(
        model: openai('gpt-4.1'),
        prompt: 'Tell me a joke.',
      );
      await for (final chunk in result.textStream) {
        stdout.write(chunk);
      }
    }

    Future<void> imageGeneration() async {
      final result = await generateImage(
        model: openai.image('dall-e-3'),
        prompt: 'A futuristic city at sunset.',
      );
      print(result.images.length);
    }

    Future<void> reasoningOptions() async {
      final result = await generateText(
        model: openai('o4-mini'),
        prompt: 'Solve the Tower of Hanoi for 4 disks.',
        providerOptions: {
          'openai': OpenAILanguageModelOptions(
            reasoningEffort: 'high',
            reasoningSummary: 'detailed',
          ).toMap(),
        },
      );
      print(result.text);
    }

    Future<void> providerRegistrySnippet() async {
      final registry = createProviderRegistry({
        'openai': RegistrableProvider(
          languageModelFactory: openai.call,
          embeddingModelFactory: openai.embedding,
        ),
      });
      final model = registry.languageModel('openai:gpt-4.1-mini');
      final result = await generateText(model: model, prompt: 'Hello!');
      print(result.text);
    }

    expect([
      streaming,
      imageGeneration,
      reasoningOptions,
      providerRegistrySnippet,
    ], hasLength(4));
  });
}
