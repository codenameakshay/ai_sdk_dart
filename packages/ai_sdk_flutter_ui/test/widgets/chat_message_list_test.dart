import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

class _TrackingScrollController extends ScrollController {
  int animateCallCount = 0;
  int jumpCallCount = 0;

  void resetCounts() {
    animateCallCount = 0;
    jumpCallCount = 0;
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    animateCallCount += 1;
    return super.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  void jumpTo(double value) {
    jumpCallCount += 1;
    super.jumpTo(value);
  }
}

Widget _scrollHarness({
  required ChatController controller,
  required ScrollController scrollController,
  bool disableAnimations = false,
  double viewportHeight = 240,
  double rowHeight = 72,
  Widget? emptyState,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: SizedBox(
          height: viewportHeight,
          child: ChatMessageList(
            controller: controller,
            scrollController: scrollController,
            emptyState: emptyState,
            messageBuilder: (context, message, isStreaming) => SizedBox(
              height: rowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${isStreaming ? 'stream:' : 'msg:'}${message.content}',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntilStreamingStarts(
  WidgetTester tester,
  ChatController controller,
) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (controller.streamingContent.isNotEmpty) return;
  }
  fail('streaming did not start');
}

void main() {
  group('ChatMessageList', () {
    testWidgets('renders existing messages', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'first user'),
          ModelMessage(
            role: ModelMessageRole.assistant,
            content: 'first assistant',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: controller)));

      expect(find.text('first user'), findsOneWidget);
      expect(find.text('first assistant'), findsOneWidget);
    });

    testWidgets('announces user and assistant message roles', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'first user'),
          ModelMessage(
            role: ModelMessageRole.assistant,
            content: 'first assistant',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: controller)));

      final userNode = tester
          .getSemantics(find.byType(ChatMessageBubble))
          .getSemanticsData();
      final assistantNode = tester
          .getSemantics(
            find.byKey(const ValueKey('assistant-message-semantics')),
          )
          .getSemanticsData();
      expect(userNode.label, 'User message');
      expect(userNode.value, 'first user');
      expect(assistantNode.label, 'Assistant message');
      expect(assistantNode.value, 'first assistant');
      semantics.dispose();
    });

    testWidgets('shows the optimistic streaming bubble', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'ask'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: controller)));
      expect(find.text('ask'), findsOneWidget);

      // Use a model that holds the stream open after emitting text, so the
      // optimistic in-flight bubble is observable while streaming.
      final model = HoldingTextModel('streamed reply');
      controller.sendMessage(
        agent: ToolLoopAgent(model: model),
        text: 'ask again',
      );

      // Pump frames until the streaming content appears.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (controller.streamingContent.isNotEmpty) break;
      }

      expect(controller.streamingContent.isNotEmpty, isTrue);
      // The optimistic assistant turn renders flush via StreamingTextView
      // (no bubble), carrying the live buffer.
      expect(find.byType(StreamingTextView), findsOneWidget);
      expect(
        tester.widget<StreamingTextView>(find.byType(StreamingTextView)).text,
        'streamed reply',
      );

      // Release the stream and let it settle so no timers dangle.
      model.finish();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (controller.status == ChatStatus.ready) break;
      }
    });

    testWidgets('renders the empty state when provided and empty', (
      tester,
    ) async {
      final controller = ChatController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            controller: controller,
            emptyState: const Text('Start chatting'),
          ),
        ),
      );
      expect(find.text('Start chatting'), findsOneWidget);
    });

    testWidgets('uses a custom messageBuilder when provided', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'raw'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            controller: controller,
            messageBuilder: (context, message, isStreaming) =>
                Text('custom:${message.content}'),
          ),
        ),
      );
      expect(find.text('custom:raw'), findsOneWidget);
    });

    testWidgets('swapping the controller re-subscribes to the new one', (
      tester,
    ) async {
      final first = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'from first'),
        ],
      );
      addTearDown(first.dispose);
      final second = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'from second'),
        ],
      );
      addTearDown(second.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: first)));
      expect(find.text('from first'), findsOneWidget);

      // Rebuild with a different controller -> didUpdateWidget swaps listeners.
      await tester.pumpWidget(_wrap(ChatMessageList(controller: second)));
      expect(find.text('from second'), findsOneWidget);
      expect(find.text('from first'), findsNothing);

      // The new controller is the live one: its changes drive rebuilds.
      second.append(
        const ModelMessage(role: ModelMessageRole.user, content: 'later'),
      );
      await tester.pump();
      expect(find.text('later'), findsOneWidget);
    });

    testWidgets('keeps pinned readers at the bottom while streaming', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: List.generate(
          14,
          (index) => ModelMessage(
            role: ModelMessageRole.user,
            content: 'message $index',
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scrollController = _TrackingScrollController();
      addTearDown(scrollController.dispose);
      final model = HoldingTextModel('streamed reply');

      await tester.pumpWidget(
        _scrollHarness(
          controller: controller,
          scrollController: scrollController,
        ),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      scrollController.resetCounts();

      controller.sendMessage(
        agent: ToolLoopAgent(model: model),
        text: 'ask',
      );
      await _pumpUntilStreamingStarts(tester, controller);
      await tester.pumpAndSettle();

      expect(
        scrollController.position.pixels,
        scrollController.position.maxScrollExtent,
      );
      expect(
        scrollController.animateCallCount + scrollController.jumpCallCount,
        greaterThan(0),
      );

      model.finish();
      await tester.pumpAndSettle();
    });

    testWidgets('does not yank scrolled-up readers during streaming', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: List.generate(
          16,
          (index) => ModelMessage(
            role: ModelMessageRole.user,
            content: 'message $index',
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scrollController = _TrackingScrollController();
      addTearDown(scrollController.dispose);
      final model = HoldingTextModel('streamed reply');

      await tester.pumpWidget(
        _scrollHarness(
          controller: controller,
          scrollController: scrollController,
        ),
      );

      final maxExtent = scrollController.position.maxScrollExtent;
      final initialOffset = (maxExtent - 220).clamp(0.0, maxExtent);
      scrollController.jumpTo(initialOffset);
      await tester.pump();
      scrollController.resetCounts();

      controller.sendMessage(
        agent: ToolLoopAgent(model: model),
        text: 'ask',
      );
      await _pumpUntilStreamingStarts(tester, controller);
      await tester.pump();

      expect(scrollController.position.pixels, initialOffset);
      expect(scrollController.animateCallCount, 0);
      expect(scrollController.jumpCallCount, 0);

      model.finish();
      await tester.pumpAndSettle();
    });

    testWidgets('manual return to bottom resumes auto-pinning', (tester) async {
      final controller = ChatController(
        initialMessages: List.generate(
          16,
          (index) => ModelMessage(
            role: ModelMessageRole.user,
            content: 'message $index',
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scrollController = _TrackingScrollController();
      addTearDown(scrollController.dispose);
      final firstModel = HoldingTextModel('first reply');
      final secondModel = HoldingTextModel('second reply');

      await tester.pumpWidget(
        _scrollHarness(
          controller: controller,
          scrollController: scrollController,
        ),
      );

      final maxExtent = scrollController.position.maxScrollExtent;
      scrollController.jumpTo((maxExtent - 220).clamp(0.0, maxExtent));
      await tester.pump();

      controller.sendMessage(
        agent: ToolLoopAgent(model: firstModel),
        text: 'first ask',
      );
      await _pumpUntilStreamingStarts(tester, controller);
      await tester.pump();

      expect(
        scrollController.position.pixels,
        lessThan(scrollController.position.maxScrollExtent),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      scrollController.resetCounts();

      firstModel.finish();
      await tester.pumpAndSettle();

      controller.sendMessage(
        agent: ToolLoopAgent(model: secondModel),
        text: 'second ask',
      );
      await _pumpUntilStreamingStarts(tester, controller);
      await tester.pumpAndSettle();

      expect(
        scrollController.position.pixels,
        scrollController.position.maxScrollExtent,
      );
      expect(
        scrollController.animateCallCount + scrollController.jumpCallCount,
        greaterThan(0),
      );

      secondModel.finish();
      await tester.pumpAndSettle();
    });

    testWidgets('uses an instant jump for auto-pin when motion is reduced', (
      tester,
    ) async {
      final controller = ChatController(
        initialMessages: List.generate(
          14,
          (index) => ModelMessage(
            role: ModelMessageRole.user,
            content: 'message $index',
          ),
        ),
      );
      addTearDown(controller.dispose);
      final scrollController = _TrackingScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _scrollHarness(
          controller: controller,
          scrollController: scrollController,
          disableAnimations: true,
        ),
      );

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      scrollController.resetCounts();

      controller.append(
        const ModelMessage(role: ModelMessageRole.user, content: 'newest'),
      );
      await tester.pump();

      expect(scrollController.jumpCallCount, 1);
      expect(scrollController.animateCallCount, 0);
      expect(
        scrollController.position.pixels,
        scrollController.position.maxScrollExtent,
      );
    });

    testWidgets(
      'coalesces multiple content changes into one scroll per frame',
      (tester) async {
        final controller = ChatController(
          initialMessages: List.generate(
            14,
            (index) => ModelMessage(
              role: ModelMessageRole.user,
              content: 'message $index',
            ),
          ),
        );
        addTearDown(controller.dispose);
        final scrollController = _TrackingScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          _scrollHarness(
            controller: controller,
            scrollController: scrollController,
            disableAnimations: true,
          ),
        );

        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();
        scrollController.resetCounts();

        controller.append(
          const ModelMessage(role: ModelMessageRole.user, content: 'one'),
        );
        controller.append(
          const ModelMessage(role: ModelMessageRole.user, content: 'two'),
        );
        controller.append(
          const ModelMessage(role: ModelMessageRole.user, content: 'three'),
        );
        await tester.pump();

        expect(scrollController.jumpCallCount, 1);
        expect(scrollController.animateCallCount, 0);
      },
    );

    testWidgets(
      'uses a replacement scroll controller for future auto-scrolls',
      (tester) async {
        final controller = ChatController(
          initialMessages: List.generate(
            14,
            (index) => ModelMessage(
              role: ModelMessageRole.user,
              content: 'message $index',
            ),
          ),
        );
        addTearDown(controller.dispose);
        final firstScrollController = _TrackingScrollController();
        final secondScrollController = _TrackingScrollController();
        addTearDown(firstScrollController.dispose);
        addTearDown(secondScrollController.dispose);

        await tester.pumpWidget(
          _scrollHarness(
            controller: controller,
            scrollController: firstScrollController,
            disableAnimations: true,
          ),
        );
        await tester.pumpWidget(
          _scrollHarness(
            controller: controller,
            scrollController: secondScrollController,
            disableAnimations: true,
          ),
        );

        secondScrollController.jumpTo(
          secondScrollController.position.maxScrollExtent,
        );
        await tester.pump();
        firstScrollController.resetCounts();
        secondScrollController.resetCounts();

        controller.append(
          const ModelMessage(
            role: ModelMessageRole.user,
            content: 'replacement',
          ),
        );
        await tester.pump();

        expect(secondScrollController.jumpCallCount, 1);
        expect(firstScrollController.jumpCallCount, 0);
      },
    );

    testWidgets(
      'first streamed response auto-pins after empty state attaches',
      (tester) async {
        final controller = ChatController();
        addTearDown(controller.dispose);
        final scrollController = _TrackingScrollController();
        addTearDown(scrollController.dispose);
        final model = HoldingTextModel('streamed reply');

        await tester.pumpWidget(
          _scrollHarness(
            controller: controller,
            scrollController: scrollController,
            viewportHeight: 120,
            rowHeight: 100,
            emptyState: const Center(child: Text('Start chatting')),
          ),
        );
        await tester.pump();

        expect(find.text('Start chatting'), findsOneWidget);
        expect(scrollController.hasClients, isFalse);

        controller.sendMessage(
          agent: ToolLoopAgent(model: model),
          text: 'ask',
        );
        await _pumpUntilStreamingStarts(tester, controller);
        await tester.pumpAndSettle();

        expect(scrollController.hasClients, isTrue);
        expect(
          scrollController.position.pixels,
          scrollController.position.maxScrollExtent,
        );
        expect(
          scrollController.animateCallCount + scrollController.jumpCallCount,
          greaterThan(0),
        );

        model.finish();
        await tester.pumpAndSettle();
      },
    );
  });
}
