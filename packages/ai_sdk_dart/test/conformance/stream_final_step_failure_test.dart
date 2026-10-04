import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test('final step settles with the source failure', () async {
    final error = StateError('source failed');
    final result = await streamText(
      model: FakeErrorStreamModel(error),
      prompt: 'go',
    );
    await expectLater(result.text, throwsA(same(error)));
    await expectLater(
      result.finalStep.timeout(const Duration(seconds: 1)),
      throwsA(same(error)),
    );
  });
}
