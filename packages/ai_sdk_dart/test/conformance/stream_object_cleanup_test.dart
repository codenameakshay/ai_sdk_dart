import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class _CleanupModel extends FakeTextModel {
  _CleanupModel(this.source) : super('');
  final Stream<LanguageModelV4StreamPart> source;
  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: source);
}

void main() {
  test('cancellation during final decoding cannot return success', () async {
    final token = CancellationToken();
    final result = await streamObject(
      model: _CleanupModel(
        Stream.value(const StreamPartTextDelta(id: 'text', delta: '{}')),
      ),
      abortSignal: token,
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (value) {
          token.cancel();
          return value;
        },
      ),
    );
    await expectLater(result.object, throwsA(isA<AiOperationCancelledError>()));
  });

  for (final inBand in [false, true]) {
    test(
      'cleanup error preserves primary ${inBand ? 'in-band' : 'source'} error',
      () async {
        final escaped = <Object>[];
        final complete = Completer<void>();
        final primary = StateError('source failed');
        final cleanup = StateError('cleanup failed');
        Object? observed;
        runZonedGuarded(
          () async {
            final source = StreamController<LanguageModelV4StreamPart>(
              onCancel: () => Future<void>.error(cleanup),
            );
            final result = await streamObject(
              model: _CleanupModel(source.stream),
              schema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (value) => value,
              ),
            );
            final outcome = result.object.then<void>(
              (_) {},
              onError: (Object error) {
                observed = error;
              },
            );
            if (inBand) {
              source.add(StreamPartError(error: primary));
            } else {
              source.addError(primary);
            }
            await outcome;
            await source.close();
            await Future<void>.delayed(Duration.zero);
            complete.complete();
          },
          (error, stack) {
            escaped.add(error);
          },
        );
        await complete.future.timeout(const Duration(seconds: 2));
        expect(observed, same(primary));
        expect(escaped, isEmpty);
      },
    );
  }
}
