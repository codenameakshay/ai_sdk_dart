import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('core APIs', () {
    test('generateText supports Output.object', () async {
      final model = _JsonGenerateModel();
      final result = await generateText<Map<String, dynamic>>(
        model: model,
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
                'tempC': {'type': 'number'},
              },
            },
            fromJson: (json) => json,
          ),
        ),
        prompt: 'Give weather JSON',
      );

      expect(result.output['city'], 'Paris');
      expect(result.output['tempC'], 21);
    });

    test('generateText supports Output.array / choice / json', () async {
      final arrayModel = _StaticTextGenerateModel(
        '[{"name":"A"},{"name":"B"}]',
      );
      final arrayResult = await generateText<List<dynamic>>(
        model: arrayModel,
        output: Output.array(
          element: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
            },
            fromJson: (json) => json,
          ),
        ),
      );
      expect(arrayResult.output.length, 2);

      final choiceModel = _StaticTextGenerateModel('sunny');
      final choiceResult = await generateText<String>(
        model: choiceModel,
        output: Output.choice(options: const ['sunny', 'rainy']),
      );
      expect(choiceResult.output, 'sunny');

      final jsonModel = _StaticTextGenerateModel('{"ok":true,"count":2}');
      final jsonResult = await generateText<Object?>(
        model: jsonModel,
        output: Output.json(),
      );
      expect((jsonResult.output as Map<String, dynamic>)['ok'], isTrue);
    });

    test(
      'generateText exposes request/response and onFinish payload',
      () async {
        GenerateTextFinishEvent<String>? finish;
        final result = await generateText<String>(
          model: _ResponseEnvelopeGenerateModel(),
          prompt: 'hi',
          bodyInclusion: const BodyInclusionPolicy.all(),
          onFinish: (event) => finish = event,
        );

        expect(result.request.messages, isNotEmpty);
        expect(result.responseInfo.messages, isNotEmpty);
        expect(result.request.body, isA<Map<String, dynamic>>());
        expect(result.responseInfo.body, isA<Map<String, dynamic>>());
        expect(finish, isNotNull);
        expect(finish!.text, 'hello');
        expect(finish!.response.messages, isNotEmpty);
      },
    );

    test('streamText emits full event taxonomy in order', () async {
      final model = _StreamTaxonomyModel();
      final result = await streamText<String>(
        model: model,
        tools: {
          'weather': tool<Map<String, dynamic>, Object?>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async {
              return Stream<Object?>.fromIterable(const [
                {'status': 'loading'},
                {'status': 'done', 'tempC': 23},
              ]);
            },
          ),
        },
        maxSteps: 3,
      );

      final events = await result.fullStream.toList();
      final typedEvents = events.where((event) => event is! StreamTextRawEvent);
      expect(typedEvents.map((event) => event.runtimeType).toList(), [
        StreamTextStartEvent,
        StreamTextStartStepEvent,
        StreamTextTextStartEvent,
        StreamTextTextDeltaEvent,
        StreamTextTextEndEvent,
        StreamTextReasoningStartEvent,
        StreamTextReasoningDeltaEvent,
        StreamTextReasoningEndEvent,
        StreamTextSourceEvent,
        StreamTextFileEvent,
        StreamTextToolInputStartEvent,
        StreamTextToolInputDeltaEvent,
        StreamTextToolInputEndEvent,
        StreamTextUsageEvent,
        StreamTextToolResultEvent,
        StreamTextToolResultEvent,
        StreamTextFinishStepEvent,
        StreamTextStartStepEvent,
        StreamTextTextStartEvent,
        StreamTextTextDeltaEvent,
        StreamTextTextEndEvent,
        StreamTextUsageEvent,
        StreamTextFinishStepEvent,
        StreamTextFinishEvent<String>,
      ]);

      final startStep = typedEvents.elementAt(1) as StreamTextStartStepEvent;
      expect(startStep.stepNumber, 0);

      final inputEnd = typedEvents
          .whereType<StreamTextToolInputEndEvent>()
          .single;
      expect(inputEnd.toolName, 'weather');
      expect(inputEnd.toolCallId, 'call_weather_1');
      expect((inputEnd.input as Map<String, dynamic>)['city'], 'Paris');

      final resultEvents = typedEvents.whereType<StreamTextToolResultEvent>();
      expect(resultEvents.first.preliminary, isTrue);
      expect(resultEvents.last.preliminary, isFalse);
    });

    test(
      'streamText applies experimental transform before callbacks',
      () async {
        final model = _TransformStreamModel();
        final onChunkText = <String>[];
        final result = await streamText<String>(
          model: model,
          experimentalTransform: smoothStream(chunkSize: 2),
          onChunk: (chunk) {
            if (chunk is StreamTextTextChunk) {
              onChunkText.add(chunk.text);
            }
          },
        );

        final events = await result.fullStream
            .where((event) => event is! StreamTextRawEvent)
            .toList();
        final deltas = events
            .whereType<StreamTextTextDeltaEvent>()
            .map((event) => event.delta)
            .toList();

        expect(deltas, ['He', 'll', 'o']);
        expect(onChunkText, ['He', 'll', 'o']);
        expect(await result.text, 'Hello');
        expect(await result.request, isA<GenerateTextRequest>());
        expect(await result.response, isA<GenerateTextResponse>());
        expect(await result.content, isNotEmpty);
      },
    );

    test('streamText exposes provider raw request/response envelope', () async {
      final result = await streamText<String>(
        model: _ResponseEnvelopeStreamModel(),
        bodyInclusion: const BodyInclusionPolicy.all(),
      );

      final request = await result.request;
      final response = await result.response;
      expect(request.body, isA<Map<String, dynamic>>());
      expect(response.body, isA<Map<String, dynamic>>());
    });

    test('streamText onError receives stream errors', () async {
      final model = _ErrorStreamModel();
      Object? observed;
      final result = await streamText<String>(
        model: model,
        onError: (error) => observed = error,
      );

      await expectLater(result.stream.toList(), throwsA('boom'));
      expect(observed, 'boom');
    });

    test('streamText onChunk includes source/file/tool-input chunks', () async {
      final chunkTypes = <Type>[];
      final result = await streamText<String>(
        model: _StreamTaxonomyModel(),
        tools: {
          'weather': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
        },
        maxSteps: 2,
        onChunk: (chunk) => chunkTypes.add(chunk.runtimeType),
      );

      await result.output;
      expect(chunkTypes, contains(StreamTextSourceChunk));
      expect(chunkTypes, contains(StreamTextFileChunk));
      expect(chunkTypes, contains(StreamTextToolInputStartChunk));
      expect(chunkTypes, contains(StreamTextToolInputDeltaChunk));
    });

    test(
      'streamText onFinish contains warnings and metadata richness',
      () async {
        StreamTextFinishEvent<String>? finished;
        final result = await streamText<String>(
          model: _OnFinishRichStreamModel(),
          bodyInclusion: const BodyInclusionPolicy.all(),
          onFinish: (event) => finished = event,
        );

        await result.output;
        expect(finished, isNotNull);
        expect(finished!.text, 'done');
        expect(
          (finished!.usage?.inputTokens.total ?? 0) +
              (finished!.usage?.outputTokens.total ?? 0),
          3,
        );
        expect(
          (finished!.totalUsage?.inputTokens.total ?? 0) +
              (finished!.totalUsage?.outputTokens.total ?? 0),
          3,
        );
        expect(
          finished!.warnings,
          contains(
            isA<LanguageModelV4OtherWarning>().having(
              (warning) => warning.message,
              'message',
              'provider-warning',
            ),
          ),
        );
        expect(finished!.response.metadata?.id, 'resp_stream_1');
        expect(finished!.response.body, isA<Map<String, dynamic>>());
        expect(finished!.response.messages, isNotEmpty);
        expect(finished!.steps, isNotEmpty);
      },
    );

    test('generateText onStepFinish works for single step', () async {
      final model = _StaticTextGenerateModel('single step');
      final calls = <GenerateTextStepFinishEvent>[];

      final result = await generateText<String>(
        model: model,
        onStepFinish: calls.add,
      );

      expect(result.text, 'single step');
      expect(calls, hasLength(1));
      expect(calls.single.stepNumber, 0);
      expect(calls.single.text, 'single step');
      expect(calls.single.toolCalls, isEmpty);
      expect(calls.single.toolResults, isEmpty);
      expect(calls.single.finishReason, LanguageModelV4FinishReason.stop);
    });

    test(
      'stopWhen semantics run tool execution before stopping in generateText',
      () async {
        var executions = 0;
        final result = await generateText<String>(
          model: _GenerateToolLoopModel(),
          maxSteps: 5,
          stopConditions: [hasToolCall('weather')],
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async {
                executions++;
                return 'ok';
              },
            ),
          },
        );

        expect(executions, 1);
        expect(result.steps, hasLength(1));
        expect(result.steps.first.toolResults, hasLength(1));
      },
    );

    test(
      'stopWhen semantics run tool execution before stopping in streamText',
      () async {
        var executions = 0;
        final result = await streamText<String>(
          model: _StreamTaxonomyModel(),
          maxSteps: 5,
          stopConditions: [hasToolCall('weather')],
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async {
                executions++;
                return 'ok';
              },
            ),
          },
        );

        await result.output;
        expect(executions, 1);
        final steps = await result.steps;
        expect(steps, hasLength(1));
        expect(steps.first.toolResults, hasLength(1));
      },
    );

    test(
      'onStepFinish works for multi-step in generateText and streamText',
      () async {
        final generateModel = _GenerateToolLoopModel();
        final generateSteps = <GenerateTextStepFinishEvent>[];

        await generateText<String>(
          model: generateModel,
          maxSteps: 3,
          tools: {
            'weather': tool<Map<String, dynamic>, Map<String, dynamic>>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (input, _) async => {'tempC': 23, 'city': input['city']},
            ),
          },
          onStepFinish: generateSteps.add,
        );

        expect(generateSteps, hasLength(2));
        expect(generateSteps.first.stepNumber, 0);
        expect(generateSteps.first.toolCalls, hasLength(1));
        expect(generateSteps.first.toolResults, hasLength(1));
        expect(generateSteps.last.stepNumber, 1);
        expect(generateSteps.last.toolCalls, isEmpty);

        final streamModel = _StreamTaxonomyModel();
        final streamSteps = <GenerateTextStepFinishEvent>[];
        final streamResult = await streamText<String>(
          model: streamModel,
          maxSteps: 3,
          tools: {
            'weather': tool<Map<String, dynamic>, Object?>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => const {'status': 'done'},
            ),
          },
          onStepFinish: streamSteps.add,
        );

        await streamResult.output;
        expect(streamSteps, hasLength(2));
        expect(streamSteps.first.stepNumber, 0);
        expect(streamSteps.last.stepNumber, 1);
      },
    );

    test(
      'prepareStep supports tool choice overrides and message compression',
      () async {
        final model = _PrepareStepModel();
        final result = await generateText<String>(
          model: model,
          maxSteps: 3,
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
            'other': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ignored',
            ),
          },
          prepareStep: (context) {
            if (context.stepNumber == 0) {
              return const GenerateTextPrepareStepResult(
                toolChoice: ToolChoiceSpecific(toolName: 'weather'),
                activeTools: ['weather'],
              );
            }
            return GenerateTextPrepareStepResult(
              messages: [context.messages.last],
            );
          },
        );

        expect(result.text, contains('final answer'));
        expect(model.calls, hasLength(2));
        expect(model.calls.first.tools.map((tool) => tool.name), ['weather']);
        expect(model.calls.first.toolChoice, isA<ToolChoiceSpecific>());
        expect(model.calls.last.prompt.messages, hasLength(1));
      },
    );

    test('toolChoice enforces none/required/specific/auto semantics', () async {
      await expectLater(
        () => generateText<String>(
          model: _ToolChoiceNoneViolationModel(),
          toolChoice: const ToolChoiceNone(),
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
        ),
        throwsA(isA<AiApiCallError>()),
      );

      await expectLater(
        () => generateText<String>(
          model: _RequiredNoToolModel(),
          toolChoice: const ToolChoiceRequired(),
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
        ),
        throwsA(isA<AiApiCallError>()),
      );

      await expectLater(
        () => generateText<String>(
          model: _StaticTextGenerateModel('ok'),
          toolChoice: const ToolChoiceSpecific(toolName: 'missing'),
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
        ),
        throwsA(isA<AiNoSuchToolError>()),
      );

      final specificModel = _SpecificToolModel();
      final specificResult = await generateText<String>(
        model: specificModel,
        toolChoice: const ToolChoiceSpecific(toolName: 'weather'),
        tools: {
          'weather': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
          'other': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ignored',
          ),
        },
        maxSteps: 3,
      );

      expect(specificResult.text, contains('specific done'));
      expect(specificModel.firstCallTools.map((tool) => tool.name).toList(), [
        'weather',
      ]);

      final autoResult = await generateText<String>(
        model: _StaticTextGenerateModel('auto-ok'),
        tools: const {},
      );
      expect(autoResult.text, 'auto-ok');
    });

    test(
      'streamText tool input lifecycle hooks receive full payloads',
      () async {
        final model = _StreamInputLifecycleModel();
        final starts = <StreamTextToolInputStartEvent>[];
        final deltas = <StreamTextToolInputDeltaEvent>[];
        final available = <StreamTextToolInputEndEvent>[];

        final result = await streamText<String>(
          model: model,
          maxSteps: 3,
          tools: {
            'search': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
          onInputStart: starts.add,
          onInputDelta: deltas.add,
          onInputAvailable: available.add,
        );

        await result.output;
        expect(starts, hasLength(1));
        expect(deltas, hasLength(2));
        expect(available, hasLength(1));
        expect(deltas.first.inputBuffer, '{"q":"par');
        expect(deltas.last.inputBuffer, '{"q":"paris"}');
        expect((available.single.input as Map<String, dynamic>)['q'], 'paris');
      },
    );

    test(
      'streamText waits for StreamPartToolCall before executing tool input',
      () async {
        final model = _DelayedToolCallStreamModel();
        var executions = 0;
        var outputCompleted = false;
        final inputAvailable = Completer<void>();

        final result = await streamText<String>(
          model: model,
          maxSteps: 3,
          tools: {
            'search': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async {
                executions++;
                return 'ok';
              },
            ),
          },
          onInputAvailable: (_) {
            if (!inputAvailable.isCompleted) {
              inputAvailable.complete();
            }
          },
        );

        result.output.then((_) {
          outputCompleted = true;
        });

        await inputAvailable.future;
        await Future<void>.delayed(Duration.zero);

        expect(executions, 0);
        expect(outputCompleted, isFalse);
        expect(model.streamCalls, 1);

        model.emitCompletedToolCall();

        await result.output;
        expect(executions, 1);
        expect(model.streamCalls, 2);

        final steps = await result.steps;
        expect(steps, hasLength(2));
        expect(steps.first.toolResults, hasLength(1));
      },
    );

    test(
      'streamText emits preliminary tool results from stream output',
      () async {
        final model = _StreamTaxonomyModel();
        final result = await streamText<String>(
          model: model,
          maxSteps: 3,
          tools: {
            'weather': tool<Map<String, dynamic>, Object?>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async {
                return Stream<Object?>.fromIterable(const [
                  {'status': 'loading'},
                  {'status': 'done', 'tempC': 23},
                ]);
              },
            ),
          },
        );

        final allEvents = await result.fullStream.toList();
        final events = allEvents
            .whereType<StreamTextToolResultEvent>()
            .toList();
        expect(events, hasLength(2));
        expect(events.first.preliminary, isTrue);
        expect(events.last.preliminary, isFalse);

        final firstText =
            (events.first.toolResult.output as ToolResultOutputText).text;
        final lastText =
            (events.last.toolResult.output as ToolResultOutputText).text;
        expect(firstText, contains('loading'));
        expect(lastText, contains('tempC'));
      },
    );

    test('experimental lifecycle callbacks are swallow-safe', () async {
      final model = _GenerateToolLoopModel();
      final result = await generateText<String>(
        model: model,
        maxSteps: 3,
        tools: {
          'weather': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
        },
        experimentalOnStart: (_) => throw StateError('onStart'),
        experimentalOnStepStart: (_) => throw StateError('onStepStart'),
        experimentalOnToolCallStart: (_) => throw StateError('onToolCallStart'),
        experimentalOnToolCallFinish: (_) =>
            throw StateError('onToolCallFinish'),
      );

      expect(result.text, contains('final answer'));

      final streamModel = _StreamTaxonomyModel();
      final streamResult = await streamText<String>(
        model: streamModel,
        maxSteps: 3,
        tools: {
          'weather': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
        },
        experimentalOnStart: (_) => throw StateError('streamOnStart'),
        experimentalOnStepStart: (_) => throw StateError('streamOnStepStart'),
        experimentalOnToolCallStart: (_) =>
            throw StateError('streamOnToolCallStart'),
        experimentalOnToolCallFinish: (_) =>
            throw StateError('streamOnToolCallFinish'),
      );

      expect(await streamResult.output, contains('tool result'));
    });

    test(
      'streamText partialOutputStream handles fenced JSON and incomplete chunks',
      () async {
        final model = _FencedJsonStreamModel();
        final result = await streamText<Map<String, dynamic>>(
          model: model,
          output: Output.object(
            schema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
          ),
        );

        final partials = await result.partialOutputStream.toList();
        expect(partials, isNotEmpty);
        final last = partials.last as Map<String, dynamic>;
        expect(last['status'], 'ok');
        expect((await result.output)['status'], 'ok');
      },
    );

    test(
      'streamText elementStream recovers from invalid array elements',
      () async {
        final model = _PartialArrayStreamModel();
        final result = await streamText<List<dynamic>>(
          model: model,
          output: Output.array(
            element: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
          ),
        );

        final elements = await result.elementStream
            .cast<Map<String, dynamic>>()
            .toList();
        expect(elements, [
          {'name': 'A'},
          {'name': 'B'},
        ]);
        final output = (await result.output).cast<Map<String, dynamic>>();
        expect(output, [
          {'name': 'A'},
          {'name': 'B'},
        ]);
      },
    );

    test('streamText output fails on final malformed JSON parse', () async {
      final model = _InvalidJsonStreamModel();
      Object? observed;
      final result = await streamText<Map<String, dynamic>>(
        model: model,
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        ),
        onError: (error) => observed = error,
      );

      final textChunks = result.textStream.handleError((_) {}).toList();
      final drains = [
        result.stream.handleError((_) {}).drain<void>(),
        result.fullStream.handleError((_) {}).drain<void>(),
        result.partialOutputStream.handleError((_) {}).drain<void>(),
        result.elementStream.handleError((_) {}).drain<void>(),
      ];
      await expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      expect((await textChunks).join(), '{"status":');
      await expectLater(result.text, throwsA(isA<AiNoObjectGeneratedError>()));
      await expectLater(
        result.finish,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await Future.wait(drains);
      expect(observed, isA<AiNoObjectGeneratedError>());
    });

    test(
      'generateText structured output throws AiNoObjectGeneratedError',
      () async {
        final model = _StaticTextGenerateModel('not-json');
        await expectLater(
          () => generateText<Map<String, dynamic>>(
            model: model,
            output: Output.object(
              schema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          ),
          throwsA(isA<AiNoObjectGeneratedError>()),
        );
      },
    );

    test(
      'rich result parity surfaces reasoning, sources, files and usage',
      () async {
        final generate = await generateText<String>(
          model: _RichGenerateModel(),
        );
        expect(generate.reasoningText, contains('I should cite sources'));
        expect(generate.sources, hasLength(1));
        expect(generate.files, hasLength(1));
        expect(
          (generate.totalUsage?.inputTokens.total ?? 0) +
              (generate.totalUsage?.outputTokens.total ?? 0),
          10,
        );
        expect(generate.responseMessages, isNotEmpty);

        final stream = await streamText<String>(model: _RichStreamModel());
        final finish = (await stream.fullStream.toList())
            .whereType<StreamTextFinishEvent<String>>()
            .single;
        expect(finish.reasoningText, contains('reasoning delta'));
        expect(finish.sources, hasLength(1));
        expect(finish.files, hasLength(1));
        expect(
          (finish.totalUsage?.inputTokens.total ?? 0) +
              (finish.totalUsage?.outputTokens.total ?? 0),
          11,
        );
        expect(finish.responseMessages, isNotEmpty);
      },
    );

    test(
      'streamText approval flow emits request then executes after approval',
      () async {
        final model = _ApprovalStreamModel();
        var executeCount = 0;
        final secureTool = tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          needsApproval: (_, _) => true,
          execute: (_, _) async {
            executeCount++;
            return 'approved';
          },
        );

        final first = await streamText<String>(
          model: model,
          tools: {'secureTool': secureTool},
          maxSteps: 3,
        );
        final firstFinish = (await first.fullStream.toList())
            .whereType<StreamTextFinishEvent<String>>()
            .single;
        expect(firstFinish.steps.first.toolApprovalRequests, hasLength(1));
        expect(executeCount, 0);

        final approval = LanguageModelV4ToolApprovalResponse(
          approvalId:
              firstFinish.steps.first.toolApprovalRequests.first.approvalId,
          approved: true,
          toolCallId: 'approval_stream_1',
          toolName: 'secureTool',
          argumentsFingerprint: '{"action":"run"}',
          policyRevision: 'default',
        );

        final second = await streamText<String>(
          model: model,
          tools: {'secureTool': secureTool},
          maxSteps: 3,
          toolApprovalResponses: [approval],
        );
        final secondFinish = (await second.fullStream.toList())
            .whereType<StreamTextFinishEvent<String>>()
            .single;
        expect(secondFinish.text, contains('approval complete'));
        expect(executeCount, 1);
      },
    );

    test('tool lifecycle chaos paths stay stable', () async {
      final badInputModel = _BadToolInputModel();
      final badInput = await generateText<String>(
        model: badInputModel,
        tools: {
          'unsafe': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
        },
        maxSteps: 2,
      );
      final badInputResults = badInput.steps
          .expand((step) => step.toolResults)
          .toList();
      expect(badInputResults.single.isError, isTrue);

      final throwModel = _GenerateToolLoopModel();
      final thrown = await generateText<String>(
        model: throwModel,
        tools: {
          'weather': dynamicTool<Object?>(
            execute: (_, _) async {
              throw 'string boom';
            },
          ),
        },
        maxSteps: 2,
      );
      final thrownResults = thrown.steps
          .expand((step) => step.toolResults)
          .toList();
      expect(thrownResults.single.isError, isTrue);
      expect(
        (thrownResults.single.output as ToolResultOutputText).text,
        contains('string boom'),
      );

      final approvalTool = tool<Map<String, dynamic>, String>(
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        needsApproval: (_, _) => true,
        execute: (_, _) async => 'should-not-run',
      );
      final first = await generateText<String>(
        model: _GenerateToolLoopModel(),
        tools: {'weather': approvalTool},
        maxSteps: 3,
      );
      final denied = await generateText<String>(
        model: _GenerateToolLoopModel(),
        tools: {'weather': approvalTool},
        maxSteps: 3,
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: first.toolApprovalRequests.first.approvalId,
            approved: false,
            reason: 'denied by user',
            toolCallId: 'call_weather_1',
            toolName: 'weather',
            argumentsFingerprint: '{"city":"Paris"}',
            policyRevision: 'default',
          ),
        ],
      );
      final deniedResults = denied.steps
          .expand((step) => step.toolResults)
          .toList();
      expect(deniedResults.single.isError, isTrue);
      expect(
        (deniedResults.single.output as ToolResultOutputText).text,
        contains('denied by user'),
      );

      final strictDynamic = await generateText<String>(
        model: _BadToolInputModel(),
        tools: {
          'unsafe': dynamicTool<Object?>(
            strict: true,
            execute: (_, _) async => 'never',
          ),
        },
        maxSteps: 2,
      );
      final strictDynamicResults = strictDynamic.steps
          .expand((step) => step.toolResults)
          .toList();
      expect(strictDynamicResults.single.isError, isTrue);
      expect(
        (strictDynamicResults.single.output as ToolResultOutputText).text,
        contains('Strict dynamic tools require JSON object input'),
      );
    });

    test(
      'mixed static and dynamic tools work with prepareStep activeTools',
      () async {
        final model = _GenerateToolLoopModel();
        Object? dynamicSeen;
        final result = await generateText<String>(
          model: model,
          tools: {
            'weather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'weather-ok',
            ),
            'custom': dynamicTool<String>(
              execute: (input, _) async {
                dynamicSeen = input;
                return 'dynamic-ok';
              },
            ),
          },
          maxSteps: 3,
          prepareStep: (context) {
            if (context.stepNumber == 0) {
              return const GenerateTextPrepareStepResult(
                activeTools: ['weather', 'custom'],
                toolChoice: ToolChoiceSpecific(toolName: 'weather'),
              );
            }
            return const GenerateTextPrepareStepResult(activeTools: ['custom']);
          },
        );

        expect(result.text, contains('final answer'));
        expect(dynamicSeen, isNull);
      },
    );

    test('generateObject parses structured JSON response', () async {
      final model = _JsonGenerateModel();
      final result = await generateObject<Map<String, dynamic>>(
        model: model,
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
              'tempC': {'type': 'number'},
            },
          },
          fromJson: (json) => json,
        ),
        prompt: 'Give weather JSON',
      );

      expect(result.object['city'], 'Paris');
      expect(result.object['tempC'], 21);
    });

    test(
      'streamObject emits parsed objects from streamed text deltas',
      () async {
        final model = _JsonStreamModel();
        final result = await streamObject<Map<String, dynamic>>(
          model: model,
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          prompt: 'stream json',
        );

        final objects = await result.stream.toList();
        expect(objects, isNotEmpty);
        expect(objects.last['status'], 'ok');
        expect(objects.last['count'], 2);

        final patchResult = await streamObject<Map<String, dynamic>>(
          model: _JsonStreamModel(),
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          prompt: 'stream json',
        );
        final patches = await patchResult.patchStream.toList();
        expect(patches, isNotEmpty);
        expect(patches.first.single.op, anyOf('replace', 'add'));
        expect(await patchResult.object, isA<Map<String, dynamic>>());
      },
    );

    test(
      'streamObject patch stream supports nested json pointer operations',
      () async {
        final result = await streamObject<Map<String, dynamic>>(
          model: _NestedJsonStreamModel(),
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        );

        await expectLater(
          result.object,
          throwsA(isA<AiNoObjectGeneratedError>()),
        );
      },
    );

    test('streamObject patch escapes json-pointer tokens', () async {
      final result = await streamObject<Map<String, dynamic>>(
        model: _EscapedKeyJsonStreamModel(),
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
      );

      await expectLater(
        result.object,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    });

    test(
      'streamObject throws AiNoObjectGeneratedError for invalid final object',
      () async {
        final result = await streamObject<Map<String, dynamic>>(
          model: _InvalidJsonStreamModel(),
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
        );

        await expectLater(
          result.object,
          throwsA(isA<AiNoObjectGeneratedError>()),
        );
      },
    );

    test(
      'ToolLoopAgent executes tool calls and returns final answer',
      () async {
        final model = _GenerateToolLoopModel();
        final agent = ToolLoopAgent(
          model: model,
          maxSteps: 3,
          tools: {
            'weather': tool<Map<String, dynamic>, Map<String, dynamic>>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
                fromJson: (json) => json,
              ),
              execute: (input, _) async {
                return {'city': input['city'], 'tempC': 23};
              },
            ),
          },
        );

        final output = await agent.generate(prompt: 'weather in paris?');
        expect(output.text, contains('23'));
      },
    );
  });
}

