// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

void main() {
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
          'anthropic': AnthropicThinkingOptions(
            budgetTokens: 5000,
          ).toMap(),
        },
      );
      print(result.text);
    }

    expect([streaming, reasoningMiddleware, thinkingOptions], hasLength(3));
  });
}
