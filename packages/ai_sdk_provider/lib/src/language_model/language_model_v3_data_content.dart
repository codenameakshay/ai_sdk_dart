import 'dart:typed_data';

/// Binary data content that can be sent to a model.
///
/// Can be raw bytes, a base64 string, or a URL.
sealed class LanguageModelV3DataContent {
  const LanguageModelV3DataContent();
}

/// Raw binary data.
class DataContentBytes extends LanguageModelV3DataContent {
  const DataContentBytes(this.bytes);

  final Uint8List bytes;
}

/// Base64-encoded string data.
class DataContentBase64 extends LanguageModelV3DataContent {
  const DataContentBase64(this.base64);

  final String base64;
}

/// A URL pointing to the data.
class DataContentUrl extends LanguageModelV3DataContent {
  const DataContentUrl(this.url);

  final Uri url;
}
