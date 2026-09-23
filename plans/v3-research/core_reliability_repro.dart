import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class ErrorStreamModel extends LanguageModelV4 {
  @override
  String get provider => 'repro';

  @override
  String get modelId => 'error-stream';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final controller = StreamController<LanguageModelV4StreamPart>();
    scheduleMicrotask(() => controller.addError(StateError('transport boom')));
    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

class ShortEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  int? get maxEmbeddingsPerCall => null;

  @override
  bool get supportsParallelCalls => true;

  @override
  String get provider => 'repro';

  @override
  String get modelId => 'short-embedding';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    return EmbeddingModelV2GenerateResult(
      embeddings: [
        EmbeddingModelV2Embedding(value: options.values.first, embedding: [1]),
      ],
    );
  }
}

class InvalidToolInputModel extends LanguageModelV4 {
  var calls = 0;

  @override
  String get provider => 'repro';

  @override
  String get modelId => 'invalid-tool-input';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    calls++;
    if (calls == 1) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'call-1',
            toolName: 'weather',
            input: {'unexpected': 1},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'done')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();
}

class PlainModel extends LanguageModelV4 {
  @override
  String get provider => 'repro';

  @override
  String get modelId => 'plain';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => const LanguageModelV4GenerateResult(
    content: [LanguageModelV4TextPart(text: 'new response')],
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();
}

Future<void> main() async => runZonedGuarded(() async {
  print('start');
  final schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );
  final objectResult = await streamObject(
    model: ErrorStreamModel(),
    schema: schema,
    prompt: 'repro',
  );
  print('streamObject returned');
  objectResult.rawStream.listen((_) {}, onError: (_, __) {});
  try {
    await objectResult.object.timeout(const Duration(milliseconds: 100));
    print('streamObject object: completed');
  } on TimeoutException {
    print('streamObject object: TIMEOUT (source error did not settle object)');
  } on Object catch (error) {
    print('streamObject object: $error');
  }

  final batch = await embedMany(
    model: ShortEmbeddingModel(),
    values: const ['a', 'b'],
  );
  print('embedMany values=2 returned=${batch.embeddings.length}');

  final invalidInputModel = InvalidToolInputModel();
  final invalidInputResult = await generateText(
    model: invalidInputModel,
    prompt: 'weather',
    maxSteps: 2,
    tools: {
      'weather': tool<Map<String, dynamic>, String>(
        inputSchema: Schema(
          jsonSchema: const {
            'type': 'object',
            'required': ['city'],
            'properties': {'city': {'type': 'string'}},
          },
          fromJson: (json) => json,
        ),
        execute: (input, _) async => 'accepted: $input',
      ),
    },
  );
  final stepResults = invalidInputResult.steps
      .expand((step) => step.toolResults)
      .map((result) => result.output is ToolResultOutputText
          ? (result.output as ToolResultOutputText).text
          : result.output)
      .toList();
  print('schema-invalid input step tool results: $stepResults, text=${invalidInputResult.text}');

  final historyResult = await generateText(
    model: PlainModel(),
    messages: const [
      ModelMessage(
        role: ModelMessageRole.assistant,
        content: 'old assistant response',
      ),
    ],
    prompt: 'new prompt',
  );
  print('responseMessages after assistant history: ${historyResult.responseMessages.length}');
}, (error, _) => print('unhandled source error: $error'));
