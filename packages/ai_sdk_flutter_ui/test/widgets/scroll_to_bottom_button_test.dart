import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _tabUntilActivated(
  WidgetTester tester,
  bool Function() activated, {
  int maxTabs = 10,
}) async {
  for (var i = 0; i < maxTabs; i++) {
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }
  fail('Unable to activate target after $maxTabs tabs');
}

void main() {
  group('ScrollToBottomButton', () {
    late ScrollController controller;

    setUp(() => controller = ScrollController());
    tearDown(() => controller.dispose());

    Widget harness() => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              controller: controller,
              itemCount: 40,
              itemBuilder: (_, i) =>
                  SizedBox(height: 50, child: Text('item $i')),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: ScrollToBottomButton(controller: controller),
            ),
          ],
        ),
      ),
    );

    testWidgets('stays hidden before any scroll view attaches', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ScrollToBottomButton(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsNothing);
    });

    testWidgets('is hidden when the list is already at the bottom', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsNothing);
    });

    testWidgets('is visible when scrolled up from the bottom', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump(); // let the post-layout visibility check run

      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);
    });

    testWidgets('tapping scrolls to the bottom', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
      await tester.pumpAndSettle();

      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });

    testWidgets('uses an accessible label and touch target when visible', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      final node = tester
          .getSemantics(
            find.byKey(const ValueKey('scroll-to-bottom-semantics')),
          )
          .getSemanticsData();
      expect(node.label, 'Scroll to latest message');
      final size = tester.getSize(
        find.byKey(const ValueKey('scroll-to-bottom')),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    testWidgets('jumps to the bottom under reduced motion on tap', (
      tester,
    ) async {
      Widget reducedHarness() => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Stack(
              children: [
                ListView.builder(
                  controller: controller,
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 50, child: Text('item $i')),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: ScrollToBottomButton(controller: controller),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(reducedHarness());
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);
      expect(controller.position.pixels, 0);

      // The reduced-motion path uses jumpTo, so the position lands at the
      // bottom synchronously (no animation to settle).
      await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
      await tester.pump();

      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });

    testWidgets('is reachable and activatable by keyboard', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await _tabUntilActivated(
        tester,
        () => controller.position.pixels == controller.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      expect(controller.position.pixels, controller.position.maxScrollExtent);
      semantics.dispose();
    });

    testWidgets('re-wires its listener when the controller changes', (
      tester,
    ) async {
      final other = ScrollController();
      addTearDown(other.dispose);

      Widget build(ScrollController c) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView.builder(
                controller: c,
                itemCount: 40,
                itemBuilder: (_, i) =>
                    SizedBox(height: 50, child: Text('item $i')),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: ScrollToBottomButton(controller: c),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(build(other));
      await tester.pump();
      // Swap to a different controller — exercises didUpdateWidget re-wiring.
      await tester.pumpWidget(build(controller));
      await tester.pump();

      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsNothing);
    });

    testWidgets(
      'stays hidden in scaffold empty state before the list attaches',
      (tester) async {
        final chatController = ChatController();
        addTearDown(chatController.dispose);
        final agent = ToolLoopAgent(model: MockLanguageModelV4());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AiChatScaffold(
                controller: chatController,
                agent: agent,
                emptyState: const Center(child: Text('No messages yet')),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.byKey(const ValueKey('scroll-to-bottom')), findsNothing);
      },
    );
  });
}
