/// Ollama provider for the AI SDK Dart.
///
/// Supports local language model generation and embeddings via a running
/// Ollama instance.
///
/// ```dart
/// import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
///
/// final model = ollama('llama3');
/// final embedder = ollama.embedding('nomic-embed-text');
/// ```
library ai_sdk_ollama;

export 'src/ollama_provider.dart';
