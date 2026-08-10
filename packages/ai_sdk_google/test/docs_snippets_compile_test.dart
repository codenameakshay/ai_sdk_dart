// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:test/test.dart';

void main() {
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
}
