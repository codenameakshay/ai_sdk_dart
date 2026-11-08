import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

const _five =
    'root = Col([c])\n'
    'c = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])';

Finder _card(int index) => find
    .byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).borderRadius ==
              BorderRadius.circular(14),
    )
    .at(index);

Finder _arrow(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

Finder _panel() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).borderRadius ==
          BorderRadius.circular(12),
);

double _horizontalPixels(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.horizontal,
      ),
    )
    .position
    .pixels;

Finder _sizedBoxAround(WidgetTester tester, String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(SizedBox)).first;

void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('Carousel', () {
    testWidgets('arrows update when streamed items overflow the track', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final p = await pumpProgram(
        tester,
        'root = Col([Carousel([Text("One")])])',
      );
      await tester.pumpAndSettle();
      expect(_arrow('Next'), findsNothing);
      p.session.update(
        'root = Col([Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])])',
        streaming: false,
      );
      await tester.pumpAndSettle();
      expect(_arrow('Next'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('cards in one carousel are equal in height', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([c])\n'
        'c = Carousel([Card([Text("a")]), Card([Text("b"), Text("c"), Text("d")])])',
      );
      final short = tester.getSize(_card(0)).height;
      final tall = tester.getSize(_card(1)).height;
      expect(short, tall);
    });

    testWidgets('an item is at most 85 percent of a phone-width track', (
      tester,
    ) async {
      _usePhoneSize(tester);
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel([Text("One")], 640)',
      );
      expect(
        tester.getSize(_sizedBoxAround(tester, 'One')).width,
        closeTo(312.8, 0.5),
      );
    });

    testWidgets(
      'Next shows on a macOS carousel with overflow, Previous does not',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await pumpProgram(
          tester,
          'root = Col([c])\n'
          'c = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])',
        );
        await tester.pumpAndSettle();
        expect(_arrow('Next'), findsOneWidget);
        expect(_arrow('Previous'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'tapping Next pages 85 percent of the viewport, clamped to the end',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await pumpProgram(
          tester,
          'root = Col([c])\n'
          'c = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])',
        );
        await tester.pumpAndSettle();
        await tester.tap(_arrow('Next'));
        await tester.pumpAndSettle();
        expect(_horizontalPixels(tester), closeTo(480, 0.5));
        expect(_arrow('Previous'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('no arrows show on an android carousel', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpProgram(
        tester,
        'root = Col([c])\n'
        'c = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])',
      );
      await tester.pumpAndSettle();
      expect(_arrow('Next'), findsNothing);
      expect(_arrow('Previous'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'an arrow takes keyboard focus, pages on Enter and frosts what is behind it',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        await pumpProgram(tester, _five);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: _arrow('Next'),
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(_horizontalPixels(tester), closeTo(480, 0.5));
      },
    );

    testWidgets(
      'reduced motion turns off the arrow fade',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpProgram(tester, _five);
        await tester.pumpAndSettle();
        final fade = tester.widget<AnimatedContainer>(
          find.descendant(
            of: _arrow('Next'),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(fade.duration, Duration.zero);
      },
    );
  });

  group('Popover', () {
    testWidgets('popping a route removes its open panel', (tester) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Popover(Text("Trigger"), Text("Panel"))])',
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            body: OpenUiView(
              session: p.session,
              builders: intelligentUiBuilders,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trigger'));
      await tester.pump();
      expect(find.text('Panel'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Panel'), findsNothing);
      expect(find.text('Trigger'), findsOneWidget);
    });

    testWidgets(
      'an icon in the trigger sits 4 px after the text, centred on it',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([p])\np = Popover(["Details", Icon("info", "sm")], "x")',
        );
        final text = tester.getRect(find.text('Details'));
        final glyph = tester.getRect(find.byType(Glyph));
        expect(glyph.center.dy, closeTo(text.center.dy, 1));
        expect(glyph.left, closeTo(text.right + 4, 0.5));
      },
    );

    testWidgets('a list of content elements is spaced 8 px apart', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([p])\np = Popover("i", [Text("one"), Text("two")])',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      final gap =
          tester.getRect(find.text('two')).top -
          tester.getRect(find.text('one')).bottom;
      expect(gap, closeTo(8, 0.5));
    });

    testWidgets('scrolling an outer viewport closes a nested popover', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Carousel([Popover("i", "Nested panel")]), '
        'Box([], "col", null, null, null, null, null, null, 1200)])',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Nested panel'), findsOneWidget);
      final outer = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );
      outer.position.jumpTo(100);
      await tester.pumpAndSettle();
      expect(find.text('Nested panel'), findsNothing);
    });

    testWidgets('removing an open nested popover detaches scroll listeners', (
      tester,
    ) async {
      final program = await pumpProgram(
        tester,
        'root = Col([Carousel([Popover("i", "Nested panel")]), '
        'Box([], "col", null, null, null, null, null, null, 1200)])',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Nested panel'), findsOneWidget);
      final outer = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );
      program.session.update(
        'root = Col([Text("Ready"), '
        'Box([], "col", null, null, null, null, null, null, 1200)])',
        streaming: false,
      );
      await tester.pumpAndSettle();
      outer.position.jumpTo(100);
      await tester.pumpAndSettle();
      expect(find.text('Nested panel'), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
      expect(outer.position.pixels, 100);
    });

    testWidgets('Escape closes the panel', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([p])\np = Popover("i", "Escape me")',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Escape me'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Escape me'), findsNothing);
    });

    testWidgets('scrolling the page closes the panel', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([p, b])\n'
        'p = Popover("i", "Scroll me away")\n'
        'b = Box([], "col", null, null, null, null, null, null, 700)',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Scroll me away'), findsOneWidget);
      tester
          .state<ScrollableState>(
            find.byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            ),
          )
          .position
          .jumpTo(20);
      await tester.pumpAndSettle();
      expect(find.text('Scroll me away'), findsNothing);
    });

    testWidgets('the panel is clamped to 12 px from the phone edge', (
      tester,
    ) async {
      _usePhoneSize(tester);
      await pumpProgram(
        tester,
        'root = Row([Spacer(), p])\np = Popover("i", "Right side")',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(tester.getRect(_panel()).left, closeTo(108, 0.5));
    });

    testWidgets(
      'the panel opens above the trigger when there is no room below',
      (tester) async {
        _usePhoneSize(tester);
        await pumpProgram(
          tester,
          'root = Col([b, p])\n'
          'b = Box([], "col", null, null, null, null, null, null, 700)\n'
          'p = Popover("i", "Above")',
        );
        await tester.tap(find.text('i'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_panel()).bottom,
          closeTo(tester.getRect(find.text('i')).top - 8, 0.5),
        );
      },
    );

    testWidgets(
      'a tap outside the panel closes it and still reaches a Button',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = Col([Button("Go", @ToAssistant("Hi")), p])\n'
          'p = Popover("i", "Outside")',
        );
        await tester.tap(find.text('i'));
        await tester.pumpAndSettle();
        expect(find.text('Outside'), findsOneWidget);
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();
        expect(find.text('Outside'), findsNothing);
        expect(pumped.events.map((e) => e.type), [
          ActionEvent.continueConversation,
        ]);
      },
    );

    testWidgets('the trigger takes keyboard focus and opens on Enter', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Popover("Term", "Meaning")])');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Meaning'), findsOneWidget);
    });

    testWidgets('the trigger stays on one line; its text wraps beside the icon', (
      tester,
    ) async {
      _usePhoneSize(tester);
      final long = 'word ' * 30;
      await pumpProgram(
        tester,
        'root = Col([Popover([Text("$long"), Icon("info", "sm")], "Meaning")])',
      );
      expect(
        tester.getCenter(find.byType(Glyph)).dy,
        closeTo(tester.getCenter(find.textContaining('word')).dy, 0.5),
      );
      // The text takes the row less the icon and gap (350px), not half of it.
      expect(
        tester.getSize(find.textContaining('word')).width,
        greaterThan(300),
      );
    });

    testWidgets('the open panel is a dialog', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(tester, 'root = Col([Popover("Term", "Meaning")])');
      await tester.tap(find.text('Term'));
      await tester.pumpAndSettle();
      var node = tester.getSemantics(find.text('Meaning'));
      while (node.role != SemanticsRole.dialog && node.parent != null) {
        node = node.parent!;
      }
      expect(node.role, SemanticsRole.dialog);
      handle.dispose();
    });
  });
}
