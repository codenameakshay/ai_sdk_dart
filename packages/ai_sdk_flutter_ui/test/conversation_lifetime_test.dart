import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _SharedBackend implements ConversationBackend, ConversationRetryBackend {
  int calls = 0;
  final _changes = StreamController<Conversation>.broadcast();
  @override
  final conversation = Conversation(id: 'shared', messages: const []);
  @override
  Stream<Conversation> get changes => _changes.stream;
  @override
  ConversationRetryInfo get retryInfo =>
      const ConversationRetryInfo(ConversationRetryAvailability.available);
  @override
  Future<void> send(String text) async => calls++;
  @override
  Future<void> retryLastTurn() async => calls++;
  @override
  Future<void> interrupt() async => calls++;
  @override
  Future<void> restore(Map<String, dynamic> encoded) async => calls++;
  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async => calls++;
  @override
  Future<void> dispose() => _changes.close();
}

void main() {
  test('disposed chat controller does not send or mutate history', () async {
    final model = MockLanguageModelV4(response: [mockText('late')]);
    final chat = ChatController();
    chat.dispose();
    await chat.sendMessage(
      agent: ToolLoopAgent(model: model),
      text: 'late',
    );
    expect(model.streamCalls, isEmpty);
    expect(chat.messages, isEmpty);
    expect(chat.status, ChatStatus.ready);
  });

  test('disposed completion controller does not start a request', () async {
    final model = MockLanguageModelV4(response: [mockText('late')]);
    final completion = CompletionController(agent: ToolLoopAgent(model: model));
    completion.dispose();
    await completion.complete('late');
    expect(model.streamCalls, isEmpty);
    expect(completion.isLoading, isFalse);
  });

  test('disposed object controller does not start a request', () async {
    final model = MockLanguageModelV4(response: [mockText('{}')]);
    final objects = ObjectStreamController<Map<String, dynamic>>(
      model: model,
      schema: Schema(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      ),
    );
    objects.dispose();
    await objects.submit('late');
    expect(model.streamCalls, isEmpty);
    expect(objects.isLoading, isFalse);
  });

  test(
    'disposed object controller does not subscribe to a new stream',
    () async {
      var subscribed = false;
      final source = StreamController<String>.broadcast(
        onListen: () => subscribed = true,
      );
      addTearDown(source.close);
      final objects = ObjectStreamController<String>();
      objects.dispose();
      await objects.bind(source.stream);
      expect(subscribed, isFalse);
      expect(objects.isLoading, isFalse);
    },
  );

  test(
    'disposed conversation controller cannot dispatch to a shared backend',
    () async {
      final backend = _SharedBackend();
      addTearDown(backend.dispose);
      final controller = ConversationController(backend, disposeBackend: false);
      await controller.dispose();
      for (final operation in <Future<void> Function()>[
        () => controller.send('late'),
        controller.retryLastTurn,
        controller.interrupt,
        () => controller.restore(const {}),
        () => controller.respondToApproval(approvalId: 'late', approved: true),
      ]) {
        await expectLater(operation, throwsStateError);
      }
      expect(backend.calls, 0);
    },
  );

  test(
    'disposed chat adapter ignores late actions on a shared controller',
    () async {
      final backend = _SharedBackend();
      addTearDown(backend.dispose);
      final controller = ConversationController(backend, disposeBackend: false);
      addTearDown(controller.dispose);
      final chat = ConversationChatController(
        controller,
        disposeConversationController: false,
      );
      chat.dispose();
      await chat.sendText('late');
      await chat.reload();
      await chat.stop();
      chat.addToolApprovalResponse(approvalId: 'late', approved: true);
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, 0);
      expect(chat.status, ChatStatus.ready);
    },
  );
}
