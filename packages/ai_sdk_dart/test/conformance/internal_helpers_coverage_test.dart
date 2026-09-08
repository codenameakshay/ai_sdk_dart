import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/partial_json.dart';
import 'package:ai_sdk_dart/src/core/shared/common_helpers.dart';
import 'package:ai_sdk_dart/src/core/streaming/structured_output.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  Schema<Map<String, dynamic>> objectSchema() => Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  group('partial json helpers', () {
    test('debug counters track parse attempts by trigger', () {
      final counters = PartialJsonDebugCounters();

      expect(
        counters.parseAttemptsForTrigger(
          PartialJsonParseTrigger.arrayElementBoundary,
        ),
        0,
      );

      counters.recordParseAttempt(
        phase: PartialJsonParsePhase.streamTextPartial,
        trigger: PartialJsonParseTrigger.arrayElementBoundary,
      );

      expect(
        counters.parseAttemptsForTrigger(
          PartialJsonParseTrigger.arrayElementBoundary,
        ),
        1,
      );
    });

    test(
      'partialJsonFingerprint falls back to toString for unencodable values',
      () {
        expect(partialJsonFingerprint(_Unencodable()), 'Unencodable()');
      },
    );
  });

  group('structured output helpers', () {
    test('choice output accepts plain trimmed text', () {
      final output = parseOutput<String>(
        Output.choice(options: const ['sunny', 'rainy']),
        '  sunny  ',
      );
      expect(output, 'sunny');
    });

    test('choice output rejects invalid plain text', () {
      expect(
        () => parseOutput<String>(
          Output.choice(options: const ['sunny', 'rainy']),
          'cloudy',
        ),
        throwsA(isA<AiInvalidToolInputError>()),
      );
    });

    test('object output accepts a typed decoded map', () {
      final output = parseOutput<Map<String, dynamic>>(
        Output.object(schema: objectSchema()),
        '{"ok":true}',
      );
      expect(output, {'ok': true});
    });
  });

  group('usage aggregation', () {
    test('keeps absent usage distinct from reported zero usage', () {
      expect(sumUsage([null, const LanguageModelV4Usage()]), isNull);

      final total = sumUsage([
        const LanguageModelV4Usage(
          inputTokens: LanguageModelV4InputTokenUsage(total: 0),
          outputTokens: LanguageModelV4OutputTokenUsage(total: 0),
        ),
      ]);
      expect(total?.inputTokens.total, 0);
      expect(total?.outputTokens.total, 0);
    });

    test('sums every nested token detail across steps', () {
      final total = sumUsage([
        const LanguageModelV4Usage(
          inputTokens: LanguageModelV4InputTokenUsage(
            total: 10,
            noCache: 6,
            cacheRead: 3,
            cacheWrite: 1,
          ),
          outputTokens: LanguageModelV4OutputTokenUsage(
            total: 5,
            text: 4,
            reasoning: 1,
          ),
        ),
        const LanguageModelV4Usage(
          inputTokens: LanguageModelV4InputTokenUsage(
            total: 7,
            noCache: 2,
            cacheRead: 5,
          ),
          outputTokens: LanguageModelV4OutputTokenUsage(
            total: 4,
            text: 1,
            reasoning: 3,
          ),
        ),
      ]);

      expect(total?.inputTokens.total, 17);
      expect(total?.inputTokens.noCache, 8);
      expect(total?.inputTokens.cacheRead, 8);
      expect(total?.inputTokens.cacheWrite, 1);
      expect(total?.outputTokens.total, 9);
      expect(total?.outputTokens.text, 5);
      expect(total?.outputTokens.reasoning, 4);
    });
  });
}

class _Unencodable {
  @override
  String toString() => 'Unencodable()';
}