class _StaticTextGenerateModel extends LanguageModelV4 {
  _StaticTextGenerateModel(this.value);

  final String value;

  @override
  String get modelId => 'fake-static';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: value)],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _JsonGenerateModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-json';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: '{"city":"Paris","tempC":21}')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _JsonStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '{"status":"ok",'),
        StreamPartTextDelta(id: 'text-0', delta: '"count":2}'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _ErrorStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-error-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartError(error: 'boom'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.error),
      ]),
    );
  }
}

class _GenerateToolLoopModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-generate-tool-loop';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );

    if (!hasToolResult) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'call_weather_1',
            toolName: 'weather',
            input: {'city': 'Paris'},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }

    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'final answer after tool: 23')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _PrepareStepModel extends LanguageModelV4 {
  final calls = <LanguageModelV4CallOptions>[];

  @override
  String get modelId => 'fake-prepare-step';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    calls.add(options);
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );
    if (!hasToolResult) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'prepare_call_1',
            toolName: 'weather',
            input: {'city': 'Paris'},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'final answer')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _ToolChoiceNoneViolationModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-toolchoice-none';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return const LanguageModelV4GenerateResult(
      content: [
        LanguageModelV4ToolCallPart(
          toolCallId: 'none_violation',
          toolName: 'weather',
          input: {'city': 'Paris'},
        ),
      ],
      finishReason: LanguageModelV4FinishReason.toolCalls,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _RequiredNoToolModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-toolchoice-required';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'no tools called')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _SpecificToolModel extends LanguageModelV4 {
  List<LanguageModelV4FunctionTool> firstCallTools = const [];

  @override
  String get modelId => 'fake-toolchoice-specific';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    firstCallTools = firstCallTools.isEmpty
        ? options.functionTools.toList()
        : firstCallTools;
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );

    if (!hasToolResult) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'specific_call_1',
            toolName: 'weather',
            input: {'city': 'Paris'},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }

    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'specific done')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _StreamTaxonomyModel extends LanguageModelV4 {
  int streamCalls = 0;

  @override
  String get modelId => 'fake-stream-taxonomy';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls++;
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );

    if (!hasToolResult) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable([
          StreamPartTextStart(id: 'text-0'),
          StreamPartTextDelta(id: 'text-0', delta: 'Checking weather...'),
          StreamPartTextEnd(id: 'text-0'),
          StreamPartReasoningStart(id: 'reasoning-0'),
          StreamPartReasoningDelta(
            id: 'reasoning-0',
            delta: 'Need to call tool',
          ),
          StreamPartReasoningEnd(id: 'reasoning-0'),
          StreamPartSource(
            source: LanguageModelV4SourcePart(
              id: 'src-1',
              url: 'https://example.com/weather',
              title: 'Weather Source',
            ),
          ),
          StreamPartFile(
            file: LanguageModelV4FilePart(
              data: DataContentUrl(Uri.parse('https://example.com/report.pdf')),
              mediaType: 'application/pdf',
              filename: 'report.pdf',
            ),
          ),
          StreamPartToolInputStart(id: 'call_weather_1', toolName: 'weather'),
          StreamPartToolInputDelta(
            id: 'call_weather_1',
            delta: '{"city":"Paris"}',
          ),
          StreamPartToolInputEnd(id: 'call_weather_1'),
          StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'call_weather_1',
              toolName: 'weather',
              input: {'city': 'Paris'},
            ),
          ),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.toolCalls),
        ]),
      );
    }

    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-1'),
        StreamPartTextDelta(
          id: 'text-1',
          delta: 'Final answer with tool result.',
        ),
        StreamPartTextEnd(id: 'text-1'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _StreamInputLifecycleModel extends LanguageModelV4 {
  int streamCalls = 0;

  @override
  String get modelId => 'fake-stream-input-lifecycle';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls++;
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );

    if (!hasToolResult) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
          StreamPartToolInputStart(id: 'call_search_1', toolName: 'search'),
          StreamPartToolInputDelta(id: 'call_search_1', delta: '{"q":"par'),
          StreamPartToolInputDelta(id: 'call_search_1', delta: 'is"}'),
          StreamPartToolInputEnd(id: 'call_search_1'),
          StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'call_search_1',
              toolName: 'search',
              input: {'q': 'paris'},
            ),
          ),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.toolCalls),
        ]),
      );
    }

    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-1'),
        StreamPartTextDelta(id: 'text-1', delta: 'done'),
        StreamPartTextEnd(id: 'text-1'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _DelayedToolCallStreamModel extends LanguageModelV4 {
  final _toolCallController = StreamController<LanguageModelV4StreamPart>();
  var streamCalls = 0;

  @override
  String get modelId => 'fake-delayed-tool-call-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  void emitCompletedToolCall() {
    _toolCallController
      ..add(
        const StreamPartToolCall(
          toolCall: LanguageModelV4ToolCallPart(
            toolCallId: 'call_search_delayed',
            toolName: 'search',
            input: {'q': 'paris'},
          ),
        ),
      )
      ..add(
        const StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.toolCalls,
        ),
      );
    unawaited(_toolCallController.close());
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    streamCalls++;
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );

    if (!hasToolResult) {
      _toolCallController
        ..add(
          const StreamPartToolInputStart(
            id: 'call_search_delayed',
            toolName: 'search',
          ),
        )
        ..add(
          const StreamPartToolInputDelta(
            id: 'call_search_delayed',
            delta: '{"q":"paris"}',
          ),
        )
        ..add(const StreamPartToolInputEnd(id: 'call_search_delayed'));
      return LanguageModelV4StreamResult(stream: _toolCallController.stream);
    }

    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-1'),
        StreamPartTextDelta(id: 'text-1', delta: 'done'),
        StreamPartTextEnd(id: 'text-1'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _FencedJsonStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-fenced-json-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '```json\n{"status":'),
        StreamPartTextDelta(id: 'text-0', delta: '"ok"}\n```'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _PartialArrayStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-partial-array-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '[{"name":"A"},'),
        StreamPartTextDelta(id: 'text-0', delta: '{"na'),
        StreamPartTextDelta(id: 'text-0', delta: 'me":"B"}]'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _InvalidJsonStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-invalid-json-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '{"status":'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _TransformStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-transform-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: 'Hello'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _RichGenerateModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-rich-generate';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4GenerateResult(
      content: [
        const LanguageModelV4ReasoningPart(text: 'I should cite sources.'),
        const LanguageModelV4SourcePart(
          id: 'src-1',
          url: 'https://example.com',
          title: 'Example',
        ),
        LanguageModelV4FilePart(
          data: DataContentUrl(Uri.parse('https://example.com/doc.pdf')),
          mediaType: 'application/pdf',
          filename: 'doc.pdf',
        ),
        const LanguageModelV4TextPart(text: 'rich done'),
      ],
      finishReason: LanguageModelV4FinishReason.stop,
      usage: const LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(total: 4),
        outputTokens: LanguageModelV4OutputTokenUsage(total: 6),
      ),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _RichStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-rich-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable([
        const StreamPartReasoningDelta(
          id: 'reasoning-stream-0',
          delta: 'reasoning delta',
        ),
        const StreamPartSource(
          source: LanguageModelV4SourcePart(
            id: 'src-stream',
            url: 'https://example.com/stream',
            title: 'Stream Source',
          ),
        ),
        StreamPartFile(
          file: LanguageModelV4FilePart(
            data: DataContentUrl(Uri.parse('https://example.com/stream.pdf')),
            mediaType: 'application/pdf',
            filename: 'stream.pdf',
          ),
        ),
        const StreamPartTextStart(id: 'text-0'),
        const StreamPartTextDelta(id: 'text-0', delta: 'stream-rich'),
        const StreamPartTextEnd(id: 'text-0'),
        const StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.stop,
          usage: LanguageModelV4Usage(
            inputTokens: LanguageModelV4InputTokenUsage(total: 5),
            outputTokens: LanguageModelV4OutputTokenUsage(total: 6),
          ),
        ),
      ]),
    );
  }
}

