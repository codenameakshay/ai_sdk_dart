import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('smoothStream', () {
    // ── basic chunking ────────────────────────────────────────────────────

    group('basic chunking', () {
      test('emits full delta when chunkSize <= 0', () async {
        final transform = smoothStream(chunkSize: 0);
        final chunks = await transform('hello world').toList();
        expect(chunks, ['hello world']);
      });

      test('splits delta into chunkSize pieces', () async {
        final transform = smoothStream(chunkSize: 3);
        final chunks = await transform('abcdef').toList();
        expect(chunks, ['abc', 'def']);
      });

      test('handles delta shorter than chunkSize', () async {
        final transform = smoothStream(chunkSize: 20);
        final chunks = await transform('hi').toList();
        expect(chunks, ['hi']);
      });

      test('empty delta emits no chunks', () async {
        final transform = smoothStream(chunkSize: 5);
        final chunks = await transform('').toList();
        expect(chunks, isEmpty);
      });

      test('default chunkSize=12 splits 24-char delta into 2 parts', () async {
        final transform = smoothStream();
        final delta = 'a' * 24;
        final chunks = await transform(delta).toList();
        expect(chunks, hasLength(2));
        expect(chunks.join(), delta);
      });

      test('reassembled chunks equal original delta', () async {
        const delta = 'The quick brown fox jumps over the lazy dog';
        final transform = smoothStream(chunkSize: 7);
        final chunks = await transform(delta).toList();
        expect(chunks.join(), delta);
      });

      test('returns a Stream<String>', () {
        final transform = smoothStream(chunkSize: 5);
        final result = transform('hello');
        expect(result, isA<Stream<String>>());
      });
    });

    // ── delay option ──────────────────────────────────────────────────────

    group('delayInMs', () {
      test('with no delay, chunks arrive quickly', () async {
        final transform = smoothStream(chunkSize: 3, delayInMs: 0);
        final sw = Stopwatch()..start();
        await transform('abcdef').toList();
        sw.stop();
        // No delay: should complete well under 100ms
        expect(sw.elapsedMilliseconds, lessThan(100));
      });

      test('with delay, total time ≥ (chunks-1)*delayInMs', () async {
        const delay = 20; // ms
        const delta = 'abcdef'; // 3 chunks of 2 chars
        final transform = smoothStream(chunkSize: 2, delayInMs: delay);
        final sw = Stopwatch()..start();
        await transform(delta).toList();
        sw.stop();
        // 3 chunks → 2 inter-chunk delays
        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(2 * delay - 5));
      });

      test('with delay, chunks are still correct', () async {
        final transform = smoothStream(chunkSize: 3, delayInMs: 5);
        final chunks = await transform('abcdef').toList();
        expect(chunks, ['abc', 'def']);
      });
    });

    // ── integration with streamText ────────────────────────────────────────

    group('integration with streamText()', () {
      test('smoothStream transform is applied to text deltas', () async {
        final model = FakeTextModel('Hello World!');
        final result = await streamText(
          model: model,
          prompt: 'hi',
          experimentalTransform: smoothStream(chunkSize: 3),
        );
        final chunks = await result.textStream.toList();
        // Each chunk should be ≤ 3 chars
        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(3));
        }
        expect(chunks.join(), 'Hello World!');
      });
    });
  });

  // ── onAbort callback ──────────────────────────────────────────────────────

  group('streamText onAbort callback', () {
    test('onAbort is called when abortSignal is cancelled', () async {
      var abortCalled = false;
      final token = CancellationToken();

      final model = FakeTextModel('Hello from model');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        abortSignal: token,
        onAbort: () {
          abortCalled = true;
        },
      );

      // Cancel before consuming stream
      token.cancel();
      // Give the microtask queue a chance to run
      await Future<void>.delayed(Duration.zero);

      expect(abortCalled, isTrue);
      // Consume stream to avoid dangling subscription
      await result.text.catchError((_) => '');
    });

    test('onAbort is not called when stream finishes normally', () async {
      var abortCalled = false;
      final token = CancellationToken();

      final model = FakeTextModel('Hello');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        abortSignal: token,
        onAbort: () {
          abortCalled = true;
        },
      );

      // Consume stream normally without cancelling
      await result.text;
      await Future<void>.delayed(Duration.zero);

      expect(abortCalled, isFalse);
    });

    test('onAbort is not called when abortSignal is null', () async {
      var abortCalled = false;

      final model = FakeTextModel('Hello');
      final result = await streamText(
        model: model,
        prompt: 'hi',
        onAbort: () {
          abortCalled = true;
        },
      );

      await result.text;
      await Future<void>.delayed(Duration.zero);

      expect(abortCalled, isFalse);
    });
  });
}
