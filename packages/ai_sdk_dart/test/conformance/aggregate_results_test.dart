import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  const source1 = LanguageModelV4SourcePart(id: 's1', url: 'https://one.test');
  const source2 = LanguageModelV4SourcePart(id: 's2', url: 'https://two.test');
  final file = LanguageModelV4FilePart(
    data: DataContentUrl(Uri.parse('https://files.test/a.txt')),
    mediaType: 'text/plain',
    filename: 'a.txt',
  );
  const known = LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(total: 2),
    outputTokens: LanguageModelV4OutputTokenUsage(total: 3),
  );
  const document = LanguageModelV4DocumentSourcePart(
    id: 'doc-1',
    mediaType: 'application/pdf',
    title: 'Reference',
    filename: 'reference.pdf',
  );
  const reasoningFile = LanguageModelV4ReasoningFilePart(
    data: DataContentBase64('cmVhc29uaW5n'),
    mediaType: 'text/plain',
  );

  LanguageModelV4GenerateResult firstStep() => LanguageModelV4GenerateResult(
    content: [
      LanguageModelV4TextPart(text: 'intermediate'),
      LanguageModelV4ReasoningPart(text: 'first thought', signature: 'sig-1'),
      LanguageModelV4ToolCallPart(
        toolCallId: 'call-1',
        toolName: 'lookup',
        input: {},
      ),
      source1,
      file,
      document,
      reasoningFile,
    ],
    finishReason: LanguageModelV4FinishReason.toolCalls,
    usage: known,
    warnings: [LanguageModelV4OtherWarning(message: 'step-one-warning')],
  );

  LanguageModelV4GenerateResult finalStep() =>
      const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4TextPart(text: 'final'),
          LanguageModelV4ReasoningPart(
            text: 'second thought',
            signature: 'sig-2',
          ),
          source2,
        ],
        finishReason: LanguageModelV4FinishReason.stop,
        usage: LanguageModelV4Usage(raw: {'provider': 'unknown'}),
        request: LanguageModelV4RequestMetadata(body: {'step': 2}),
        response: LanguageModelV4ResponseMetadata(id: 'response-final'),
      );

  test(
    'generateText aggregates multi-step content while preserving final text and step',
    () async {
      final result = await generateText(
        model: FakeMultiStepModel([firstStep(), finalStep()]),
        prompt: 'go',
        maxSteps: 2,
        bodyInclusion: const BodyInclusionPolicy.all(),
        tools: {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'ok',
          ),
        },
      );
      expect(result.text, 'final');
      expect(result.finalStep.text, 'final');
      expect(result.steps.first.responseMessages, hasLength(2));
      expect(result.finalStep.responseMessages, hasLength(1));
      expect(result.finalStep.responseMetadata?.id, 'response-final');
      expect(result.finalStep.request?.body, {'step': 2});
      expect(
        result.content.whereType<LanguageModelV4TextPart>().map((p) => p.text),
        ['intermediate', 'final'],
      );
      expect(result.sources.map((s) => s.id), ['s1', 's2']);
      expect(result.files, hasLength(1));
      expect(result.documentSources.single.id, 'doc-1');
      expect(result.reasoningFiles.single.mediaType, 'text/plain');
      expect(result.reasoning.map((part) => part.text), ['second thought']);
      expect(result.reasoningText, 'second thought');
      expect(result.toolCalls, hasLength(1));
      expect(result.warnings, hasLength(1));
      expect(result.usage?.inputTokens.total, 2);
      expect(result.usage?.outputTokens.total, 3);
      expect(result.totalUsage, same(result.usage));
    },
  );

  test('streamText exposes aggregated futures and finalStep', () async {
    final result = await streamText(
      model: FakeMultiStepModel([firstStep(), finalStep()]),
      prompt: 'go',
      maxSteps: 2,
      bodyInclusion: const BodyInclusionPolicy.all(),
      tools: {
        'lookup': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (_, _) async => 'ok',
        ),
      },
    );
    final eventsFuture = result.fullStream.toList();
    await result.text;
    expect((await result.finalStep).text, 'final');
    expect((await result.steps).first.responseMessages, hasLength(2));
    expect((await result.finalStep).responseMessages, hasLength(1));
    expect((await result.finalStep).responseMetadata?.id, 'response-final');
    expect((await result.finalStep).request?.body, {'step': 2});
    expect(
      (await result.content).whereType<LanguageModelV4TextPart>().map(
        (p) => p.text,
      ),
      ['intermediate', 'final'],
    );
    expect((await result.sources).map((s) => s.id), ['s1', 's2']);
    expect(await result.files, hasLength(1));
    expect((await result.documentSources).single.id, 'doc-1');
    expect((await result.reasoningFiles).single.mediaType, 'text/plain');
    expect((await result.reasoning).map((part) => part.text), [
      'second thought',
    ]);
    expect(await result.reasoningText, 'second thought');
    expect(await result.toolCalls, hasLength(1));
    expect(await result.warnings, hasLength(1));
    expect((await result.usage)?.inputTokens.total, 2);
    expect((await result.totalUsage)?.outputTokens.total, 3);
    final events = await eventsFuture;
    final finish = events.whereType<StreamTextFinishEvent>().single;
    expect(finish.finalStep.text, 'final');
    expect(finish.sources, hasLength(2));
    expect(finish.documentSources, hasLength(1));
    expect(finish.reasoningFiles, hasLength(1));
    expect(finish.reasoning.map((part) => part.text), ['second thought']);
    expect(events.whereType<StreamTextDocumentSourceEvent>(), hasLength(1));
    expect(events.whereType<StreamTextReasoningFileEvent>(), hasLength(1));
    expect(
      events.whereType<StreamTextReasoningDeltaEvent>().map((e) => e.delta),
      ['first thought', 'second thought'],
    );
    expect(finish.usage?.inputTokens.total, 2);
    expect(finish.usage?.outputTokens.total, 3);
  });
}
