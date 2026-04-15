/// Azure OpenAI provider for the AI SDK Dart.
///
/// Supports language model generation and embeddings via Azure-hosted OpenAI
/// deployments.
///
/// ```dart
/// import 'package:ai_sdk_azure/ai_sdk_azure.dart';
///
/// final provider = AzureOpenAIProvider(
///   endpoint: 'https://my-resource.openai.azure.com',
///   apiKey: 'my-api-key',
/// );
/// final model = provider('my-gpt4-deployment');
/// final embedder = provider.embedding('my-ada-deployment');
/// ```
library ai_sdk_azure;

export 'src/azure_provider.dart';
