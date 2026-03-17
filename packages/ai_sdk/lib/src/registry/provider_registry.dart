import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A registry mapping `'provider:modelId'` strings to model factories.
///
/// Modeled after the JS SDK's `createProviderRegistry()`.
///
/// ```dart
/// final registry = createProviderRegistry({
///   'openai': openai,
///   'anthropic': anthropic,
/// });
///
/// final model = registry.languageModel('openai:gpt-4o');
/// ```
class ProviderRegistry {
  ProviderRegistry._(this._providers);

  final Map<String, _ProviderLike> _providers;

  /// Resolve a language model by `'provider:modelId'`.
  LanguageModelV3 languageModel(String id) {
    final (provider, modelId) = _splitId(id);
    final p = _providers[provider];
    if (p == null) {
      throw ArgumentError(
        'No provider registered for "$provider". '
        'Available: ${_providers.keys.join(', ')}',
      );
    }
    return p.languageModel(modelId);
  }

  /// Resolve an embedding model by `'provider:modelId'`.
  EmbeddingModelV2<String> textEmbeddingModel(String id) {
    final (provider, modelId) = _splitId(id);
    final p = _providers[provider];
    if (p == null) {
      throw ArgumentError(
        'No provider registered for "$provider". '
        'Available: ${_providers.keys.join(', ')}',
      );
    }
    return p.textEmbeddingModel(modelId);
  }

  (String, String) _splitId(String id) {
    final idx = id.indexOf(':');
    if (idx < 0) {
      throw ArgumentError(
        'Provider registry id must be in the form "provider:modelId", got "$id".',
      );
    }
    return (id.substring(0, idx), id.substring(idx + 1));
  }
}

/// Interface that provider facades must satisfy to be registered.
abstract interface class _ProviderLike {
  LanguageModelV3 languageModel(String modelId);
  EmbeddingModelV2<String> textEmbeddingModel(String modelId);
}

/// Adapter that wraps a callable provider (e.g. a function/class with a
/// `call` method for language models and an `embedding` method).
class _CallableProvider implements _ProviderLike {
  const _CallableProvider({
    required this.languageModelFactory,
    required this.embeddingModelFactory,
  });

  final LanguageModelV3 Function(String modelId) languageModelFactory;
  final EmbeddingModelV2<String> Function(String modelId) embeddingModelFactory;

  @override
  LanguageModelV3 languageModel(String modelId) =>
      languageModelFactory(modelId);

  @override
  EmbeddingModelV2<String> textEmbeddingModel(String modelId) =>
      embeddingModelFactory(modelId);
}

/// Creates a [ProviderRegistry] from a map of provider name → provider object.
///
/// Each value must be an object with:
/// - A `call(modelId)` method returning [LanguageModelV3]
/// - An `embedding(modelId)` method returning [EmbeddingModelV2<String>]
///
/// If a provider doesn't support a model type, the factory may throw.
///
/// Example:
/// ```dart
/// final registry = createProviderRegistry({
///   'openai': openai,
///   'anthropic': anthropic,
/// });
/// final model = registry.languageModel('openai:gpt-4o');
/// ```
ProviderRegistry createProviderRegistry(
  Map<String, RegistrableProvider> providers,
) {
  return ProviderRegistry._(
    providers.map(
      (name, provider) => MapEntry(
        name,
        _CallableProvider(
          languageModelFactory: provider.languageModelFactory,
          embeddingModelFactory: provider.embeddingModelFactory,
        ),
      ),
    ),
  );
}

/// A provider that can be registered in a [ProviderRegistry].
class RegistrableProvider {
  const RegistrableProvider({
    required this.languageModelFactory,
    required this.embeddingModelFactory,
  });

  final LanguageModelV3 Function(String modelId) languageModelFactory;
  final EmbeddingModelV2<String> Function(String modelId) embeddingModelFactory;
}
