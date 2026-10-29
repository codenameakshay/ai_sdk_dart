import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

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

  test('overlapping text ids are closed independently', () async {
    const input = [
      StreamPartTextStart(id: 'a'),
      StreamPartTextDelta(id: 'a', delta: 'A'),
      StreamPartTextStart(id: 'b'),
      StreamPartTextDelta(id: 'b', delta: 'B'),
      StreamPartTextEnd(id: 'b'),
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ];
    final parts = await transform(input);

    expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
      'b',
      'a',
    ]);
    expect(
      parts.whereType<StreamPartTextDelta>().map(
        (part) => '${part.id}:${part.delta}',
      ),
      ['a:A', 'b:B'],
    );

    final result = await stream(input);
    expect(await result.text, 'BA');
    expect(
      (await result.content).whereType<LanguageModelV4TextPart>().map(
        (part) => part.text,
      ),
      ['B', 'A'],
    );
  });

  test('all overlapping text ids are closed at EOF in opening order', () async {
    final parts = await transform([
      const StreamPartTextStart(id: 'a'),
      const StreamPartTextDelta(id: 'a', delta: 'A'),
      const StreamPartTextStart(id: 'b'),
      const StreamPartTextDelta(id: 'b', delta: 'B'),
    ]);

    expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
      'a',
      'b',
    ]);
    expect(
      parts.whereType<StreamPartTextDelta>().map(
        (part) => '${part.id}:${part.delta}',
      ),
      ['a:A', 'b:B'],
    );
  });

  for (final finish in [false, true]) {
    test(
      'an empty started text part closes once ${finish ? 'at finish' : 'at EOF'}',
      () async {
        final parts = await transform([
          const StreamPartTextStart(id: 'empty'),
          if (finish)
            StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
          'empty',
        ]);
      },
    );
  }

  test(
    'explicitly ending an empty text part does not duplicate its end',
    () async {
      final parts = await transform([
        const StreamPartTextStart(id: 'empty'),
        const StreamPartTextEnd(id: 'empty'),
      ]);

      expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
        'empty',
      ]);
    },
  );

  test(
    'a later empty open id is closed instead of the stale delta id',
    () async {
      final parts = await transform([
        const StreamPartTextStart(id: 'a'),
        const StreamPartTextDelta(id: 'a', delta: 'A'),
        const StreamPartTextEnd(id: 'a'),
        const StreamPartTextStart(id: 'b'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]);

      expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
        'a',
        'b',
      ]);
    },
  );

  test(
    'empty streams stay empty and delta-only streams use fallback ids',
    () async {
      expect(await transform([]), isEmpty);
      expect(
        (await transform([
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ])).whereType<StreamPartTextEnd>(),
        isEmpty,
      );

      final parts = await transform([
        const StreamPartTextDelta(id: 'delta-only', delta: 'text'),
      ]);
      expect(
        parts.whereType<StreamPartTextDelta>().map(
          (part) => '${part.id}:${part.delta}',
        ),
        ['delta-only:text'],
      );
      expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
        'delta-only',
      ]);
    },
  );

  test('nested reasoning middleware flushes text ends before finish', () async {
    final inner = wrapLanguageModel(
      model: FakeStreamModel([
        const StreamPartTextStart(id: 'text'),
        const StreamPartTextDelta(id: 'text', delta: '<think>plan</'),
        const StreamPartTextDelta(id: 'text', delta: 'think>answer'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      middleware: extractReasoningMiddleware(tagName: 'think'),
    );
    final wrapped = wrapLanguageModel(
      model: inner,
      middleware: extractReasoningMiddleware(tagName: 'other'),
    );
    final result = await wrapped.doStream(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    final parts = await result.stream.toList();
    final endIndex = parts.indexWhere((part) => part is StreamPartTextEnd);
    final finishIndex = parts.indexWhere((part) => part is StreamPartFinish);
    expect(
      parts.whereType<StreamPartTextDelta>().map(
        (part) => '${part.id}:${part.delta}',
      ),
      ['text:answer'],
    );
    expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
      'text',
    ]);
    expect(endIndex, greaterThanOrEqualTo(0));
    expect(endIndex, lessThan(finishIndex));
    expect(parts.last, isA<StreamPartFinish>());
  });

  for (final finish in [false, true]) {
    test(
      'an open text id closes ${finish ? 'at finish' : 'at EOF'} while reasoning remains open',
      () async {
        final parts = await transform([
          const StreamPartTextStart(id: 'text'),
          const StreamPartTextDelta(id: 'text', delta: '<think>plan'),
          if (finish)
            StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        expect(
          parts.whereType<StreamPartReasoningDelta>().map((part) => part.delta),
          ['plan'],
        );
        expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
          'text',
        ]);
      },
    );
  }

  test(
    'explicit text end is not repeated while reasoning remains open',
    () async {
      final parts = await transform([
        const StreamPartTextStart(id: 'text'),
        const StreamPartTextDelta(id: 'text', delta: '<think>plan'),
        const StreamPartTextEnd(id: 'text'),
      ]);

      expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
        'text',
      ]);
    },
  );
}
