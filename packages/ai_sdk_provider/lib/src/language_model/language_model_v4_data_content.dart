import 'dart:convert';
import 'dart:typed_data';

/// Binary data content that can be sent to a model.
///
/// Can be raw bytes, a base64 string, or a URL.
sealed class LanguageModelV4DataContent {
  const LanguageModelV4DataContent();
}

/// Raw binary data.
class DataContentBytes extends LanguageModelV4DataContent {
  const DataContentBytes(this.bytes);

  final Uint8List bytes;
}

/// Base64-encoded string data.
class DataContentBase64 extends LanguageModelV4DataContent {
  const DataContentBase64(this.base64);

  final String base64;
}

/// A URL pointing to the data.
class DataContentUrl extends LanguageModelV4DataContent {
  const DataContentUrl(this.url);

  final Uri url;
}

/// An opaque file or asset reference owned by a provider.
///
/// References are namespaced so an adapter cannot accidentally send an ID
/// issued by another provider as a URL or local byte payload.
class DataContentProviderReference extends LanguageModelV4DataContent {
  const DataContentProviderReference({
    required this.namespace,
    required this.id,
  });

  final String namespace;
  final String id;
}

/// Base64-encodes [data], or `null` for [DataContentUrl] (which has no bytes
/// to encode locally).
String? dataContentToBase64(LanguageModelV4DataContent data) {
  return switch (data) {
    DataContentBytes(:final bytes) => base64Encode(bytes),
    DataContentBase64(:final base64) => base64,
    DataContentUrl() => null,
    DataContentProviderReference(:final namespace, :final id) =>
      throw UnsupportedError(
        'Provider reference $namespace:$id requires a provider-specific serializer',
      ),
  };
}
