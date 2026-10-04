import 'package:ai_sdk_openai/ai_sdk_openai.dart';

/// Creates an experimental Responses batch and reads its result file when it
/// is available. Polling remains the caller's responsibility.
Future<void> runBatchLifecycle() async {
  final provider = OpenAIProvider(
    apiKey: const String.fromEnvironment('OPENAI_API_KEY'),
  );
  try {
    final batches = provider.batches();
    final batch = await batches.create(const [
      OpenAIBatchInput(
        customId: 'example-1',
        model: 'gpt-4.1-mini',
        input: 'Say hello from the batch example.',
      ),
    ]);
    final current = await batches.get(batch.id);
    final terminal =
        current.status == OpenAIBatchStatus.completed ||
        current.status == OpenAIBatchStatus.expired ||
        current.status == OpenAIBatchStatus.cancelled;
    if (terminal) {
      for (final file in [current.outputFileId, current.errorFileId]) {
        if (file == null) continue;
        final stream = await provider.files().download(file);
        await for (final result in decodeOpenAIBatchResults(stream)) {
          print('${result.customId}: ${result.statusCode}');
        }
      }
    }
  } finally {
    provider.dispose();
  }
}

Future<void> main() => runBatchLifecycle();
