import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/recipes/bloc_conversation.dart';
import '../example/recipes/riverpod_conversation.dart';

class _Backend implements ConversationBackend {
  _Backend(String id)
    : _conversation = Conversation(id: id, messages: const []);
  Conversation _conversation;
  final controller = StreamController<Conversation>.broadcast();
  int disposeCount = 0;
  bool get isDisposed => disposeCount > 0;
  @override
  Conversation get conversation => _conversation;
  @override
  Stream<Conversation> get changes => controller.stream;
  void emitId(String id) {
    _conversation = Conversation(id: id, messages: const []);
    controller.add(_conversation);
  }

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
    disposeCount++;
  }
}

void main() {
  testWidgets('Riverpod snapshot provider rebuilds and auto-disposes', (
    tester,
  ) async {
    final backend = _Backend('one');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final snapshot = ref.watch(conversationSnapshotProvider(backend));
              return Text(snapshot.value?.id ?? 'loading');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('one'), findsOneWidget);
    backend.emitId('two');
    await tester.pump();
    await tester.pump();
    expect(find.text('two'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(backend.disposeCount, 1);
  });

  testWidgets('Bloc replacement ignores late emissions from the old backend', (
    tester,
  ) async {
    final first = _Backend('first');
    final second = _Backend('second');
    final cubit = ConversationCubit(first, disposeBackend: true);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: BlocBuilder<ConversationCubit, Conversation>(
            builder: (_, state) => Text(state.id),
          ),
        ),
      ),
    );
    expect(find.text('first'), findsOneWidget);
    await cubit.replaceBackend(second);
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    first.emitId('late-first');
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close().timeout(const Duration(seconds: 1));
    expect(first.disposeCount, 1);
    await second.dispose();
    await first.controller.close();
    await second.controller.close();
  });

  test(
    'Bloc replacement and close race cannot resurrect a subscription',
    () async {
      final first = _Backend('first');
      final second = _Backend('second');
      final third = _Backend('third');
      final cubit = ConversationCubit(first, disposeBackend: true);
      final replacement = cubit.replaceBackend(second);
      final closing = cubit.close();
      await Future.wait([replacement, closing]);
      second.emitId('late-second');
      third.emitId('late-third');
      expect(cubit.isClosed, isTrue);
      expect(first.disposeCount, 1);
      await second.controller.close();
      await third.dispose();
      await third.controller.close();
    },
  );

  test(
    'Bloc keeps caller-owned backends alive during replacement and close',
    () async {
      final first = _Backend('first');
      final second = _Backend('second');
      final cubit = ConversationCubit(first);
      await cubit.replaceBackend(second);
      await cubit.close();
      expect(first.disposeCount, 0);
      expect(second.disposeCount, 0);
      await first.controller.close();
      await second.controller.close();
    },
  );

  test('Bloc same-backend replacement is a no-op', () async {
    final backend = _Backend('same');
    final cubit = ConversationCubit(backend, disposeBackend: true);
    await cubit.replaceBackend(backend);
    expect(backend.disposeCount, 0);
    await cubit.close();
    expect(backend.disposeCount, 1);
    await backend.controller.close();
  });
}
