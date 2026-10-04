import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';

Future<void> main() async {
  const apiKey = String.fromEnvironment('OPENAI_API_KEY');
  if (apiKey.isEmpty) {
    throw StateError(
      'Pass an API key with --define=OPENAI_API_KEY=... to run the preview.',
    );
  }

  final session = await RealtimeSession.connect(
    apiKey: apiKey,
    config: const RealtimeSessionConfig(
      outputModalities: ['text'],
      turnDetection: RealtimeServerVad(createResponse: true),
    ),
  );
  final subscription = session.events.listen((event) {
    switch (event) {
      case RealtimeTextDelta(:final delta):
        print(delta);
      case RealtimeTranscriptCompleted(:final transcript):
        print('transcript: $transcript');
      case RealtimeResponseDone(:final usage):
        if (usage != null) print('tokens: ${usage.totalTokens ?? '?'}');
      case RealtimeProviderError(:final message):
        print('provider error: $message');
      default:
        break;
    }
  });

  try {
    await session.sendText('Say hello briefly.');
    await session.createResponse();
    await Future<void>.delayed(const Duration(seconds: 3));
  } finally {
    await subscription.cancel();
    await session.close();
  }
}