class _ApprovalStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-approval-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );
    if (!hasToolResult) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
          StreamPartToolInputStart(
            id: 'approval_stream_1',
            toolName: 'secureTool',
          ),
          StreamPartToolInputDelta(
            id: 'approval_stream_1',
            delta: '{"action":"run"}',
          ),
          StreamPartToolInputEnd(id: 'approval_stream_1'),
          StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'approval_stream_1',
              toolName: 'secureTool',
              input: {'action': 'run'},
            ),
          ),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.toolCalls),
        ]),
      );
    }

    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-1'),
        StreamPartTextDelta(id: 'text-1', delta: 'approval complete'),
        StreamPartTextEnd(id: 'text-1'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _BadToolInputModel extends LanguageModelV4 {
  @override
  String get modelId => 'fake-bad-tool-input';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final hasToolResult = options.prompt.messages.any(
      (message) =>
          message.role == LanguageModelV4Role.tool &&
          message.content.whereType<LanguageModelV4ToolResultPart>().isNotEmpty,
    );
    if (!hasToolResult) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'bad_input_1',
            toolName: 'unsafe',
            input: 'not-an-object',
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'done')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _ResponseEnvelopeGenerateModel extends LanguageModelV4 {
  @override
  String get modelId => 'response-envelope-generate';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4GenerateResult(
      content: const [LanguageModelV4TextPart(text: 'hello')],
      finishReason: LanguageModelV4FinishReason.stop,
      request: const LanguageModelV4RequestMetadata(
        body: {'raw': 'request-body'},
      ),
      response: const LanguageModelV4ResponseMetadata(
        id: 'resp-1',
        modelId: 'response-envelope-generate',
        body: {'raw': 'response-body'},
      ),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _ResponseEnvelopeStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'response-envelope-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: 'ok'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      request: const LanguageModelV4RequestMetadata(
        body: {'raw': 'request-body'},
      ),
      response: const LanguageModelV4ResponseMetadata(
        body: {'raw': 'response-body'},
      ),
    );
  }
}

