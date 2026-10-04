import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

class _CleanupModel extends LanguageModelV4 {
  _CleanupModel(this.source);
  final Stream<LanguageModelV4StreamPart> source;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'cleanup';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: source);
}

class _ReusableStreamModel extends LanguageModelV4 {
  _ReusableStreamModel({this.fail = false});
  final bool fail;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'reusable-stream';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (fail) {
      return LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.error(StateError('failed')),
      );
    }
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable(const [
        StreamPartTextStart(id: 'text'),
        StreamPartTextDelta(id: 'text', delta: 'ok'),
        StreamPartTextEnd(id: 'text'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _ObservedToken extends CancellationToken {
  _ObservedToken() {
    _events = StreamController<void>.broadcast(
      onListen: () => attaches++,
      onCancel: () => detaches++,
    );
  }

  late final StreamController<void> _events;
  final _cancelled = Completer<void>();
  var cancelled = false;
  var attaches = 0;
  var detaches = 0;

  @override
  bool get isCancelled => cancelled;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => _events.stream;

  @override
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _cancelled.complete();
    _events
      ..add(null)
      ..close();
  }
}

void main() {
  test('cleanup error does not replace a primary stream error', () async {
    final escaped = <Object>[];
    final complete = Completer<void>();
    final primary = StateError('source failed');
    final cleanup = StateError('cleanup failed');
    Object? observed;

    runZonedGuarded(() async {
      final source = StreamController<LanguageModelV4StreamPart>(
        onCancel: () => Future<void>.error(cleanup),
      );
      final result = await streamText(model: _CleanupModel(source.stream));
      final outcome = result.text.then<void>(
        (_) {},
        onError: (Object error) => observed = error,
      );
      final reasoningFilesOutcome = result.reasoningFiles.then<void>(
        (_) {},
        onError: (Object error) {
          expect(error, same(primary));
        },
      );
      final documentSourcesOutcome = result.documentSources.then<void>(
        (_) {},
        onError: (Object error) {
          expect(error, same(primary));
        },
      );
      source.addError(primary);
      await Future.wait([
        outcome,
        reasoningFilesOutcome,
        documentSourcesOutcome,
      ]);
      await source.close();
      await Future<void>.delayed(Duration.zero);
      complete.complete();
    }, (error, stack) => escaped.add(error));

    await complete.future.timeout(const Duration(seconds: 2));
    expect(observed, same(primary));
    expect(escaped, isEmpty);
  });

  test(
    'streamText detaches onAbort observers after repeated completion',
    () async {
      final token = _ObservedToken();
      addTearDown(token._events.close);
      final model = _ReusableStreamModel();

      for (var index = 0; index < 50; index++) {
        final result = await streamText(
          model: model,
          abortSignal: token,
          onAbort: () {},
        );
        await result.fullStream.toList();
        await Future<void>.delayed(Duration.zero);
        expect(token._events.hasListener, isFalse);
      }

      expect(token.attaches, greaterThanOrEqualTo(50));
      expect(token.detaches, token.attaches);
    },
  );

  test('streamText detaches onAbort observers after repeated errors', () async {
    final token = _ObservedToken();
    addTearDown(token._events.close);
    final model = _ReusableStreamModel(fail: true);

    for (var index = 0; index < 50; index++) {
      final result = await streamText(
        model: model,
        abortSignal: token,
        onAbort: () {},
      );
      await expectLater(result.fullStream.toList(), throwsA(isA<StateError>()));
      await Future<void>.delayed(Duration.zero);
      expect(token._events.hasListener, isFalse);
    }

    expect(token.attaches, greaterThanOrEqualTo(50));
    expect(token.detaches, token.attaches);
  });
}
