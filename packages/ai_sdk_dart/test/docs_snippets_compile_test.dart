import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:test/test.dart';

void main() {
  test('root and package README snippets compile', () {
    Future<void> quickStart() async {
      final apiKey = Platform.environment['OPENAI_API_KEY'] ?? 'test-key';
      final provider = OpenAIProvider(apiKey: apiKey);
      final result = await generateText(
        model: provider('gpt-4.1-mini'),
        prompt: 'Say hello from AI SDK Dart!',
      );
      print(result.text);
    }

    Future<void> streaming() async {
      final result = await streamText(
        model: openai('gpt-4.1-mini'),
        prompt: 'Count from 1 to 5.',
      );
      await for (final chunk in result.textStream) {
        stdout.write(chunk);
      }
    }

    Future<void> structuredOutput() async {
      final result = await generateText<Map<String, dynamic>>(
        model: openai('gpt-4.1-mini'),
        prompt: 'Return the capital and currency of Japan as JSON.',
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'capital': {'type': 'string'},
                'currency': {'type': 'string'},
              },
            },
            fromJson: (json) => json,
          ),
        ),
      );
      print(result.output);
    }

    Future<void> tools() async {
      final result = await generateText(
        model: openai('gpt-4.1-mini'),
        prompt: 'What is the weather in Paris?',
        maxSteps: 5,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
              },
              fromJson: (json) => json,
            ),
            execute: (input, _) async => 'Sunny, 18C in ${input['city']}',
          ),
        },
      );
      print(result.text);
    }

    expect([quickStart, streaming, structuredOutput, tools], hasLength(4));
  });

  test('anthropic README and example snippets compile', () {
    Future<void> streaming() async {
      final result = await streamText(
        model: anthropic('claude-sonnet-4-5'),
        prompt: 'Write a haiku about Dart.',
      );
      await for (final chunk in result.textStream) {
        stdout.write(chunk);
      }
    }

    Future<void> reasoningMiddleware() async {
      final model = wrapLanguageModel(
        model: anthropic('claude-sonnet-4-5'),
        middleware: extractReasoningMiddleware(tagName: 'think'),
      );
      final result = await generateText(
        model: model,
        prompt: 'Solve: if 3x + 5 = 20, what is x?',
      );
      print(result.reasoningText);
    }

    Future<void> thinkingOptions() async {
      final result = await generateText(
        model: anthropic('claude-opus-4-5'),
        prompt: 'Prove that sqrt(2) is irrational.',
        providerOptions: {
          'anthropic': AnthropicThinkingOptions(budgetTokens: 5000).toMap(),
        },
      );
      print(result.text);
    }

    Future<void> defaultSettingsSnippet() async {
      final model = wrapLanguageModel(
        model: anthropic('claude-sonnet-4-5'),
        middleware: defaultSettingsMiddleware(
          temperature: 0.3,
          maxOutputTokens: 512,
        ),
      );
      final result = await generateText(
        model: model,
        prompt: 'Summarise the Dart language in three bullet points.',
      );
      print(result.text);
    }

    expect([
      streaming,
      reasoningMiddleware,
      thinkingOptions,
      defaultSettingsSnippet,
    ], hasLength(4));
  });

  test('google README and example snippets compile', () {
    Future<void> streaming() async {
      final result = await streamText(
        model: google('gemini-2.0-flash'),
        prompt: 'Tell me about the history of the internet.',
      );
      await for (final chunk in result.textStream) {
        stdout.write(chunk);
      }
    }

    Future<void> structuredOutput() async {
      final result = await generateText<Map<String, dynamic>>(
        model: google('gemini-2.0-flash'),
        prompt: 'Return the capital and timezone of Japan as JSON.',
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'capital': {'type': 'string'},
                'timezone': {'type': 'string'},
              },
            },
            fromJson: (json) => json,
          ),
        ),
      );
      print(result.output);
    }

    Future<void> customProviderSnippet() async {
      final provider = GoogleGenerativeAIProvider(
        apiKey: Platform.environment['GOOGLE_API_KEY'] ?? 'test-key',
      );
      final result = await generateText(
        model: provider('gemini-2.0-flash'),
        prompt: 'Hello!',
      );
      print(result.text);
    }

    expect([streaming, structuredOutput, customProviderSnippet], hasLength(3));
  });

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
