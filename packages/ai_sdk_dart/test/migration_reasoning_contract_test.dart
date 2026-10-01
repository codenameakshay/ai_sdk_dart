import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'conformance/helpers/fake_models.dart';

void main() {
  test(
    'migration guide reads all-step reasoning from the step history',
    () async {
      final guide = [
        File('docs/migration/v2-to-v3.md'),
        File('../../docs/migration/v2-to-v3.md'),
      ].firstWhere((file) => file.existsSync()).readAsStringSync();
      expect(
        guide.contains('result.steps.expand((step) => step.reasoning)'),
        isTrue,
        reason: 'The migration guide must read all-step reasoning from steps.',
      );
      final result = await generateText(
        model: FakeMultiStepModel(const [
          LanguageModelV4GenerateResult(
            content: [
              LanguageModelV4ReasoningPart(text: 'first thought'),
              LanguageModelV4ToolCallPart(
                toolCallId: 'lookup',
                toolName: 'lookup',
                input: {},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
          LanguageModelV4GenerateResult(
            content: [
              LanguageModelV4ReasoningPart(text: 'final thought'),
              LanguageModelV4TextPart(text: 'answer'),
            ],
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]),
        tools: {
          'lookup': dynamicTool<String>(execute: (_, _) async => 'found'),
        },
        maxSteps: 2,
      );
      final allReasoning = result.steps.expand((step) => step.reasoning);
      expect(allReasoning.map((part) => part.text), [
        'first thought',
        'final thought',
      ]);
      expect(result.reasoning.map((part) => part.text), ['final thought']);
    },
  );
}
