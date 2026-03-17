import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';
import 'helpers/matchers.dart';

void main() {
  group('generateText conformance', () {
    // ── Basic text generation ─────────────────────────────────────────────

    group('basic text', () {
      test('returns text from model response', () async {
        final model = FakeTextModel('Hello, world!');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.text, 'Hello, world!');
      });

      test('exposes finishReason and rawFinishReason', () async {
        final model = FakeTextModel(
          'done',
          finishReason: LanguageModelV3FinishReason.stop,
          rawFinishReason: 'stop',
        );
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.finishReason, LanguageModelV3FinishReason.stop);
        expect(result.rawFinishReason, 'stop');
      });

      test('exposes usage from model response', () async {
        final model = FakeTextModel(
          'done',
          usage: const LanguageModelV3Usage(
            inputTokens: 5,
            outputTokens: 3,
            totalTokens: 8,
          ),
        );
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.usage?.inputTokens, 5);
        expect(result.usage?.outputTokens, 3);
      });

      test('exposes warnings from model response', () async {
        final model = FakeTextModel('done', warnings: ['deprecation: old-api']);
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.warnings, contains('deprecation: old-api'));
      });

      test('steps contains single step for single-step generation', () async {
        final model = FakeTextModel('Hello!');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.steps.length, 1);
        expect(result.steps[0].stepNumber, 0);
        expect(result.steps[0].text, 'Hello!');
        expect(result.steps[0].finishReason, LanguageModelV3FinishReason.stop);
      });
    });

    // ── Reasoning ─────────────────────────────────────────────────────────

    group('reasoning', () {
      test('reasoning field contains ReasoningPart array', () async {
        final model = FakeTextModel('answer', reasoning: 'Let me think...');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.reasoning.length, 1);
        expect(result.reasoning[0].text, 'Let me think...');
      });

      test('reasoningText concatenates all reasoning parts', () async {
        final model = FakeTextModel('answer', reasoning: 'Let me think...');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.reasoningText, 'Let me think...');
      });

      test('redacted reasoning maps to [REDACTED] in reasoningText', () async {
        final model = FakeTextModel('answer', redactedReasoning: true);
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.reasoningText, '[REDACTED]');
      });
    });

    // ── Sources ───────────────────────────────────────────────────────────

    group('sources', () {
      test('sources from provider response are exposed on result', () async {
        final model = FakeTextModel(
          'answer',
          sources: [
            const LanguageModelV3SourcePart(
              id: 's1',
              url: 'https://example.com',
              title: 'Example',
            ),
          ],
        );
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.sources.length, 1);
        expect(result.sources[0].url, 'https://example.com');
        expect(result.sources[0].title, 'Example');
      });
    });

    // ── Provider metadata ─────────────────────────────────────────────────

    group('providerMetadata', () {
      test('providerMetadata from model is passed through to result', () async {
        final model = FakeTextModel(
          'done',
          providerMetadata: const {
            'anthropic': {'cacheReadInputTokens': 5},
          },
        );
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.providerMetadata, isNotNull);
        expect(
          (result.providerMetadata!['anthropic']
              as Map?)?['cacheReadInputTokens'],
          5,
        );
      });
    });

    // ── Callbacks ─────────────────────────────────────────────────────────

    group('callbacks', () {
      test(
        'onFinish is called with text, steps, usage, finishReason',
        () async {
          GenerateTextFinishEvent<dynamic>? finishEvent;
          final model = FakeTextModel(
            'hello',
            usage: const LanguageModelV3Usage(inputTokens: 2, outputTokens: 1),
          );
          await generateText(
            model: model,
            prompt: 'hi',
            onFinish: (event) => finishEvent = event,
          );
          expect(finishEvent, isNotNull);
          expect(finishEvent!.text, 'hello');
          expect(finishEvent!.steps.length, 1);
          expect(finishEvent!.usage?.inputTokens, 2);
          expect(finishEvent!.finishReason, LanguageModelV3FinishReason.stop);
        },
      );

      test('onStepFinish is called once per step', () async {
        final stepEvents = <GenerateTextStepFinishEvent>[];
        final model = FakeTextModel('step done');
        await generateText(
          model: model,
          prompt: 'hi',
          onStepFinish: stepEvents.add,
        );
        expect(stepEvents.length, 1);
        expect(stepEvents[0].stepNumber, 0);
        expect(stepEvents[0].text, 'step done');
      });

      test(
        'experimentalOnStart is called once with model and messages',
        () async {
          GenerateTextExperimentalStartEvent? startEvent;
          final model = FakeTextModel('hi');
          await generateText(
            model: model,
            prompt: 'hello',
            experimentalOnStart: (e) => startEvent = e,
          );
          expect(startEvent, isNotNull);
          expect(startEvent!.model, same(model));
          expect(startEvent!.messages, isNotEmpty);
        },
      );

      test('experimentalOnStepStart is called once per step', () async {
        final stepStartEvents = <GenerateTextExperimentalStepStartEvent>[];
        final model = FakeTextModel('done');
        await generateText(
          model: model,
          prompt: 'hi',
          experimentalOnStepStart: stepStartEvents.add,
        );
        expect(stepStartEvents.length, 1);
        expect(stepStartEvents[0].stepNumber, 0);
      });
    });

    // ── Multi-step ────────────────────────────────────────────────────────

    group('multi-step', () {
      test('single tool call + text produces 2 steps', () async {
        final model = FakeMultiStepModel([
          // Step 1: tool call
          LanguageModelV3GenerateResult(
            content: [
              const LanguageModelV3ToolCallPart(
                toolCallId: 'c1',
                toolName: 'calc',
                input: {'op': 'add', 'a': 1, 'b': 2},
              ),
            ],
            finishReason: LanguageModelV3FinishReason.toolCalls,
          ),
          // Step 2: text answer
          const LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'The answer is 3')],
            finishReason: LanguageModelV3FinishReason.stop,
          ),
        ]);

        final result = await generateText(
          model: model,
          prompt: 'What is 1+2?',
          maxSteps: 3,
          tools: {
            'calc': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (input, _) async => '3',
            ),
          },
        );

        expect(result.steps.length, 2);
        expect(result.text, 'The answer is 3');
      });

      test('totalUsage aggregates usage across all steps', () async {
        final usage = const LanguageModelV3Usage(
          inputTokens: 10,
          outputTokens: 5,
          totalTokens: 15,
        );
        final model = FakeMultiStepModel([
          LanguageModelV3GenerateResult(
            content: [
              const LanguageModelV3ToolCallPart(
                toolCallId: 'c1',
                toolName: 'noop',
                input: {},
              ),
            ],
            finishReason: LanguageModelV3FinishReason.toolCalls,
            usage: usage,
          ),
          LanguageModelV3GenerateResult(
            content: [const LanguageModelV3TextPart(text: 'done')],
            finishReason: LanguageModelV3FinishReason.stop,
            usage: usage,
          ),
        ]);

        final result = await generateText(
          model: model,
          prompt: 'hi',
          maxSteps: 3,
          tools: {
            'noop': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, __) async => 'ok',
            ),
          },
        );

        expect(result.totalUsage?.inputTokens, 20);
        expect(result.totalUsage?.outputTokens, 10);
      });
    });

    // ── prepareStep ───────────────────────────────────────────────────────

    group('prepareStep', () {
      test('prepareStep can override model for a step', () async {
        final overrideModel = FakeTextModel('override-text');
        final mainModel = FakeTextModel('main-text');

        final result = await generateText(
          model: mainModel,
          prompt: 'hi',
          prepareStep: (ctx) async {
            if (ctx.stepNumber == 0) {
              return GenerateTextPrepareStepResult(model: overrideModel);
            }
            return null;
          },
        );

        expect(result.text, 'override-text');
      });

      test(
        'prepareStep can set activeTools to restrict which tools are exposed',
        () async {
          final capturingModel = FakeCapturingModel();
          await generateText(
            model: capturingModel,
            prompt: 'hi',
            tools: {
              'toolA': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, __) async => 'a',
              ),
              'toolB': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, __) async => 'b',
              ),
            },
            prepareStep: (_) async =>
                GenerateTextPrepareStepResult(activeTools: ['toolA']),
          );

          final opts = capturingModel.capturedOptions.first;
          expect(opts.tools.length, 1);
          expect(opts.tools[0].name, 'toolA');
        },
      );
    });

    // ── Stop conditions ───────────────────────────────────────────────────

    group('stopConditions', () {
      test(
        'stopAfterMaxCalls(1) stops after one step even with tools',
        () async {
          final model = FakeMultiStepModel([
            LanguageModelV3GenerateResult(
              content: [
                const LanguageModelV3ToolCallPart(
                  toolCallId: 'c1',
                  toolName: 'noop',
                  input: {},
                ),
              ],
              finishReason: LanguageModelV3FinishReason.toolCalls,
            ),
            const LanguageModelV3GenerateResult(
              content: [LanguageModelV3TextPart(text: 'done')],
              finishReason: LanguageModelV3FinishReason.stop,
            ),
          ]);

          final result = await generateText(
            model: model,
            prompt: 'hi',
            maxSteps: 5,
            stopConditions: [stepCountIs(1)],
            tools: {
              'noop': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, __) async => 'ok',
              ),
            },
          );

          // stopAfterMaxCalls(1) stops after the first step's tool results loop
          expect(result.steps.length, 1);
        },
      );
    });

    // ── Request/response ──────────────────────────────────────────────────

    group('request and responseInfo', () {
      test('request.messages contains the initial prompt messages', () async {
        final model = FakeTextModel('hello');
        final result = await generateText(model: model, prompt: 'What is 2+2?');
        expect(result.request.messages, isNotEmpty);
        expect(result.requestMessages, isNotEmpty);
      });

      test('responseMessages contains assistant messages only', () async {
        final model = FakeTextModel('The answer is 4');
        final result = await generateText(model: model, prompt: 'What is 2+2?');
        expect(
          result.responseMessages.every(
            (m) =>
                m.role == LanguageModelV3Role.assistant ||
                m.role == LanguageModelV3Role.tool,
          ),
          isTrue,
        );
      });
    });

    // ── Tool choice validation ────────────────────────────────────────────

    group('toolChoice validation', () {
      test('ToolChoiceNone with no tool calls succeeds', () async {
        final model = FakeTextModel('plain text');
        final result = await generateText(
          model: model,
          prompt: 'hi',
          toolChoice: const ToolChoiceNone(),
          tools: {
            'unused': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );
        expect(result.text, 'plain text');
      });

      test('ToolChoiceNone throws when model returns tool calls', () async {
        final model = FakeToolModel(
          toolName: 'myTool',
          toolInput: const {'x': 1},
        );
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            toolChoice: const ToolChoiceNone(),
            tools: {
              'myTool': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
              ),
            },
          ),
          throwsAiError<AiApiCallError>(),
        );
      });
    });
  });
}
