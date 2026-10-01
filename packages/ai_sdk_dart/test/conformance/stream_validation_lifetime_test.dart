import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  test(
    'invalid approval responses do not retain cancellation observers',
    () async {
      final token = _ObservedToken();
      addTearDown(token.events.close);
      const response = LanguageModelV4ToolApprovalResponse(
        approvalId: 'duplicate',
        approved: true,
      );
      await expectLater(
        streamText(
          model: FakeTextModel('unused'),
          abortSignal: token,
          toolApprovalResponses: const [response, response],
        ),
        throwsArgumentError,
      );
      expect(token.events.hasListener, isFalse);
    },
  );
}

class _ObservedToken extends CancellationToken {
  final events = StreamController<void>.broadcast();

  @override
  Stream<void> get cancellationEvents => events.stream;
}
