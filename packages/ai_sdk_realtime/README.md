# ai_sdk_realtime

Typed OpenAI Realtime WebSocket session support for AI SDK Dart.

The package owns the GA `session.update`, audio buffer, response cancellation,
tool result, transcript, and response usage wire shapes. Unknown server event
types are retained as `RealtimeUnknownEvent` so newer protocol events can be
handled by the application without being discarded.

## Preview usage

```dart
import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';

final session = await RealtimeSession.connect(
  apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
  config: const RealtimeSessionConfig(
    turnDetection: RealtimeServerVad(createResponse: true),
  ),
);
final subscription = session.events.listen(print);
await session.sendText('Say hello briefly.');
await session.createResponse();
await subscription.cancel();
await session.close();
```

Run the checked-in preview with:

```sh
dart run --define=OPENAI_API_KEY=... example/realtime_preview.dart
```

The default authenticated connector uses `dart:io`. Browser applications must
provide a browser-safe `RealtimeTransportConnector` and a short-lived or
ephemeral credential flow. The package does not capture microphone input,
decode or play audio, request permissions, or select an audio route; those
responsibilities stay with the host application.

The deterministic transport and loopback tests cover wire shape, queue bounds,
startup, cancellation, and cleanup. Live OpenAI service behavior and physical
or simulator audio devices require separate qualification.
