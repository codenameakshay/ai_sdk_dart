import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'text metadata survives lifecycle, final content, and next prompt',
    () async {
      final first = FakeStreamModel([
        const StreamPartTextStart(
          id: 'text-1',
          providerMetadata: {
            'vendor': {'start': true, 'shared': 'start'},
          },
        ),
        const StreamPartTextDelta(
          id: 'text-1',
          delta: 'hello',
          providerMetadata: {
            'vendor': {'delta': true, 'shared': 'delta'},
          },
        ),
        const StreamPartTextEnd(
          id: 'text-1',
          providerMetadata: {
            'vendor': {'end': true, 'shared': 'end'},
          },
        ),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]);
      final result = await streamText(model: first, prompt: 'first');
      final events = await result.fullStream.toList();
      final textEvents = events.whereType<StreamTextEvent>().toList();
      expect(
        textEvents
            .whereType<StreamTextTextStartEvent>()
            .single
            .providerMetadata,
        {
          'vendor': {'start': true, 'shared': 'start'},
        },
      );
      expect(
        textEvents
            .whereType<StreamTextTextDeltaEvent>()
            .single
            .providerMetadata,
        {
          'vendor': {'delta': true, 'shared': 'delta'},
        },
      );
      expect(
        textEvents.whereType<StreamTextTextEndEvent>().single.providerMetadata,
        {
          'vendor': {'end': true, 'shared': 'end'},
        },
      );
      final content =
          (await result.steps).single.content.single as LanguageModelV4TextPart;
      expect(content.text, 'hello');
      expect(content.providerOptions, {
        'vendor': {'start': true, 'delta': true, 'end': true, 'shared': 'end'},
      });

      final second = FakeCapturingStreamModel('next');
      final next = await streamText(
        model: second,
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: [content],
          ),
        ],
      );
      await next.text;
      final replayed =
          second.lastOptions!.prompt.messages.single.content.single
              as LanguageModelV4TextPart;
      expect(replayed.providerOptions, content.providerOptions);
    },
  );
}
