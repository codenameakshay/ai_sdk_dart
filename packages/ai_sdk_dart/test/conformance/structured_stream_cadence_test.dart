import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/partial_json.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  FakeStreamModel characterStream(String text) {
    return FakeStreamModel([
      const StreamPartTextStart(id: 't1'),
      for (final char in text.split(''))
        StreamPartTextDelta(id: 't1', delta: char),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);
  }

  FakeStreamModel deltaStream(List<String> deltas) {
    return FakeStreamModel([
      const StreamPartTextStart(id: 't1'),
      for (final delta in deltas) StreamPartTextDelta(id: 't1', delta: delta),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);
  }

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

        expect(partials, hasLength(1));
        expect(jsonEncode(partials.single), jsonEncode(await result.output));
        final item = (partials.single['items'] as List).single as Map;
        expect(item['text'], 'quote: "hi" and slash \\');
        expect(item['emoji'], '\u{1F600}');
        expect(
          counters.parseAttemptsFor(PartialJsonParsePhase.streamTextPartial),
          lessThan(8),
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

        expect(partials, hasLength(1));
        expect(partials.single['emoji'], '😀');
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
        const text =
            '{}\n'
            '{"count":1,"message":"\\uD83D\\uDE00"}\n'
            '{"count":1,"message":"\\uD83D\\uDE00"}\n'
            '{"count":2,"nested":{"items":[1,2]}}\n';
        final result = await streamObject<Map<String, dynamic>>(
          model: characterStream(text),
          schema: objectSchema(),
        );

        final partials = await result.partialObjectStream.toList();

        expect(partials.map(jsonEncode).toList(), [
          '{}',
          '{"count":1,"message":"😀"}',
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
          lessThan(8),
        );
      },
    );

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
