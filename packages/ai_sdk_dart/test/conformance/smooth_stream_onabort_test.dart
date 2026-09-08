import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
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
    });

    // ── delay option ──────────────────────────────────────────────────────

    group('delayInMs', () {
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
      final outputDrain = result.output.catchError((_) => null);

      // Cancel before consuming stream
      token.cancel();
      // Give the microtask queue a chance to run
      await Future<void>.delayed(Duration.zero);

      expect(abortCalled, isTrue);
      // Consume stream to avoid dangling subscription
      await result.text.catchError((_) => '');
      await outputDrain;
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

    test(
      'onAbort is not called when cancelling after normal completion',
      () async {
        var abortCalls = 0;
        final token = CancellationToken();

        final result = await streamText(
          model: FakeTextModel('Hello'),
          prompt: 'hi',
          abortSignal: token,
          onAbort: () {
            abortCalls++;
          },
        );

        await result.text;
        token.cancel();
        await Future<void>.delayed(Duration.zero);

        expect(abortCalls, 0);
      },
    );

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

    test('cancelling mid-stream stops processing further deltas', () async {
      // Regression: cancelling must actually break the read loop, not merely
      // fire the onAbort callback while the stream keeps draining.
      final token = CancellationToken();
      final model = _SlowStreamModel(const [
        'one ',
        'two ',
        'three ',
        'four ',
        'five',
      ], chunkDelayInMs: 25);
      final received = <String>[];
      final result = await streamText(
        model: model,
        prompt: 'hi',
        abortSignal: token,
      );

      final sub = result.textStream.listen((delta) {
        received.add(delta);
        if (received.length == 2) token.cancel();
      });

      await expectLater(result.text, throwsA(isA<AiOperationCancelledError>()));
      await sub.cancel();

      // The loop broke after the cancel, so not all five deltas were seen.
      expect(received.length, greaterThanOrEqualTo(2));
      expect(received.length, lessThan(5));
    });

    test(
      'cancelling during a silent stream fails text stream promptly',
      () async {
        final token = CancellationToken();
        final result = await streamText(
          model: _SilentStreamModel(),
          prompt: 'hi',
          abortSignal: token,
        );

        final textStreamFuture = result.textStream.toList();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        token.cancel();

        await expectLater(
          textStreamFuture,
          throwsA(isA<AiOperationCancelledError>()),
        );
        await expectLater(
          result.text,
          throwsA(isA<AiOperationCancelledError>()),
        );
      },
    );

    test(
      'onAbort is not called when cancelling after terminal error',
      () async {
        var abortCalls = 0;
        final token = CancellationToken();
        final result = await streamText(
          model: _ImmediateErrorStreamModel(),
          prompt: 'hi',
          abortSignal: token,
          onAbort: () {
            abortCalls++;
          },
        );

        await expectLater(result.text, throwsA(isA<StateError>()));
        token.cancel();
        await Future<void>.delayed(Duration.zero);

        expect(abortCalls, 0);
      },
    );
  });
}

/// A streaming model that emits text deltas spaced by [chunkDelayInMs], so a
/// mid-stream cancellation can land between chunks.
class _SlowStreamModel extends LanguageModelV4 {
  _SlowStreamModel(this.deltas, {this.chunkDelayInMs = 25});

  final List<String> deltas;
  final int chunkDelayInMs;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'slow-stream';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: deltas.join())],
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final parts = <LanguageModelV4StreamPart>[
      StreamPartTextStart(id: 't'),
      for (final d in deltas) StreamPartTextDelta(id: 't', delta: d),
      StreamPartTextEnd(id: 't'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ];
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: parts,
        chunkDelayInMs: chunkDelayInMs,
      ),
    );
  }
}

class _SilentStreamModel extends LanguageModelV4 {
  @override
  String get provider => 'fake';

  @override
  String get modelId => 'silent-stream';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final controller = StreamController<LanguageModelV4StreamPart>();
    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

class _ImmediateErrorStreamModel extends LanguageModelV4 {
  @override
  String get provider => 'fake';

  @override
  String get modelId => 'immediate-error-stream';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable([
        StreamPartError(error: StateError('boom')),
      ]),
    );
  }
}
