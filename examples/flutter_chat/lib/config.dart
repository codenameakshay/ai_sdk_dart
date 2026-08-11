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
