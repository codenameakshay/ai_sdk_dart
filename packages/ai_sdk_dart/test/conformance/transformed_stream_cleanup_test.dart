import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'transformed stream cleanup preserves the source failure without escaping',
    () async {
      final primary = StateError('transform source failed');
      final cleanup = StateError('transform cleanup failed');
      final escaped = <Object>[];
      final complete = Completer<void>();
      Object? observed;
      runZonedGuarded(() async {
        final source = StreamController<String>(
          onCancel: () => Future<void>.error(cleanup),
        );
        final result = await streamText(
          model: FakeTextModel('input'),
          experimentalTransform: (_) {
            source.addError(primary);
            return source.stream;
          },
        );
        try {
          await result.text;
        } catch (error) {
          observed = error;
        }
        await source.close();
        await Future<void>.delayed(Duration.zero);
        complete.complete();
      }, (error, stack) => escaped.add(error));
      await complete.future.timeout(const Duration(seconds: 2));
      expect(observed, same(primary));
      expect(escaped, isEmpty);
    },
  );
}
