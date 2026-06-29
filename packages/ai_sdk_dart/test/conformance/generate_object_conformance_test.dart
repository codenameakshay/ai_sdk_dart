import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';
import 'helpers/matchers.dart';

/// A language model that delays before returning text — used to test timeouts.
class _SlowTextModel implements LanguageModelV3 {
  _SlowTextModel(this.text, this.delay);

  final String text;
  final Duration delay;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'slow-model';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    await Future<void>.delayed(delay);
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    await Future<void>.delayed(delay);
    return LanguageModelV3StreamResult(
      stream: Stream<LanguageModelV3StreamPart>.fromIterable([
        StreamPartTextStart(id: 't'),
        StreamPartTextDelta(id: 't', delta: text),
        StreamPartTextEnd(id: 't'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]),
    );
  }
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
        throwsAiError<AiNoObjectGeneratedError>(),
      );
    });

    test('throws AiNoObjectGeneratedError on non-JSON text', () async {
      final model = FakeTextModel('not json at all');
      expect(
        () => generateObject(model: model, schema: schema, prompt: 'x'),
        throwsAiError<AiNoObjectGeneratedError>(),
      );
    });

    test('throws AiNoObjectGeneratedError when JSON is an array not object',
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
    });

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

    test('converts ModelMessages (all roles) into provider messages',
        () async {
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
      );
      final messages = model.lastCallOptions!.prompt.messages;
      // prompt is null here, so messages == the 4 converted messages.
      expect(messages, hasLength(4));
      expect(messages[0].role.name, 'system');
      expect(messages[1].role.name, 'user');
      expect(messages[2].role.name, 'assistant');
      expect(messages[3].role.name, 'tool');
    });

    test('forwards generation params (maxOutputTokens/temperature/topP)',
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
    });

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
        throwsA(isA<Object>()),
      );
    });
  });
}
