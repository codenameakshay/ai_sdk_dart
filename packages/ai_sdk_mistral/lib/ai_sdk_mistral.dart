/// Mistral AI provider for the AI SDK Dart.
///
/// Supports language model generation and embeddings.
///
/// ```dart
/// import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
///
/// final model = mistral('mistral-large-latest');
/// final embedder = mistral.embedding('mistral-embed');
/// ```
library ai_sdk_mistral;

export 'src/mistral_provider.dart';
