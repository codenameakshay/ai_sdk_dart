import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class ReasoningBuffer {
  final _text = StringBuffer();
  ProviderMetadata? _metadata;

  void mergeMetadata(ProviderMetadata? metadata) {
    if (metadata == null) return;
    _metadata ??= {};
    for (final entry in metadata.entries) {
      _metadata![entry.key] = {...?_metadata![entry.key], ...entry.value};
    }
  }

  void write(String delta, ProviderMetadata? metadata) {
    _text.write(delta);
    mergeMetadata(metadata);
  }

  LanguageModelV4ReasoningPart finish({
    ProviderMetadata? metadata,
    String? signature,
  }) {
    mergeMetadata(metadata);
    return LanguageModelV4ReasoningPart(
      text: _text.toString(),
      signature: signature,
      providerOptions: _metadata,
    );
  }
}
