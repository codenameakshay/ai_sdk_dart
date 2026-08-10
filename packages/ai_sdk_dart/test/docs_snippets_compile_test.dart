import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
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
}
