import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  Future<List<LanguageModelV4StreamPart>> transform(
    List<LanguageModelV4StreamPart> input,
  ) async {
    final result =
        await wrapLanguageModel(
          model: FakeStreamModel(input),
          middleware: extractReasoningMiddleware(),
        ).doStream(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        );
    return result.stream.toList();
  }

  test('interleaved text ids cannot complete each other\'s tags', () async {
    final parts = await transform(const [
      StreamPartTextStart(id: 'a'),
      StreamPartTextStart(id: 'b'),
      StreamPartTextDelta(id: 'a', delta: '<thi'),
      StreamPartTextDelta(id: 'b', delta: 'nk>B'),
      StreamPartTextDelta(id: 'a', delta: 'nk>A</think>answer'),
      StreamPartTextEnd(id: 'b'),
      StreamPartTextEnd(id: 'a'),
    ]);
    final text = <String, String>{};
    for (final part in parts.whereType<StreamPartTextDelta>()) {
      text.update(
        part.id,
        (value) => value + part.delta,
        ifAbsent: () => part.delta,
      );
    }
    expect(text, {'a': 'answer', 'b': 'nk>B'});
    expect(
      parts.whereType<StreamPartReasoningDelta>().map((p) => p.delta).join(),
      'A',
    );
    expectBalanced(parts);
  });

  test('simultaneous reasoning blocks have independent lifecycles', () async {
    final parts = await transform(const [
      StreamPartTextStart(id: 'a'),
      StreamPartTextStart(id: 'b'),
      StreamPartTextDelta(id: 'a', delta: '<think>alpha'),
      StreamPartTextDelta(id: 'b', delta: '<think>beta'),
      StreamPartTextDelta(id: 'a', delta: '</think>A'),
      StreamPartTextDelta(id: 'b', delta: '</think>B'),
      StreamPartTextEnd(id: 'b'),
      StreamPartTextEnd(id: 'a'),
    ]);
    final reasoning = <String, String>{};
    for (final part in parts.whereType<StreamPartReasoningDelta>()) {
      reasoning.update(
        part.id,
        (value) => value + part.delta,
        ifAbsent: () => part.delta,
      );
    }
    expect(reasoning.values, unorderedEquals(['alpha', 'beta']));
    expectBalanced(parts);
  });

  for (final sideband in <LanguageModelV4StreamPart>[
    const StreamPartRaw(rawValue: {'chunk': 1}),
    const StreamPartSource(
      source: LanguageModelV4SourcePart(id: 's', url: 'https://example.com'),
    ),
  ]) {
    for (var split = 1; split < '<think>plan</think>answer'.length; split++) {
      test('${sideband.runtimeType} preserves tags at split $split', () async {
        const text = '<think>plan</think>answer';
        final input = <LanguageModelV4StreamPart>[
          const StreamPartTextStart(id: 'a'),
          StreamPartTextDelta(id: 'a', delta: text.substring(0, split)),
          sideband,
          StreamPartTextDelta(id: 'a', delta: text.substring(split)),
          const StreamPartTextEnd(id: 'a'),
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ];
        final parts = await transform(input);
        expect(parts, contains(same(sideband)));
        expectBalanced(parts);
        final result = await streamText(
          model: wrapLanguageModel(
            model: FakeStreamModel(input),
            middleware: extractReasoningMiddleware(),
          ),
          prompt: 'go',
          includeRawChunks: true,
        );
        expect((await result.textStream.toList()).join(), 'answer');
        expect(await result.text, 'answer');
        expect(await result.reasoningText, 'plan');
        expect(
          (await result.content)
              .whereType<LanguageModelV4TextPart>()
              .map((p) => p.text)
              .join(),
          'answer',
        );
      });
    }
  }

  for (final middleware in [false, true]) {
    test(
      'interleaved final text agrees with deltas (middleware=$middleware)',
      () async {
        final model = FakeStreamModel(const [
          StreamPartTextStart(id: 'a'),
          StreamPartTextStart(id: 'b'),
          StreamPartTextDelta(id: 'a', delta: 'AAAAAAAAAAAA'),
          StreamPartTextDelta(id: 'b', delta: 'BBBBBBBBBBBB'),
          StreamPartTextDelta(id: 'a', delta: 'CCCCCCCCCCCC'),
          StreamPartTextEnd(id: 'b'),
          StreamPartTextEnd(id: 'a'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);
        final result = await streamText(
          model: middleware
              ? wrapLanguageModel(
                  model: model,
                  middleware: extractReasoningMiddleware(),
                )
              : model,
          prompt: 'go',
        );
        final streamed = (await result.textStream.toList()).join();
        expect(await result.text, streamed);
        expect(
          (await result.content)
              .whereType<LanguageModelV4TextPart>()
              .map((p) => p.text)
              .join(),
          streamed,
        );
        expect((await result.steps).single.text, streamed);
      },
    );
  }

  for (final finish in [false, true]) {
    test(
      'all open reasoning closes before text at ${finish ? 'finish' : 'EOF'}',
      () async {
        final parts = await transform([
          const StreamPartTextDelta(id: 'a', delta: '<think>alpha</thi'),
          const StreamPartTextDelta(id: 'b', delta: '<think>beta'),
          const StreamPartRaw(rawValue: 'diagnostic'),
          if (finish)
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.stop,
            ),
        ]);
        expectBalanced(parts);
        expect(
          parts
              .whereType<StreamPartReasoningDelta>()
              .map((p) => p.delta)
              .join(),
          'alpha</thibeta',
        );
        final lastReasoningEnd = parts.lastIndexWhere(
          (p) => p is StreamPartReasoningEnd,
        );
        final firstTextEnd = parts.indexWhere((p) => p is StreamPartTextEnd);
        expect(lastReasoningEnd, lessThan(firstTextEnd));
        expect(parts.whereType<StreamPartTextEnd>().map((p) => p.id), [
          'a',
          'b',
        ]);
      },
    );
  }

  test('text-end resolves a fragment without leaking to a reused ID', () async {
    final parts = await transform(const [
      StreamPartTextStart(id: 'a'),
      StreamPartTextDelta(id: 'a', delta: '<thi'),
      StreamPartTextEnd(id: 'a'),
      StreamPartTextStart(id: 'a'),
      StreamPartTextDelta(id: 'a', delta: 'nk>literal'),
      StreamPartTextEnd(id: 'a'),
    ]);
    expectBalanced(parts);
    expect(parts.whereType<StreamPartReasoningStart>(), isEmpty);
    expect(
      parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
      '<think>literal',
    );
  });

  test(
    'interleaved content runs retain per-ID start/delta/end metadata',
    () async {
      final result = await streamText(
        model: FakeStreamModel(const [
          StreamPartTextStart(
            id: 'a',
            providerMetadata: {
              'p': {'start': 1},
            },
          ),
          StreamPartTextStart(
            id: 'b',
            providerMetadata: {
              'p': {'other': 2},
            },
          ),
          StreamPartTextDelta(
            id: 'a',
            delta: 'one',
            providerMetadata: {
              'p': {'delta': 3},
            },
          ),
          StreamPartTextDelta(id: 'b', delta: 'two'),
          StreamPartTextDelta(id: 'a', delta: 'three'),
          StreamPartTextEnd(id: 'b'),
          StreamPartTextEnd(
            id: 'a',
            providerMetadata: {
              'p': {'end': 4},
            },
          ),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]),
        prompt: 'go',
      );
      expect((await result.textStream.toList()).join(), 'onetwothree');
      final parts = (await result.content)
          .whereType<LanguageModelV4TextPart>()
          .toList();
      expect(parts.map((p) => p.text), ['one', 'two', 'three']);
      expect(parts[0].providerOptions, {
        'p': {'start': 1, 'delta': 3, 'end': 4},
      });
      expect(parts[2].providerOptions, parts[0].providerOptions);
      expect(parts[1].providerOptions, {
        'p': {'other': 2},
      });
      expect(await result.text, 'onetwothree');
    },
  );
  test(
    'native reasoning IDs cannot collide with extracted reasoning',
    () async {
      final parts = await transform(const [
        StreamPartReasoningStart(id: 'mw-reasoning-1'),
        StreamPartReasoningDelta(id: 'mw-reasoning-1', delta: 'native'),
        StreamPartTextStart(id: 'a'),
        StreamPartTextStart(id: 'b'),
        StreamPartTextDelta(id: 'b', delta: '<think>extracted</think>answer'),
        StreamPartReasoningEnd(
          id: 'mw-reasoning-1',
          signature: 'keep-signature',
        ),
        StreamPartTextEnd(id: 'b'),
        StreamPartTextEnd(id: 'a'),
      ]);
      expectBalanced(parts);
      expect(
        parts.whereType<StreamPartReasoningStart>().map((p) => p.id).toSet(),
        hasLength(2),
      );
      expect(
        parts
            .whereType<StreamPartReasoningEnd>()
            .where((p) => p.id == 'mw-reasoning-1')
            .single
            .signature,
        'keep-signature',
      );
    },
  );

  test('nested extractors have separate reasoning namespaces', () async {
    final model = wrapLanguageModel(
      model: wrapLanguageModel(
        model: FakeStreamModel(const [
          StreamPartTextStart(id: 'a'),
          StreamPartTextDelta(
            id: 'a',
            delta: '<other>outer text that starts before inner',
          ),
          StreamPartTextDelta(
            id: 'a',
            delta: '<think>inner</think>end</other>answer',
          ),
          StreamPartTextEnd(id: 'a'),
        ]),
        middleware: extractReasoningMiddleware(),
      ),
      middleware: extractReasoningMiddleware(tagName: 'other'),
    );
    final result = await model.doStream(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    final parts = await result.stream.toList();
    expectBalanced(parts);
    expect(
      parts.whereType<StreamPartReasoningStart>().map((p) => p.id).toSet(),
      hasLength(2),
    );
  });

  test('terminal error flushes pending text before the error', () async {
    final failure = StreamPartError(error: StateError('provider failed'));
    final parts = await transform([
      const StreamPartTextStart(id: 'a'),
      const StreamPartTextDelta(id: 'a', delta: 'partial'),
      failure,
    ]);
    expectBalanced(parts);
    expect(
      parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
      'partial',
    );
    expect(parts.last, same(failure));
  });

  test('structured previews use interleaved delta order', () async {
    final result = await streamText(
      model: FakeStreamModel(const [
        StreamPartTextStart(id: 'a'),
        StreamPartTextStart(id: 'b'),
        StreamPartTextDelta(id: 'a', delta: '{"alpha":"abcdefghijklmnop",'),
        StreamPartTextDelta(id: 'b', delta: '"beta":"qrstuvwxyz012345",'),
        StreamPartTextDelta(id: 'a', delta: '"gamma":"last"}'),
        StreamPartTextEnd(id: 'b'),
        StreamPartTextEnd(id: 'a'),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
      prompt: 'go',
      output: Output.json(),
    );
    final partials = await result.partialOutputStream.toList();
    final expected = {
      'alpha': 'abcdefghijklmnop',
      'beta': 'qrstuvwxyz012345',
      'gamma': 'last',
    };
    expect(await result.output, expected);
    expect(partials.last, expected);
  });
}

void expectBalanced(List<LanguageModelV4StreamPart> parts) {
  final text = <String>{};
  final reasoning = <String>{};
  for (final part in parts) {
    switch (part) {
      case StreamPartTextStart(:final id):
        expect(text.add(id), isTrue);
      case StreamPartTextDelta(:final id):
        expect(text, contains(id));
      case StreamPartTextEnd(:final id):
        expect(text.remove(id), isTrue);
      case StreamPartReasoningStart(:final id):
        expect(reasoning.add(id), isTrue);
      case StreamPartReasoningDelta(:final id):
        expect(reasoning, contains(id));
      case StreamPartReasoningEnd(:final id):
        expect(reasoning.remove(id), isTrue);
      case StreamPartFinish():
        expect(text, isEmpty);
        expect(reasoning, isEmpty);
      default:
        break;
    }
  }
  expect(text, isEmpty);
  expect(reasoning, isEmpty);
}
