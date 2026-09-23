import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

class _VariantModel extends LanguageModelV4 {
  @override
  String get provider => 'fixture';

  @override
  String get modelId => 'variants';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4GenerateResult(
    content: [
      const LanguageModelV4TextPart(text: 'done'),
      const LanguageModelV4ReasoningFilePart(
        data: DataContentBase64('cmVhc29u'),
        mediaType: 'text/plain',
      ),
      const LanguageModelV4DocumentSourcePart(
        id: 'document-1',
        mediaType: 'application/pdf',
        title: 'Document',
      ),
      const LanguageModelV4ToolResultPart(
        toolCallId: 'call-json',
        toolName: 'json',
        output: ToolResultOutputJson({'ok': true}),
      ),
      const LanguageModelV4ToolResultPart(
        toolCallId: 'call-denied',
        toolName: 'denied',
        output: ToolResultOutputExecutionDenied('blocked', 'approval-1'),
      ),
    ],
    finishReason: LanguageModelV4FinishReason.stop,
  );

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final parts = <LanguageModelV4StreamPart>[
      const StreamPartStreamStart(),
      const StreamPartTextStart(id: 'text'),
      const StreamPartTextDelta(id: 'text', delta: 'done'),
      const StreamPartTextEnd(id: 'text'),
      const StreamPartReasoningFile(
        file: LanguageModelV4ReasoningFilePart(
          data: DataContentBase64('cmVhc29u'),
          mediaType: 'text/plain',
        ),
      ),
      const StreamPartDocumentSource(
        source: LanguageModelV4DocumentSourcePart(
          id: 'document-1',
          mediaType: 'application/pdf',
          title: 'Document',
        ),
      ),
      const StreamPartToolResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: 'call-json',
          toolName: 'json',
          output: ToolResultOutputErrorJson({'message': 'bad'}),
        ),
      ),
      const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ];
    return LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
  }
}

void main() {
  test(
    'generateText preserves direct provider variants and infers errors',
    () async {
      final result = await generateText(model: _VariantModel(), prompt: 'go');

      expect(result.documentSources.single.id, 'document-1');
      expect(result.reasoningFiles.single.mediaType, 'text/plain');
      final jsonResult = result.toolResults.first;
      expect(jsonResult.output, isA<ToolResultOutputJson>());
      expect(jsonResult.isError, isFalse);
      final deniedResult = result.toolResults.last;
      expect(deniedResult.output, isA<ToolResultOutputExecutionDenied>());
      expect(deniedResult.isError, isTrue);
    },
  );

  test(
    'streamText emits direct variants and preserves structured errors',
    () async {
      final result = await streamText(model: _VariantModel(), prompt: 'go');
      final events = await result.fullStream.toList();

      expect(events.whereType<StreamTextDocumentSourceEvent>(), hasLength(1));
      expect(events.whereType<StreamTextReasoningFileEvent>(), hasLength(1));
      final toolEvent = events.whereType<StreamTextToolResultEvent>().single;
      expect(toolEvent.toolResult.output, isA<ToolResultOutputErrorJson>());
      expect(toolEvent.toolResult.isError, isTrue);
      expect((await result.documentSources).single.id, 'document-1');
      expect((await result.reasoningFiles).single.mediaType, 'text/plain');
    },
  );
}
