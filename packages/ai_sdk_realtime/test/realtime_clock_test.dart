import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('startup budget begins at the current clock reading', () async {
    final transport = _Transport();
    transport.add('session.created');
    final session = await RealtimeSession.connect(
      apiKey: 'fixture',
      clock: _Clock(),
      connector: (_, _) async => transport,
    );
    expect(session.state, RealtimeConnectionState.ready);
    await session.close();
  });
}

class _Clock implements RealtimeClock {
  @override
  Duration get elapsed => const Duration(hours: 1);
  @override
  Timer schedule(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

class _Transport implements RealtimeTransport {
  final _incoming = StreamController<Object?>();
  void add(String type) => _incoming.add(
    jsonEncode({
      'type': type,
      'session': {'id': 'session-1'},
    }),
  );
  @override
  Stream<Object?> get incoming => _incoming.stream;
  @override
  Future<void> send(String text) async => add('session.updated');
  @override
  Future<void> close([int? code, String? reason]) => _incoming.close();
}
