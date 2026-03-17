import 'package:ai_sdk/ai_sdk.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';
import 'helpers/matchers.dart';

void main() {
  group('structured output conformance', () {
    // ── Output.text() ─────────────────────────────────────────────────────

    group('Output.text()', () {
      test('returns raw string passthrough', () async {
        final model = FakeTextModel('Hello!');
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.output, 'Hello!');
        expect(result.text, 'Hello!');
      });
    });

    // ── Output.object() ───────────────────────────────────────────────────

    group('Output.object()', () {
      test('parses JSON object into typed map', () async {
        final model = FakeTextModel('{"city":"Paris","tempC":21}');
        final result = await generateText<Map<String, dynamic>>(
          model: model,
          prompt: 'Give weather JSON',
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
        );
        expect(result.output['city'], 'Paris');
        expect(result.output['tempC'], 21);
      });

      test('recovers JSON from ```json ... ``` code fences', () async {
        final model = FakeTextModel(
          '```json\n{"city":"London","tempC":15}\n```',
        );
        final result = await generateText<Map<String, dynamic>>(
          model: model,
          prompt: 'Weather JSON',
          output: Output.object(
            schema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
          ),
        );
        expect(result.output['city'], 'London');
      });

      test('throws AiNoObjectGeneratedError for invalid JSON', () async {
        final model = FakeTextModel('this is not JSON');
        expect(
          () => generateText<Map<String, dynamic>>(
            model: model,
            prompt: 'JSON please',
            output: Output.object(
              schema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          ),
          throwsAiError<AiNoObjectGeneratedError>(),
        );
      });

      test('AiNoObjectGeneratedError exposes text and cause', () async {
        final model = FakeTextModel('not-json');
        Object? caught;
        try {
          await generateText<Map<String, dynamic>>(
            model: model,
            prompt: 'JSON please',
            output: Output.object(
              schema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          );
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<AiNoObjectGeneratedError>());
        final err = caught as AiNoObjectGeneratedError;
        expect(err.text, 'not-json');
        expect(err.cause, isNotNull);
        expect(err.message, isNotEmpty);
      });
    });

    // ── Output.array() ────────────────────────────────────────────────────

    group('Output.array()', () {
      test('parses JSON array into typed list', () async {
        final model = FakeTextModel('[{"name":"Alice"},{"name":"Bob"}]');
        final result = await generateText<List<dynamic>>(
          model: model,
          prompt: 'list people',
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
        expect(result.output.length, 2);
        expect((result.output[0] as Map)['name'], 'Alice');
        expect((result.output[1] as Map)['name'], 'Bob');
      });

      test(
        'throws AiNoObjectGeneratedError when model returns non-array',
        () async {
          final model = FakeTextModel('{"key":"value"}');
          expect(
            () => generateText<List<Map<String, dynamic>>>(
              model: model,
              prompt: 'list',
              output: Output.array(
                element: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
              ),
            ),
            throwsAiError<AiNoObjectGeneratedError>(),
          );
        },
      );
    });

    // ── Output.choice() ───────────────────────────────────────────────────

    group('Output.choice()', () {
      test('returns exact matching choice value', () async {
        final model = FakeTextModel('sunny');
        final result = await generateText<String>(
          model: model,
          prompt: 'weather?',
          output: Output.choice(options: const ['sunny', 'rainy', 'cloudy']),
        );
        expect(result.output, 'sunny');
      });

      test('throws AiNoObjectGeneratedError for disallowed value', () async {
        final model = FakeTextModel('windy');
        expect(
          () => generateText<String>(
            model: model,
            prompt: 'weather?',
            output: Output.choice(options: const ['sunny', 'rainy']),
          ),
          throwsAiError<AiNoObjectGeneratedError>(),
        );
      });

      test('accepts choice value wrapped in JSON string quotes', () async {
        // Model may return "sunny" (JSON string) — should be unwrapped
        final model = FakeTextModel('"rainy"');
        final result = await generateText<String>(
          model: model,
          prompt: 'weather?',
          output: Output.choice(options: const ['sunny', 'rainy']),
        );
        expect(result.output, 'rainy');
      });
    });

    // ── Output.json() ─────────────────────────────────────────────────────

    group('Output.json()', () {
      test('returns raw parsed JSON without schema validation', () async {
        final model = FakeTextModel('{"ok":true,"count":2}');
        final result = await generateText<Object?>(
          model: model,
          prompt: 'json?',
          output: Output.json(),
        );
        final map = result.output as Map<String, dynamic>;
        expect(map['ok'], isTrue);
        expect(map['count'], 2);
      });

      test('returns JSON array as List', () async {
        final model = FakeTextModel('[1,2,3]');
        final result = await generateText<Object?>(
          model: model,
          prompt: 'list?',
          output: Output.json(),
        );
        expect(result.output, isA<List>());
      });

      test('throws AiNoObjectGeneratedError for invalid JSON', () async {
        final model = FakeTextModel('not json');
        expect(
          () => generateText<Object?>(
            model: model,
            prompt: 'json?',
            output: Output.json(),
          ),
          throwsAiError<AiNoObjectGeneratedError>(),
        );
      });
    });

    // ── AiNoObjectGeneratedError.isInstance() ─────────────────────────────

    group('AiNoObjectGeneratedError.isInstance()', () {
      test('returns true for AiNoObjectGeneratedError instance', () {
        final err = AiNoObjectGeneratedError(
          message: 'fail',
          text: 'bad',
          response: null,
          usage: null,
        );
        expect(AiNoObjectGeneratedError.isInstance(err), isTrue);
      });

      test('returns false for non-error objects', () {
        expect(AiNoObjectGeneratedError.isInstance('not an error'), isFalse);
        expect(AiNoObjectGeneratedError.isInstance(42), isFalse);
        expect(
          AiNoObjectGeneratedError.isInstance(
            const AiApiCallError('api error'),
          ),
          isFalse,
        );
      });
    });
  });
}
