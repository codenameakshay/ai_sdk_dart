import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../example/recipes/bloc_conversation.dart';
import '../example/recipes/riverpod_conversation.dart';
import 'helpers.dart';

FakeConversationBackend _backend(String id) => FakeConversationBackend(
  initial: Conversation(id: id, messages: const []),
);

void main() {
  testWidgets('Riverpod snapshot provider rebuilds and auto-disposes', (
    tester,
  ) async {
    final backend = _backend('one');
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
    backend.emit('two');
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
    final first = _backend('first');
    final second = _backend('second');
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
    first.emit('late-first');
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close().timeout(const Duration(seconds: 1));
    expect(first.disposeCount, 1);
    await second.dispose();
    await first.streamController.close();
    await second.streamController.close();
  });

  test(
    'Bloc replacement and close race cannot resurrect a subscription',
    () async {
      final first = _backend('first');
      final second = _backend('second');
      final third = _backend('third');
      final cubit = ConversationCubit(first, disposeBackend: true);
      final replacement = cubit.replaceBackend(second);
      final closing = cubit.close();
      await Future.wait([replacement, closing]);
      second.emit('late-second');
      third.emit('late-third');
      expect(cubit.isClosed, isTrue);
      expect(first.disposeCount, 1);
      await second.streamController.close();
      await third.dispose();
      await third.streamController.close();
    },
  );

  test(
    'Bloc keeps caller-owned backends alive during replacement and close',
    () async {
      final first = _backend('first');
      final second = _backend('second');
      final cubit = ConversationCubit(first);
      await cubit.replaceBackend(second);
      await cubit.close();
      expect(first.disposeCount, 0);
      expect(second.disposeCount, 0);
      await first.streamController.close();
      await second.streamController.close();
    },
  );

  test('Bloc same-backend replacement is a no-op', () async {
    final backend = _backend('same');
    final cubit = ConversationCubit(backend, disposeBackend: true);
    await cubit.replaceBackend(backend);
    expect(backend.disposeCount, 0);
    await cubit.close();
    expect(backend.disposeCount, 1);
    await backend.streamController.close();
  });

  test(
    'queued replacement cleanup cancels the captured subscription',
    () async {
      final releaseFirst = Completer<void>();
      final first = FakeConversationBackend(
        initial: Conversation(id: 'first', messages: const []),
        broadcast: false,
        onCancelDelay: releaseFirst.future,
      );
      final second = _backend('second');
      final third = _backend('third');
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
      expect(second.cancelCount, 1);
      expect(third.cancelCount, 0);
      third.emit('third-update');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.id, 'third-update');
    },
  );
}
