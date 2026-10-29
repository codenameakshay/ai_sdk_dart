import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Text that extractReasoningMiddleware buffers and flushes later must keep
/// the upstream text part id, so it reaches the final `text` and `content`
/// and not only `textStream`.
void main() {
  Future<StreamTextResult<String>> stream(
    List<LanguageModelV4StreamPart> parts,
  ) {
    return streamText(
      model: wrapLanguageModel(
        model: FakeStreamModel(parts),
        middleware: extractReasoningMiddleware(tagName: 'think'),
      ),
      prompt: 'go',
    );
  }

  const thinkThenAnswer = [
    StreamPartTextStart(id: 't1'),
    StreamPartTextDelta(id: 't1', delta: '<think>'),
    StreamPartTextDelta(id: 't1', delta: 'plan'),
    StreamPartTextDelta(id: 't1', delta: '</think>'),
    StreamPartTextDelta(id: 't1', delta: 'Done.'),
  ];

  test('text flushed before text-end reaches text and content', () async {
    final result = await stream([
      ...thinkThenAnswer,
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);

    expect((await result.textStream.toList()).join(), 'Done.');
    expect(await result.text, 'Done.');
    expect(await result.reasoningText, 'plan');
    final content = await result.content;
    expect(content.whereType<LanguageModelV4TextPart>().map((p) => p.text), [
      'Done.',
    ]);
  });

  test('text flushed before another non-text part keeps its id', () async {
    const source = LanguageModelV4SourcePart(
      id: 's1',
      url: 'https://example.com',
    );
    final result = await stream([
      ...thinkThenAnswer,
      const StreamPartSource(source: source),
      const StreamPartTextDelta(id: 't1', delta: ' Bye.'),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);

    final textIds = <String>{};
    await for (final event in result.fullStream) {
      if (event is StreamTextTextDeltaEvent) textIds.add(event.id);
    }
    expect(textIds, {'t1'});
    expect(await result.text, 'Done. Bye.');
    expect(
      (await result.content).whereType<LanguageModelV4TextPart>().map(
        (p) => p.text,
      ),
      ['Done. Bye.'],
    );
  });

  test('text flushed at end of stream closes the open text part', () async {
    final result = await stream(thinkThenAnswer);

    expect((await result.textStream.toList()).join(), 'Done.');
    expect(await result.text, 'Done.');
    expect(await result.reasoningText, 'plan');
    expect(
      (await result.content).whereType<LanguageModelV4TextPart>().map(
        (p) => p.text,
      ),
      ['Done.'],
    );
  });

  Future<List<LanguageModelV4StreamPart>> transform(
    List<LanguageModelV4StreamPart> parts,
  ) async {
    final wrapped = wrapLanguageModel(
      model: FakeStreamModel(parts),
      middleware: extractReasoningMiddleware(tagName: 'think'),
    );
    final transformed = await wrapped.doStream(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    return transformed.stream.toList();
  }

  test('an open text part is closed before finish', () async {
    final parts = await transform([
      ...thinkThenAnswer,
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);

    expect(parts.whereType<StreamPartTextEnd>().map((p) => p.id), ['t1']);
    final endIndex = parts.indexWhere((p) => p is StreamPartTextEnd);
    expect(endIndex, parts.indexWhere((p) => p is StreamPartFinish) - 1);
    expect(parts.last, isA<StreamPartFinish>());

    final result = await stream([
      ...thinkThenAnswer,
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);
    expect(await result.text, 'Done.');
  });

  test('each text part keeps its own id', () async {
    final result = await stream([
      ...thinkThenAnswer,
      const StreamPartTextEnd(id: 't1'),
      const StreamPartTextStart(id: 't2'),
      const StreamPartTextDelta(id: 't2', delta: 'Bye.'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]);

    final deltaIds = <String, String>{};
    await for (final event in result.fullStream) {
      if (event is StreamTextTextDeltaEvent) {
        deltaIds.update(
          event.id,
          (text) => text + event.delta,
          ifAbsent: () => event.delta,
        );
      }
    }
    expect(deltaIds, {'t1': 'Done.', 't2': 'Bye.'});
    expect(await result.text, 'Done.Bye.');
    expect(
      (await result.content).whereType<LanguageModelV4TextPart>().map(
        (p) => p.text,
      ),
      ['Done.', 'Bye.'],
    );
  });

  test('a closed text part is not closed again at end of stream', () async {
    final parts = await transform([
      ...thinkThenAnswer,
      const StreamPartTextEnd(id: 't1'),
    ]);

    expect(parts.whereType<StreamPartTextEnd>().map((p) => p.id), ['t1']);
    expect(parts.whereType<StreamPartTextDelta>().map((p) => p.id), ['t1']);
  });
}
