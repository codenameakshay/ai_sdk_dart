import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// A language model that delays before returning text — used to test timeouts.
class _SlowTextModel extends LanguageModelV4 {
  _SlowTextModel(this.text, this.delay);

  final String text;
  final Duration delay;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'slow-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    await Future<void>.delayed(delay);
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    await Future<void>.delayed(delay);
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable([
        StreamPartTextStart(id: 't'),
        StreamPartTextDelta(id: 't', delta: text),
        StreamPartTextEnd(id: 't'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _HangingObjectModel extends LanguageModelV4 {
  final started = Completer<void>();
  AbortSignal? signal;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'hanging-object';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) {
    signal = options.abortSignal;
    if (!started.isCompleted) started.complete();
    return Completer<LanguageModelV4GenerateResult>().future;
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();
}

class _MetadataObjectModel extends LanguageModelV4 {
  _MetadataObjectModel(this.text);

  final String text;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'metadata-object';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: text)],
    finishReason: LanguageModelV4FinishReason.stop,
    request: const LanguageModelV4RequestMetadata(body: {'request': true}),
    response: LanguageModelV4ResponseMetadata(
      id: 'response-1',
      body: const {'response': true},
    ),
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();
}

void main() {
  group('generateObject conformance', () {
    final schema = Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
      fromJson: (json) => json,
    );

    test('parses a JSON object and returns rawJson + response', () async {
      final model = FakeTextModel('{"name":"Alice"}');
      final result = await generateObject(
        model: model,
        schema: schema,
        prompt: 'name?',
      );
      expect(result.object['name'], 'Alice');
      expect(result.rawJson, {'name': 'Alice'});
      expect(result.response, isNotNull);
    });

    test(
      'filters request and response bodies according to body inclusion',
      () async {
        final model = _MetadataObjectModel('{"name":"Alice"}');
        final omitted = await generateObject(
          model: model,
          schema: schema,
          prompt: 'name?',
        );
        expect(omitted.response.request?.body, isNull);
        expect(omitted.response.response?.body, isNull);

        final included = await generateObject(
          model: model,
          schema: schema,
          prompt: 'name?',
          bodyInclusion: const BodyInclusionPolicy.all(),
        );
        expect(included.response.request?.body, {'request': true});
        expect(included.response.response?.body, {'response': true});
      },
    );

    test('includes response metadata on structured output errors', () async {
      final model = _MetadataObjectModel('not json');
      await expectLater(
        generateObject(model: model, schema: schema, prompt: 'name?'),
        throwsA(
          isA<AiNoObjectGeneratedError>().having(
            (error) => error.response?.id,
            'response id',
            'response-1',
          ),
        ),
      );
    });

    test('recovers JSON from ```json``` fences', () async {
      final model = FakeTextModel('```json\n{"name":"Bob"}\n```');
      final result = await generateObject(
        model: model,
        schema: schema,
        prompt: 'name?',
      );
      expect(result.object['name'], 'Bob');
    });

    test('throws AiNoObjectGeneratedError on empty content', () async {
      final model = FakeTextModel('');
      expect(
        () => generateObject(model: model, schema: schema, prompt: 'x'),
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    });

    test('throws AiNoObjectGeneratedError on non-JSON text', () async {
      final model = FakeTextModel('not json at all');
      expect(
        () => generateObject(model: model, schema: schema, prompt: 'x'),
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    });

    test(
      'throws AiNoObjectGeneratedError when JSON is an array not object',
      () async {
        final model = FakeTextModel('[1, 2, 3]');
        Object? caught;
        try {
          await generateObject(model: model, schema: schema, prompt: 'x');
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AiNoObjectGeneratedError>());
        expect((caught as AiNoObjectGeneratedError).text, '[1, 2, 3]');
      },
    );

    test('system instruction is prepended and passed to model', () async {
      final model = FakeTextModel('{"name":"x"}');
      await generateObject(
        model: model,
        schema: schema,
        system: 'You are a helpful assistant.',
        prompt: 'name?',
      );
      final sentSystem = model.lastCallOptions?.prompt.system;
      expect(sentSystem, contains('You are a helpful assistant.'));
      expect(sentSystem, contains('Return a single JSON object'));
    });

    test('converts ModelMessages (all roles) into provider messages', () async {
      final model = FakeTextModel('{"name":"x"}');
      await generateObject(
        model: model,
        schema: schema,
        messages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'sys'),
          ModelMessage(role: ModelMessageRole.user, content: 'hi'),
          ModelMessage(role: ModelMessageRole.assistant, content: 'hello'),
          ModelMessage(role: ModelMessageRole.tool, content: 'result'),
        ],
        allowSystemInMessages: true,
      );
      final messages = model.lastCallOptions!.prompt.messages;
      // prompt is null here, so messages == the 4 converted messages.
      expect(messages, hasLength(4));
      expect(messages[0].role.name, 'system');
      expect(messages[1].role.name, 'user');
      expect(messages[2].role.name, 'assistant');
      expect(messages[3].role.name, 'tool');
    });

    test(
      'forwards generation params (maxOutputTokens/temperature/topP)',
      () async {
        final model = FakeTextModel('{"name":"x"}');
        await generateObject(
          model: model,
          schema: schema,
          prompt: 'x',
          maxOutputTokens: 128,
          temperature: 0.3,
          topP: 0.8,
        );
        expect(model.lastCallOptions?.maxOutputTokens, 128);
        expect(model.lastCallOptions?.temperature, 0.3);
        expect(model.lastCallOptions?.topP, 0.8);
      },
    );

    test('timeout throws when model is too slow', () async {
      final model = _SlowTextModel(
        '{"name":"x"}',
        const Duration(milliseconds: 200),
      );
      expect(
        () => generateObject(
          model: model,
          schema: schema,
          prompt: 'x',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('timeout also covers synchronous schema decoding', () async {
      final model = FakeTextModel('{"name":"x"}');
      final decodingSchema = Schema<Map<String, dynamic>>(
        jsonSchema: schema.jsonSchema,
        fromJson: (json) {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsed < const Duration(milliseconds: 20)) {}
          return json;
        },
      );

      await expectLater(
        generateObject(
          model: model,
          schema: decodingSchema,
          prompt: 'x',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('pre-cancelled generateObject does not invoke the model', () async {
      final model = _HangingObjectModel();
      await expectLater(
        generateObject(
          model: model,
          schema: schema,
          abortSignal: CancellationToken()..cancel(),
        ),
        throwsA(isA<AiOperationCancelledError>()),
      );
      expect(model.signal, isNull);
    });

    test('active generateObject cancellation aborts provider work', () async {
      final model = _HangingObjectModel();
      final token = CancellationToken();
      final pending = generateObject(
        model: model,
        schema: schema,
        abortSignal: token,
      );
      await model.started.future;
      token.cancel();
      await expectLater(pending, throwsA(isA<AiOperationCancelledError>()));
      expect(model.signal?.isCancelled, isTrue);
    });
  });
}
