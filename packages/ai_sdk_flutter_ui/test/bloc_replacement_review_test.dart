import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/recipes/bloc_conversation.dart';

void main() {
  test(
    'queued replacement cleanup cancels the captured subscription',
    () async {
      final releaseFirst = Completer<void>();
      final first = _Backend('first', cancellation: releaseFirst.future);
      final second = _Backend('second');
      final third = _Backend('third');
      final cubit = ConversationCubit(first);
      addTearDown(() async {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        await cubit.close();
        await first.dispose();
        await second.dispose();
        await third.dispose();
      });

      final replaceSecond = cubit.replaceBackend(second);
      await Future<void>.delayed(Duration.zero);
      final replaceThird = cubit.replaceBackend(third);
      releaseFirst.complete();
      await Future.wait([replaceSecond, replaceThird]);
      await Future<void>.delayed(Duration.zero);

      expect(first.cancelCount, 1);
      expect(second.cancelCount, lessThanOrEqualTo(1));
      expect(third.cancelCount, 0);
      third.emit('third-update');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.id, 'third-update');
    },
  );
}

class _Backend implements ConversationBackend {
  _Backend(String id, {Future<void>? cancellation})
    : _conversation = Conversation(id: id, messages: const []) {
    _changes = StreamController<Conversation>(
      onCancel: () {
        cancelCount++;
        return cancellation;
      },
    );
  }

  Conversation _conversation;
  late final StreamController<Conversation> _changes;
  int cancelCount = 0;

  void emit(String id) {
    _conversation = Conversation(id: id, messages: const []);
    _changes.add(_conversation);
  }

  @override
  Conversation get conversation => _conversation;
  @override
  Stream<Conversation> get changes => _changes.stream;
  @override
  Future<void> send(String text) async {}
  @override
  Future<void> interrupt() async {}
  @override
  Future<void> restore(Map<String, dynamic> encoded) async {}
  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {}
  @override
  Future<void> dispose() async {
    unawaited(_changes.close());
  }
}
