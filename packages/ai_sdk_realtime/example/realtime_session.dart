import 'dart:typed_data';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';

Future<void> main() async {
  final session = await RealtimeSession.connect(
    apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
    config: const RealtimeSessionConfig(outputModalities: ['audio', 'text']),
  );
  final subscription = session.events.listen((event) {
    if (event case RealtimeAudioDelta(:final audio)) {
      // Forward audio to a host playback device. Device routing is host-owned.
      print('received ${audio.length} bytes');
    }
  });
  await session.sendText('Say hello briefly.');
  await session.createResponse();
  await session.sendAudio(Uint8List(0));
  await subscription.cancel();
  await session.close();
}
