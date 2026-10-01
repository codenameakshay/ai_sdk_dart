import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  for (final retainedState in ['queued', 'delivered']) {
    test(
      'one listener cancellation retains another listener $retainedState audio budget',
      () async {
        final transport = _Transport();
        transport.add({
          'type': 'session.created',
          'session': {'id': 'session-1'},
        });
        final session = await RealtimeSession.connect(
          apiKey: 'fixture',
          maxBufferedAudioBytes: 2,
          connector: (_, _) async => transport,
        );
        addTearDown(session.close);
        final first = session.events.listen((_) {}, onError: (_) {});
        final second = session.events.listen((_) {}, onError: (_) {});
        first.pause();
        if (retainedState == 'queued') second.pause();
        addTearDown(second.cancel);
        transport.add({
          'type': 'response.output_audio.delta',
          'delta': base64Encode([1, 2]),
        });
        await Future<void>.delayed(Duration.zero);
        await first.cancel();
        var audioEvents = 0;
        final errors = <Object>[];
        final active = session.events.listen((event) {
          if (event is RealtimeAudioDelta) audioEvents++;
        }, onError: errors.add);
        addTearDown(active.cancel);
        transport.add({
          'type': 'response.output_audio.delta',
          'delta': base64Encode([3, 4]),
        });
        await Future<void>.delayed(Duration.zero);
        expect(audioEvents, 0);
        expect(errors, contains(isA<RealtimeException>()));
        second.resume();
        await Future<void>.delayed(Duration.zero);
        await session.acknowledgeAudio(2);
      },
    );
  }

  test('paused queued text precedes done after peer EOF', () async {
    final transport = _Transport();
    final session = await _connect(transport);
    final seen = <String>[];
    final done = Completer<void>();
    final subscription = session.events.listen((event) {
      if (event is RealtimeTextDelta) seen.add(event.delta);
    }, onDone: done.complete);
    subscription.pause();
    transport.text('retained');
    unawaited(transport.close());
    await Future<void>.delayed(Duration.zero);
    subscription.resume();
    await done.future;
    expect(seen, ['retained']);
    await session.close();
  });

  test('paused queue overflow becomes an observable terminal error', () async {
    final transport = _Transport();
    final session = await _connect(transport, maxCount: 1);
    addTearDown(session.close);
    final errors = <Object>[];
    var done = false;
    final subscription = session.events.listen(
      (_) {},
      onError: errors.add,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
    subscription.pause();
    transport.text('first');
    transport.text('second');
    await Future<void>.delayed(Duration.zero);
    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(errors, contains(isA<RealtimeException>()));
    expect(done, isTrue);
  });
}

Future<RealtimeSession> _connect(_Transport transport, {int maxCount = 4}) {
  transport.add({
    'type': 'session.created',
    'session': {'id': 'session-1'},
  });
  return RealtimeSession.connect(
    apiKey: 'fixture',
    maxBufferedEventCount: maxCount,
    connector: (_, _) async => transport,
  );
}

class _Transport implements RealtimeTransport {
  final _incoming = StreamController<Object?>();
  void add(Map<String, dynamic> event) => _incoming.add(jsonEncode(event));
  void text(String text) => add({
    'type': 'response.output_text.delta',
    'response_id': 'response-1',
    'item_id': 'item-1',
    'content_index': 0,
    'delta': text,
  });
  @override
  Stream<Object?> get incoming => _incoming.stream;
  @override
  Future<void> send(String text) async {
    if ((jsonDecode(text) as Map)['type'] == 'session.update') {
      add({
        'type': 'session.updated',
        'session': {'id': 'session-1'},
      });
    }
  }

  @override
  Future<void> close([int? code, String? reason]) => _incoming.close();
}
