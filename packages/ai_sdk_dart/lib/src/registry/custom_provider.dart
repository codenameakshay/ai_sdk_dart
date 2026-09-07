import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A provider built from explicit factory functions and an optional fallback.
///
/// Mirrors `customProvider()` from the JS AI SDK v6. Use when you need to
/// define a provider on-the-fly from lambdas or to add a fallback chain.
///
/// ```dart
/// final provider = customProvider(
///   languageModels: {
///     'fast': myFastModel,
///     'slow': mySlowModel,
///   },
///   embeddingModels: {
///     'embed': myEmbeddingModel,
///   },
///   fallbackLanguageModel: (modelId) => myFallbackModel(modelId),
/// );
///
/// final model = provider.languageModel('fast');
/// final embed = provider.textEmbeddingModel('embed');
/// final fallback = provider.languageModel('remote-model');
/// ```
class CustomProvider {
  const CustomProvider._({
    required Map<String, LanguageModelV4> languageModels,
    required Map<String, EmbeddingModelV2<String>> embeddingModels,
    required Map<String, ImageModelV3> imageModels,
    required Map<String, SpeechModelV1> speechModels,
    required Map<String, TranscriptionModelV1> transcriptionModels,
    required LanguageModelV4 Function(String)? fallbackLanguageModel,
    required EmbeddingModelV2<String> Function(String)? fallbackEmbeddingModel,
    required ImageModelV3 Function(String)? fallbackImageModel,
    required SpeechModelV1 Function(String)? fallbackSpeechModel,
    required TranscriptionModelV1 Function(String)? fallbackTranscriptionModel,
  }) : _languageModels = languageModels,
       _embeddingModels = embeddingModels,
       _imageModels = imageModels,
       _speechModels = speechModels,
       _transcriptionModels = transcriptionModels,
       _fallbackLanguageModel = fallbackLanguageModel,
       _fallbackEmbeddingModel = fallbackEmbeddingModel,
       _fallbackImageModel = fallbackImageModel,
       _fallbackSpeechModel = fallbackSpeechModel,
       _fallbackTranscriptionModel = fallbackTranscriptionModel;

  final Map<String, LanguageModelV4> _languageModels;
  final Map<String, EmbeddingModelV2<String>> _embeddingModels;
  final Map<String, ImageModelV3> _imageModels;
  final Map<String, SpeechModelV1> _speechModels;
  final Map<String, TranscriptionModelV1> _transcriptionModels;
  final LanguageModelV4 Function(String)? _fallbackLanguageModel;
  final EmbeddingModelV2<String> Function(String)? _fallbackEmbeddingModel;
  final ImageModelV3 Function(String)? _fallbackImageModel;
  final SpeechModelV1 Function(String)? _fallbackSpeechModel;
  final TranscriptionModelV1 Function(String)? _fallbackTranscriptionModel;

  /// Resolve a language model by [modelId].
  ///
  /// If not found in this provider's map, delegates to the fallback.
  /// Throws [ArgumentError] when neither map nor fallback knows the id.
  LanguageModelV4 languageModel(String modelId) {
    final model = _languageModels[modelId];
    if (model != null) return model;
    if (_fallbackLanguageModel != null) return _fallbackLanguageModel(modelId);
    throw ArgumentError(
      'No language model registered for "$modelId". '
      'Available: ${_languageModels.keys.join(', ')}',
    );
  }

  /// Resolve an embedding model by [modelId].
  EmbeddingModelV2<String> textEmbeddingModel(String modelId) {
    final model = _embeddingModels[modelId];
    if (model != null) return model;
    if (_fallbackEmbeddingModel != null) {
      return _fallbackEmbeddingModel(modelId);
    }
    throw ArgumentError(
      'No embedding model registered for "$modelId". '
      'Available: ${_embeddingModels.keys.join(', ')}',
    );
  }

  /// Resolve an image model by [modelId].
  ImageModelV3 imageModel(String modelId) {
    final model = _imageModels[modelId];
    if (model != null) return model;
    if (_fallbackImageModel != null) return _fallbackImageModel(modelId);
    throw ArgumentError(
      'No image model registered for "$modelId". '
      'Available: ${_imageModels.keys.join(', ')}',
    );
  }

  /// Resolve a speech model by [modelId].
  SpeechModelV1 speechModel(String modelId) {
    final model = _speechModels[modelId];
    if (model != null) return model;
    if (_fallbackSpeechModel != null) return _fallbackSpeechModel(modelId);
    throw ArgumentError(
      'No speech model registered for "$modelId". '
      'Available: ${_speechModels.keys.join(', ')}',
    );
  }

  /// Resolve a transcription model by [modelId].
  TranscriptionModelV1 transcriptionModel(String modelId) {
    final model = _transcriptionModels[modelId];
    if (model != null) return model;
    if (_fallbackTranscriptionModel != null) {
      return _fallbackTranscriptionModel(modelId);
    }
    throw ArgumentError(
      'No transcription model registered for "$modelId". '
      'Available: ${_transcriptionModels.keys.join(', ')}',
    );
  }
}

/// Creates a [CustomProvider] from explicit model maps and an optional fallback.
///
/// Mirrors `customProvider()` from the JS AI SDK v6.
///
/// Parameters:
/// - [languageModels] — map of model ID → [LanguageModelV4] instance.
/// - [embeddingModels] — map of model ID → [EmbeddingModelV2] instance.
/// - [imageModels] — map of model ID → [ImageModelV3] instance.
/// - [speechModels] — map of model ID → [SpeechModelV1] instance.
/// - [transcriptionModels] — map of model ID → [TranscriptionModelV1] instance.
/// - [fallbackLanguageModel] — factory to resolve unknown language model IDs.
/// - [fallbackEmbeddingModel] — factory to resolve unknown embedding model IDs.
/// - [fallbackImageModel] — factory to resolve unknown image model IDs.
/// - [fallbackSpeechModel] — factory to resolve unknown speech model IDs.
/// - [fallbackTranscriptionModel] — factory to resolve unknown transcription model IDs.
CustomProvider customProvider({
  Map<String, LanguageModelV4>? languageModels,
  Map<String, EmbeddingModelV2<String>>? embeddingModels,
  Map<String, ImageModelV3>? imageModels,
  Map<String, SpeechModelV1>? speechModels,
  Map<String, TranscriptionModelV1>? transcriptionModels,
  LanguageModelV4 Function(String modelId)? fallbackLanguageModel,
  EmbeddingModelV2<String> Function(String modelId)? fallbackEmbeddingModel,
  ImageModelV3 Function(String modelId)? fallbackImageModel,
  SpeechModelV1 Function(String modelId)? fallbackSpeechModel,
  TranscriptionModelV1 Function(String modelId)? fallbackTranscriptionModel,
}) {
  return CustomProvider._(
    languageModels: languageModels ?? const {},
    embeddingModels: embeddingModels ?? const {},
    imageModels: imageModels ?? const {},
    speechModels: speechModels ?? const {},
    transcriptionModels: transcriptionModels ?? const {},
    fallbackLanguageModel: fallbackLanguageModel,
    fallbackEmbeddingModel: fallbackEmbeddingModel,
    fallbackImageModel: fallbackImageModel,
    fallbackSpeechModel: fallbackSpeechModel,
    fallbackTranscriptionModel: fallbackTranscriptionModel,
  );
}
