/// API keys injected at build time via --dart-define.
///
/// Pass keys when running or building:
///
///   fvm flutter run --dart-define=OPENAI_API_KEY=sk-... \
///     --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
///     --dart-define=GOOGLE_API_KEY=...
///
/// For production apps, consider flutter_dotenv or flutter_secure_storage
/// to avoid baking keys into the binary.
const String openAiApiKey = String.fromEnvironment('OPENAI_API_KEY');
const String anthropicApiKey = String.fromEnvironment('ANTHROPIC_API_KEY');
const String googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
