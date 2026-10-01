import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';

/// Uploads a file, uses its opaque provider reference, and explicitly deletes it.
///
/// The provider owns the HTTP client. Always dispose it when the lifecycle is
/// complete; file deletion is an explicit server operation.
Future<void> runFilesLifecycle() async {
  final provider = OpenAIProvider(
    apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
  );
  try {
    final files = provider.files();
    final metadata = await files.upload(
      OpenAIFileUpload(
        filename: 'notes.txt',
        purpose: 'assistants',
        bytes: Uint8List.fromList('hello'.codeUnits),
        mediaType: 'text/plain',
      ),
    );
    try {
      final content = await files.download(metadata.id);
      await content.drain<void>();
    } finally {
      await files.delete(metadata.id);
    }
  } finally {
    provider.dispose();
  }
}

Future<void> main() => runFilesLifecycle();
