/// OpenAI API key injected at build time via --dart-define.
///
/// Pass the key when running or building:
///
///   fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
///   fvm flutter build apk --dart-define=OPENAI_API_KEY=sk-...
///
/// Do not ship a long-lived provider secret this way. For production, prefer a
/// trusted proxy or backend-minted short-lived credentials.
const String openAiApiKey = String.fromEnvironment('OPENAI_API_KEY');

/// URL of the `examples/remote_backend` reference server, injected at build
/// time via --dart-define.
///
///   fvm flutter run --dart-define=REMOTE_BACKEND_URL=http://127.0.0.1:8081/chat
///
/// Defaults to the pinned reference server's loopback address.
const String remoteBackendUrl = String.fromEnvironment(
  'REMOTE_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8081/chat',
);
