import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/retry_helper.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  setUp(debugResetRetryHooksForTests);
  tearDown(debugResetRetryHooksForTests);

  // ---------------------------------------------------------------------------
  // generateText – new generation parameters
  // ---------------------------------------------------------------------------

  group('generateText generation parameters', () {
    test('passes topK to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(model: model, prompt: 'hi', topK: 40);
      expect(model.capturedOptions.last.topK, 40);
    });

    test('passes presencePenalty to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(model: model, prompt: 'hi', presencePenalty: 0.5);
      expect(model.capturedOptions.last.presencePenalty, 0.5);
    });

    test('passes frequencyPenalty to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(model: model, prompt: 'hi', frequencyPenalty: 0.3);
      expect(model.capturedOptions.last.frequencyPenalty, 0.3);
    });

    test('passes stopSequences to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(
        model: model,
        prompt: 'hi',
        stopSequences: ['STOP', 'END'],
      );
      expect(model.capturedOptions.last.stopSequences, ['STOP', 'END']);
    });

    test('passes seed to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(model: model, prompt: 'hi', seed: 42);
      expect(model.capturedOptions.last.seed, 42);
    });

    test('passes headers to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      await generateText(
        model: model,
        prompt: 'hi',
        headers: {'x-custom': 'value'},
      );
      expect(model.capturedOptions.last.headers, {'x-custom': 'value'});
    });

    test('maxRetries retries on failure up to maxRetries times', () async {
      var callCount = 0;
      final model = _CountingFakeModel(
        onCall: () {
          callCount++;
          if (callCount < 3) throw Exception('transient error');
          return LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'success')],
            finishReason: LanguageModelV3FinishReason.stop,
          );
        },
      );

      final result = await generateText(
        model: model,
        prompt: 'hi',
        maxRetries: 3,
      );
      expect(result.text, 'success');
      expect(callCount, 3);
    });

    test('maxRetries rethrows after exhausting retries', () async {
      final model = FakeErrorModel(Exception('permanent error'));
      expect(
        () => generateText(model: model, prompt: 'hi', maxRetries: 2),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'does not retry non-retryable API errors such as auth failures',
      () async {
        var callCount = 0;
        final model = _CountingFakeModel(
          onCall: () {
            callCount++;
            throw const AiApiCallError(
              'Unauthorized',
              statusCode: 401,
              type: 'authentication_error',
              isRetryable: false,
            );
          },
        );

        await expectLater(
          () => generateText(model: model, prompt: 'hi', maxRetries: 3),
          throwsA(isA<AiApiCallError>()),
        );
        expect(callCount, 1);
      },
    );

    test('does not retry after cancellation is requested', () async {
      final token = CancellationToken();
      var callCount = 0;
      final model = _CountingFakeModel(
        onCall: () {
          callCount++;
          token.cancel();
          throw const AiApiCallError(
            'Cancelled upstream request',
            statusCode: 429,
            isRetryable: true,
          );
        },
      );

      await expectLater(
        () => generateText(
          model: model,
          prompt: 'hi',
          maxRetries: 3,
          abortSignal: token,
        ),
        throwsA(isA<AiApiCallError>()),
      );
      expect(callCount, 1);
    });

    test('honors Retry-After headers before retrying', () async {
      final slept = <Duration>[];
      debugConfigureRetryHooksForTests(
        sleep: (duration) async => slept.add(duration),
        randomDouble: () => throw StateError('backoff jitter should not run'),
      );

      var callCount = 0;
      final model = _CountingFakeModel(
        onCall: () {
          callCount++;
          if (callCount == 1) {
            throw const AiApiCallError(
              'Rate limited',
              statusCode: 429,
              isRetryable: true,
              responseHeaders: {'Retry-After': '3'},
            );
          }
          return LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'success')],
            finishReason: LanguageModelV3FinishReason.stop,
          );
        },
      );

      final result = await generateText(
        model: model,
        prompt: 'hi',
        maxRetries: 2,
      );

      expect(result.text, 'success');
      expect(callCount, 2);
      expect(slept, [const Duration(seconds: 3)]);
    });

    test('activeToolNames filters tools passed to provider', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final tools = {
        'tool_a': tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
          description: 'Tool A',
        ),
        'tool_b': tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
          description: 'Tool B',
        ),
      };

      await generateText(
        model: model,
        prompt: 'hi',
        tools: tools,
        activeToolNames: ['tool_a'],
      );

      final passedToolNames = model.capturedOptions.last.tools
          .map((t) => t.name)
          .toList();
      expect(passedToolNames, contains('tool_a'));
      expect(passedToolNames, isNot(contains('tool_b')));
    });
  });

  // ---------------------------------------------------------------------------
  // streamText – new generation parameters
  // ---------------------------------------------------------------------------

  group('streamText generation parameters', () {
    test('passes topK to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(model: model, prompt: 'hi', topK: 40);
      await result.text; // drain the stream
      expect(model.capturedOptions.last.topK, 40);
    });

    test('passes presencePenalty to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        presencePenalty: 0.5,
      );
      await result.text;
      expect(model.capturedOptions.last.presencePenalty, 0.5);
    });

    test('passes frequencyPenalty to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        frequencyPenalty: 0.3,
      );
      await result.text;
      expect(model.capturedOptions.last.frequencyPenalty, 0.3);
    });

    test('passes stopSequences to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        stopSequences: ['STOP'],
      );
      await result.text;
      expect(model.capturedOptions.last.stopSequences, ['STOP']);
    });

    test('passes seed to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(model: model, prompt: 'hi', seed: 99);
      await result.text;
      expect(model.capturedOptions.last.seed, 99);
    });

    test('passes headers to LanguageModelV3CallOptions', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        headers: {'x-req-id': 'abc'},
      );
      await result.text;
      expect(model.capturedOptions.last.headers, {'x-req-id': 'abc'});
    });

    test('maxRetries retries doStream on failure', () async {
      var callCount = 0;
      final model = _CountingFakeModel(
        onCall: () {
          callCount++;
          if (callCount < 2) throw Exception('transient');
          return LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'streamed')],
            finishReason: LanguageModelV3FinishReason.stop,
          );
        },
        isStream: true,
      );

      final result = await streamText(
        model: model,
        prompt: 'hi',
        maxRetries: 2,
      );
      final text = await result.text;
      expect(text, 'streamed');
      expect(callCount, 2);
    });

    test(
      'retries retryable API errors with capped exponential jitter',
      () async {
        final slept = <Duration>[];
        final attempts = <RetryAttemptObservation>[];
        final jitterValues = <double>[0.25, 1.0, 1.0, 1.0];
        debugConfigureRetryHooksForTests(
          sleep: (duration) async => slept.add(duration),
          randomDouble: () => jitterValues.removeAt(0),
          onAttempt: attempts.add,
        );

        var callCount = 0;
        final model = _CountingFakeModel(
          onCall: () {
            callCount++;
            if (callCount < 5) {
              throw const AiApiCallError(
                'Transient upstream failure',
                statusCode: 503,
                isRetryable: true,
              );
            }
            return LanguageModelV3GenerateResult(
              content: [LanguageModelV3TextPart(text: 'streamed')],
              finishReason: LanguageModelV3FinishReason.stop,
            );
          },
          isStream: true,
        );

        final result = await streamText(
          model: model,
          prompt: 'hi',
          maxRetries: 4,
        );
        final text = await result.text;

        expect(text, 'streamed');
        expect(callCount, 5);
        expect(slept, [
          const Duration(milliseconds: 25),
          const Duration(milliseconds: 200),
          const Duration(milliseconds: 400),
          const Duration(milliseconds: 500),
        ]);
        expect(attempts.map((attempt) => attempt.attemptNumber), [
          1,
          2,
          3,
          4,
          5,
        ]);
      },
    );

    test('activeToolNames filters tools passed to provider', () async {
      final model = FakeCapturingModel(responseText: 'ok');
      final tools = {
        'tool_a': tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
          description: 'Tool A',
        ),
        'tool_b': tool<Map<String, dynamic>, String>(
          inputSchema: jsonSchema({'type': 'object'}),
          description: 'Tool B',
        ),
      };

      final result = await streamText(
        model: model,
        prompt: 'hi',
        tools: tools,
        activeToolNames: ['tool_a'],
      );
      await result.text;

      final passedToolNames = model.capturedOptions.last.tools
          .map((t) => t.name)
          .toList();
      expect(passedToolNames, contains('tool_a'));
      expect(passedToolNames, isNot(contains('tool_b')));
    });
  });

  // ---------------------------------------------------------------------------
  // jsonSchema() helper
  // ---------------------------------------------------------------------------

  group('jsonSchema()', () {
    test('creates a Schema<Map<String, dynamic>>', () {
      final schema = jsonSchema({'type': 'object', 'properties': {}});
      expect(schema, isA<Schema<Map<String, dynamic>>>());
    });

    test('jsonSchema field matches the provided map', () {
      final map = {
        'type': 'string',
        'enum': ['a', 'b'],
      };
      final schema = jsonSchema(map);
      expect(schema.jsonSchema, map);
    });

    test('fromJson returns the map unmodified', () {
      final schema = jsonSchema({'type': 'object'});
      final input = {'key': 'value', 'num': 1};
      expect(schema.fromJson(input), same(input));
    });

    test('can be used as tool inputSchema', () async {
      final myTool = tool<Map<String, dynamic>, String>(
        inputSchema: jsonSchema({'type': 'object', 'properties': {}}),
        description: 'Test tool',
        execute: (input, _) async => 'result',
      );
      expect(myTool.inputSchema.jsonSchema['type'], 'object');
    });
  });
}

// ---------------------------------------------------------------------------
// Helper fake models
// ---------------------------------------------------------------------------

typedef _GenerateCallback = LanguageModelV3GenerateResult Function();

/// A fake model that delegates to a callback, allowing controlled failures.
class _CountingFakeModel implements LanguageModelV3 {
  _CountingFakeModel({required this.onCall, this.isStream = false});

  final _GenerateCallback onCall;
  final bool isStream;

  @override
  final String provider = 'fake';

  @override
  final String modelId = 'fake-counting-model';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return onCall();
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final result = onCall();
    final text = result.content
        .whereType<LanguageModelV3TextPart>()
        .map((p) => p.text)
        .join();
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: result.finishReason),
        ],
      ),
    );
  }
}
