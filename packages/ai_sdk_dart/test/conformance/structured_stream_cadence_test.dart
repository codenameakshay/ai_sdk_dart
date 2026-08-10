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
      StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
    ]);
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
            .map(jsonEncode)
            .toList();
        final elementsFuture = result.elementStream
            .cast<Map<String, dynamic>>()
            .toList();
        final partials = await partialsFuture;
        final elements = await elementsFuture;

        expect(partials, orderedEquals(partials.toSet().toList()));
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
        expect(
          counters.parseAttemptsFor(
            PartialJsonParsePhase.streamTextArrayElements,
          ),
          lessThan(6),
        );
      },
    );

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
  });
}
