import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/partial_json.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  FakeStreamModel characterStream(String text) =>
      textDeltaStream(text.split(''));

  final deltaStream = textDeltaStream;

  String largeArrayPayload(int elementCount) {
    final buffer = StringBuffer('[');
    for (var index = 0; index < elementCount; index++) {
      if (index > 0) {
        buffer.write(',');
      }
      buffer.write(
        '{"id":$index,"label":"item-$index","nested":{"value":"abcdefghijklmno"}}',
      );
    }
    buffer.write(']');
    return buffer.toString();
  }

  late PartialJsonDebugCounters counters;

  setUp(() {
    counters = PartialJsonDebugCounters();
    partialJsonDebugCounters = counters;
  });

  tearDown(() {
    partialJsonDebugCounters = null;
  });

  group('structured stream cadence', () {
    test(
      'streamText object output handles fenced nested JSON with escapes and split unicode',
      () async {
        const text =
            '```json\n'
            '{"items":[{"text":"quote: \\"hi\\" and slash \\\\","emoji":"\\uD83D\\uDE00"}],"done":true}'
            '\n```';
        final result = await streamText<Map<String, dynamic>>(
          model: characterStream(text),
          output: Output.object(schema: objectSchema()),
        );

        final partials = await result.partialOutputStream
            .cast<Map<String, dynamic>>()
            .toList();

        expect(partials, isNotEmpty);
        expect(jsonEncode(partials.last), jsonEncode(await result.output));
        final item = (partials.last['items'] as List).single as Map;
        expect(item['text'], 'quote: "hi" and slash \\');
        expect(item['emoji'], '\u{1F600}');
        expect(
          counters.parseAttemptsFor(PartialJsonParsePhase.streamTextPartial),
          lessThan(32),
        );
      },
    );

    test(
      'streamText object output handles raw astral unicode split across deltas',
      () async {
        const highSurrogate = '\uD83D';
        const lowSurrogate = '\uDE00';
        final result = await streamText<Map<String, dynamic>>(
          model: deltaStream([
            '{"emoji":"',
            highSurrogate,
            lowSurrogate,
            '","done":true}',
          ]),
          output: Output.object(schema: objectSchema()),
        );

        final partials = await result.partialOutputStream
            .cast<Map<String, dynamic>>()
            .toList();

        expect(partials, isNotEmpty);
        expect(partials.last['emoji'], '😀');
        expect((await result.output)['emoji'], '😀');
      },
    );

    test(
      'streamText array output emits unique partials and elements for incomplete nested values',
      () async {
        const text =
            '[{"id":1,"nested":{"text":"A\\uD83D\\uDE00"}},{"id":2,"nested":{"text":"B\\\\C"}}]';
        final result = await streamText<List<dynamic>>(
          model: characterStream(text),
          output: Output.array(element: objectSchema()),
        );

        final partialsFuture = result.partialOutputStream
            .cast<List<dynamic>>()
            .toList();
        final elementsFuture = result.elementStream
            .cast<Map<String, dynamic>>()
            .toList();
        final partials = await partialsFuture;
        final elements = await elementsFuture;

        expect(partials.map(jsonEncode).toList(), [
          '[{"id":1,"nested":{"text":"A😀"}}]',
          '[{"id":1,"nested":{"text":"A😀"}},{"id":2,"nested":{"text":"B\\\\C"}}]',
        ]);
        expect(elements, [
          {
            'id': 1,
            'nested': {'text': 'A😀'},
          },
          {
            'id': 2,
            'nested': {'text': r'B\C'},
          },
        ]);
        expect((partials.first.first as Map)['id'], 1);
        expect(partials.first, hasLength(1));
        expect(() => partials.first.add({'id': 99}), throwsUnsupportedError);
        expect(
          counters.parseAttemptsFor(
            PartialJsonParsePhase.streamTextArrayElements,
          ),
          lessThan(6),
        );
      },
    );

    test('streamText empty arrays emit one empty partial snapshot', () async {
      final result = await streamText<List<dynamic>>(
        model: characterStream('[]'),
        output: Output.array(element: objectSchema()),
      );

      final partials = await result.partialOutputStream
          .cast<List<dynamic>>()
          .toList();

      expect(partials, hasLength(1));
      expect(partials.single, isEmpty);
      expect(await result.output, isEmpty);
    });

    test(
      'streamObject emits unique snapshots and parse attempts scale with completed objects',
      () async {
        const text = '{"count":2,"nested":{"items":[1,2]}}';
        final result = await streamObject<Map<String, dynamic>>(
          model: characterStream(text),
          schema: objectSchema(),
        );

        final partials = await result.partialObjectStream.toList();

        expect(partials.map(jsonEncode).toList(), [
          '{"count":2,"nested":{"items":[1]}}',
          '{"count":2,"nested":{"items":[1,2]}}',
        ]);
        expect(await result.object, {
          'count': 2,
          'nested': {
            'items': [1, 2],
          },
        });
        expect(
          counters.parseAttemptsFor(PartialJsonParsePhase.streamObjectSnapshot),
          lessThan(12),
        );
      },
    );

    test(
      'streamObject previews a growing string before root closure',
      () async {
        final result = await streamObject<Map<String, dynamic>>(
          model: deltaStream([
            '{"nested":{"text":"Hello there ',
            'again, ',
            'world"}}',
          ]),
          schema: objectSchema(),
        );
        final partials = await result.partialObjectStream.toList();
        expect(partials.length, greaterThanOrEqualTo(2));
        expect((partials.first['nested'] as Map)['text'], 'Hello there ');
        expect(
          (partials.last['nested'] as Map)['text'],
          'Hello there again, world',
        );
        expect(
          () => (partials.first['nested'] as Map)['text'] = 'changed',
          throwsUnsupportedError,
        );
        expect((await result.object)['nested'], {
          'text': 'Hello there again, world',
        });
      },
    );

    test(
      'streamText previews raw JSON without decoding its schema early',
      () async {
        var decodes = 0;
        final schema = Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) {
            decodes++;
            return json;
          },
        );
        final result = await streamText<Map<String, dynamic>>(
          model: deltaStream(['{"text":"Growing now ', 'again', '"}']),
          output: Output.object(schema: schema),
        );
        final partials = await result.partialOutputStream.toList();
        expect(partials.length, greaterThanOrEqualTo(2));
        expect((partials.first as Map)['text'], 'Growing now ');
        expect(decodes, 1);
        expect((await result.output)['text'], 'Growing now again');
        expect(decodes, 1);
      },
    );

    test(
      'split escapes preserve Unicode and immutable nested previews',
      () async {
        final result = await streamObject<Map<String, dynamic>>(
          model: deltaStream([
            '{"items":[{"text":"eight chars \\',
            'uD83D\\',
            'uDE00 and slash \\\\',
            ' end"}]}',
          ]),
          schema: objectSchema(),
        );
        final partials = await result.partialObjectStream.toList();
        final finalObject = await result.object;
        expect(finalObject['items'], [
          {'text': 'eight chars 😀 and slash \\ end'},
        ]);
        expect(partials.last, finalObject);
        final items = partials.last['items'] as List;
        expect(() => items.add(null), throwsUnsupportedError);
        expect(() => (items.first as Map)['text'] = '', throwsUnsupportedError);
      },
    );

    test('repaired previews cannot validate an invalid final object', () async {
      final result = await streamObject<Map<String, dynamic>>(
        model: deltaStream(['{"text":"unfinished value']),
        schema: objectSchema(),
      );
      final finalFailure = expectLater(
        result.object,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
      await expectLater(
        result.partialObjectStream,
        emitsInOrder([
          isA<Map<String, dynamic>>(),
          emitsError(isA<AiNoObjectGeneratedError>()),
        ]),
      );
      await finalFailure;
    });

    test(
      'streamText large top-level arrays scale decode attempts with element count',
      () async {
        const elementCount = 128;
        final result = await streamText<List<dynamic>>(
          model: characterStream(largeArrayPayload(elementCount)),
          output: Output.array(element: objectSchema()),
        );

        final elements = await result.elementStream
            .cast<Map<String, dynamic>>()
            .toList();
        final output = await result.output;

        expect(elements, hasLength(elementCount));
        expect(output, hasLength(elementCount));
        expect(counters.decodeAttempts, lessThanOrEqualTo(elementCount + 4));
        expect(
          counters.parseAttemptsFor(
            PartialJsonParsePhase.streamTextArrayElements,
          ),
          lessThanOrEqualTo(elementCount + 2),
        );
        expect(counters.snapshotCount, lessThanOrEqualTo(elementCount));
        expect(
          counters.snapshotElementsCopied,
          lessThanOrEqualTo(elementCount * (elementCount + 1) ~/ 2),
        );
      },
    );
  });
}
