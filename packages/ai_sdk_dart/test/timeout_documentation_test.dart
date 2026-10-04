import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'conformance/helpers/fake_models.dart';

void main() {
  final root =
      File('README.md').existsSync() && Directory('packages').existsSync()
      ? ''
      : '../../';
  for (final path in [
    'README.md',
    'packages/ai_sdk_dart/README.md',
    'docs/migration/v2-to-v3.md',
  ]) {
    test('$path documents the typed text timeout parameter', () async {
      final text = File('$root$path').readAsStringSync();
      expect(
        text.contains(
          'timeout: const TimeoutConfiguration(total: Duration(seconds: 30))',
        ),
        isTrue,
      );
      expect(
        text.contains('`timeout` remains the total-duration shorthand'),
        isFalse,
      );
      expect(
        text.contains('apply `Duration` deadlines to any model call'),
        isFalse,
      );
      final model = FakeTextModel('answer');
      final generated = await generateText(
        model: model,
        timeout: const TimeoutConfiguration(total: Duration(seconds: 30)),
      );
      final streamed = await streamText(
        model: model,
        timeout: const TimeoutConfiguration(total: Duration(seconds: 30)),
      );
      final agent = await ToolLoopAgent(model: model).generate(
        timeout: const TimeoutConfiguration(total: Duration(seconds: 30)),
      );
      expect(generated.text, 'answer');
      expect(await streamed.text, 'answer');
      expect(agent.text, 'answer');
      final embedded = await embed(
        model: FakeEmbeddingModel([1]),
        value: 'input',
        timeout: const Duration(seconds: 30),
      );
      expect(embedded.embedding, [1]);
    });
  }
}
