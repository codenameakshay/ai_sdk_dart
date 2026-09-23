import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'streamText preserves opaque reasoning metadata and signatures in response history',
    () async {
      final model = FakeStreamModel(const [
        StreamPartReasoningStart(
          id: 'r',
          providerMetadata: {
            'vendor': {'itemId': 'item-1'},
          },
        ),
        StreamPartReasoningDelta(
          id: 'r',
          delta: 'thought',
          providerMetadata: {
            'vendor': {'opaque': 'retain'},
          },
        ),
        StreamPartReasoningEnd(
          id: 'r',
          signature: 'signed',
          providerMetadata: {
            'vendor': {'continuation': 'next'},
          },
        ),
        StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]);
      final result = await streamText(model: model, prompt: 'reason');
      final response = await result.response;
      final part = response.messages.single.content
          .whereType<LanguageModelV4ReasoningPart>()
          .single;
      expect(part.signature, 'signed');
      expect(part.providerOptions, {
        'vendor': {
          'itemId': 'item-1',
          'opaque': 'retain',
          'continuation': 'next',
        },
      });
    },
  );
}
