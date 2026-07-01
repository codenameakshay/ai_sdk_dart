import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('item $i')),
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
      await tester.pump();
      expect(find.byKey(const ValueKey('scroll-to-bottom')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('scroll-to-bottom')));
      await tester.pumpAndSettle();

      expect(controller.position.pixels, controller.position.maxScrollExtent);
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
  });
}
