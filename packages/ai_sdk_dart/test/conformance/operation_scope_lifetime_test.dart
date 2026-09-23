import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class _ObservedToken extends CancellationToken {
  _ObservedToken() {
    events = StreamController<void>.broadcast(
      onListen: () => attaches++,
      onCancel: () => detaches++,
    );
  }
  late final StreamController<void> events;
  int attaches = 0;
  int detaches = 0;
  @override
  Stream<void> get cancellationEvents => events.stream;
}

void main() {
  test('completed operations detach from a reusable caller token', () async {
    final token = _ObservedToken();
    addTearDown(token.events.close);
    final model = FakeEmbeddingModel([1.0, 2.0]);
    for (var index = 0; index < 100; index++) {
      await embed(model: model, value: 'value-$index', abortSignal: token);
      expect(token.events.hasListener, isFalse);
    }
    expect(token.attaches, 100);
    expect(token.detaches, token.attaches);
  });
}
