import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  final output = Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {'type': 'object'},
      fromJson: (json) => json,
    ),
  );

  test('generateText rejects valid JSON followed by malformed text', () async {
    await expectLater(
      generateText(
        model: FakeTextModel('{"ok":true} trailing {"broken":'),
        output: output,
        prompt: 'json',
      ),
      throwsA(isA<AiNoObjectGeneratedError>()),
    );
  });

  test(
    'streamText rejects a complete object followed by a truncated object',
    () async {
      final result = await streamText(
        model: FakeTextModel('{"ok":true}{"broken":'),
        output: output,
        prompt: 'json',
      );
      await expectLater(
        result.output,
        throwsA(isA<AiNoObjectGeneratedError>()),
      );
    },
  );

  test('generateText rejects multiple JSON documents', () async {
    await expectLater(
      generateText(
        model: FakeTextModel('{} {}'),
        output: output,
        prompt: 'json',
      ),
      throwsA(isA<AiNoObjectGeneratedError>()),
    );
  });

  test('streamText rejects multiple JSON documents', () async {
    final result = await streamText(
      model: FakeTextModel('{} {}'),
      output: output,
      prompt: 'json',
    );
    await expectLater(result.output, throwsA(isA<AiNoObjectGeneratedError>()));
  });
}
