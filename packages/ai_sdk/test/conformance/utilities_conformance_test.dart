import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('utilities conformance', () {
    // ── generateId() ──────────────────────────────────────────────────────

    group('generateId()', () {
      test('returns a non-empty string', () {
        final id = generateId();
        expect(id, isNotEmpty);
      });

      test('with no arguments starts with "id-"', () {
        final id = generateId();
        expect(id, startsWith('id-'));
      });

      test('with custom prefix starts with that prefix followed by "-"', () {
        expect(generateId('msg'), startsWith('msg-'));
        expect(generateId('user'), startsWith('user-'));
        expect(generateId('tool'), startsWith('tool-'));
      });

      test('consecutive calls return unique IDs', () {
        final ids = List.generate(100, (_) => generateId());
        expect(ids.toSet().length, ids.length);
      });

      test('IDs from different prefixes are still unique', () {
        final a = generateId('a');
        final b = generateId('b');
        expect(a, isNot(b));
      });
    });

    // ── createIdGenerator() ───────────────────────────────────────────────

    group('createIdGenerator()', () {
      test('returns a function', () {
        final gen = createIdGenerator(prefix: 'x');
        expect(gen, isA<Function>());
      });

      test('generated IDs start with the given prefix + "-"', () {
        final gen = createIdGenerator(prefix: 'msg');
        expect(gen(), startsWith('msg-'));
        expect(gen(), startsWith('msg-'));
      });

      test('default prefix is "id"', () {
        final gen = createIdGenerator();
        expect(gen(), startsWith('id-'));
      });

      test('consecutive calls return unique IDs', () {
        final gen = createIdGenerator(prefix: 'test');
        final ids = List.generate(50, (_) => gen());
        expect(ids.toSet().length, ids.length);
      });

      test('two generators with same prefix produce independent sequences', () {
        final gen1 = createIdGenerator(prefix: 'x');
        final gen2 = createIdGenerator(prefix: 'x');
        final id1 = gen1();
        final id2 = gen2();
        // Both start with 'x-' but are generated at different times, so unique
        expect(id1, startsWith('x-'));
        expect(id2, startsWith('x-'));
        expect(id1, isNot(id2));
      });
    });

    // ── simulateReadableStream() ──────────────────────────────────────────

    group('simulateReadableStream()', () {
      test('emits all parts in the given order', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ];

        final emitted = await simulateReadableStream(parts: parts).toList();
        expect(emitted.length, 4);
        expect(emitted[0], isA<StreamPartTextStart>());
        expect(emitted[1], isA<StreamPartTextDelta>());
        expect(emitted[2], isA<StreamPartTextEnd>());
        expect(emitted[3], isA<StreamPartFinish>());
      });

      test('emits parts in correct typed order', () async {
        final parts = [
          const StreamPartReasoningDelta(delta: 'thinking'),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ];

        final emitted = await simulateReadableStream(parts: parts).toList();
        expect(emitted[0], isA<StreamPartReasoningDelta>());
        expect((emitted[0] as StreamPartReasoningDelta).delta, 'thinking');
      });

      test('empty parts list produces empty stream', () async {
        final emitted = await simulateReadableStream(parts: []).toList();
        expect(emitted, isEmpty);
      });

      test('with no delay, stream completes quickly', () async {
        final stopwatch = Stopwatch()..start();
        final parts = List.generate(
          10,
          (i) => StreamPartTextDelta(id: 't1', delta: 'chunk$i'),
        );
        await simulateReadableStream(parts: parts).toList();
        stopwatch.stop();
        // Should complete well within 1 second (no delays)
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('with delay, each part is delayed', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
        ];

        final stopwatch = Stopwatch()..start();
        await simulateReadableStream(
          parts: parts,
          delay: const Duration(milliseconds: 20),
        ).toList();
        stopwatch.stop();

        // 3 parts × 20ms = at least 60ms
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
      });

      test('preserves stream part data through emission', () async {
        const delta = StreamPartTextDelta(id: 'myId', delta: 'specific text');
        final emitted = await simulateReadableStream(parts: [delta]).toList();
        final emittedDelta = emitted[0] as StreamPartTextDelta;
        expect(emittedDelta.id, 'myId');
        expect(emittedDelta.delta, 'specific text');
      });
    });
  });
}