class _OnFinishRichStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'finish-rich-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: 'done'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.stop,
          usage: LanguageModelV4Usage(
            inputTokens: LanguageModelV4InputTokenUsage(total: 1),
            outputTokens: LanguageModelV4OutputTokenUsage(total: 2),
          ),
          providerMetadata: {
            'fake': {'finish': 'metadata'},
          },
        ),
      ]),
      warnings: const [
        LanguageModelV4OtherWarning(message: 'provider-warning'),
      ],
      request: const LanguageModelV4RequestMetadata(body: {'foo': 'bar'}),
      response: LanguageModelV4ResponseMetadata(
        id: 'resp_stream_1',
        modelId: 'finish-rich-stream',
        timestamp: DateTime.parse('2026-01-01T00:00:00.000Z'),
        body: const {'raw': 'stream-body'},
      ),
    );
  }
}

class _NestedJsonStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'nested-json-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '{"recipe":{}}\n'),
        StreamPartTextDelta(
          id: 'text-0',
          delta: '{"recipe":{"name":"Lasagna"}}\n',
        ),
        StreamPartTextDelta(
          id: 'text-0',
          delta: '{"recipe":{"name":"Lasagna","steps":["Boil"]}}',
        ),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      response: LanguageModelV4ResponseMetadata(
        id: 'nested_1',
        modelId: 'nested-json-stream',
        timestamp: DateTime.parse('2026-01-01T00:00:00.000Z'),
      ),
    );
  }
}

class _EscapedKeyJsonStreamModel extends LanguageModelV4 {
  @override
  String get modelId => 'escaped-key-json-stream';

  @override
  String get provider => 'fake';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable(const [
        StreamPartTextStart(id: 'text-0'),
        StreamPartTextDelta(id: 'text-0', delta: '{}\n'),
        StreamPartTextDelta(id: 'text-0', delta: '{"a/b":1}\n'),
        StreamPartTextDelta(id: 'text-0', delta: '{"a/b":1,"c~d":2}'),
        StreamPartTextEnd(id: 'text-0'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}
