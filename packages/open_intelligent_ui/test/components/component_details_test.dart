import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/css_color.dart';

import '../support/pump.dart';

const _carouselOfFive =
    'root = Col([c])\n'
    'c = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])';

Finder _arrow(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

double _horizontalPixels(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.horizontal,
      ),
    )
    .position
    .pixels;

int? _arrowFillArgb(WidgetTester tester, String label) {
  final box = tester.widget<Container>(
    find.descendant(of: _arrow(label), matching: find.byType(Container)).first,
  );
  return (box.decoration! as BoxDecoration).color?.toARGB32();
}

int? _textArgb(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color
    ?.toARGB32();

CustomPainter _shimmerPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('iui-shimmer')),
        matching: find.byType(CustomPaint),
      ),
    )
    .painter!;

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  group('Carousel arrows', () {
    testWidgets('Previous pages back to the start after Next has scrolled', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpProgram(tester, _carouselOfFive);
      await tester.pumpAndSettle();
      await tester.tap(_arrow('Next'));
      await tester.pumpAndSettle();
      expect(_horizontalPixels(tester), closeTo(480, 0.5));

      await tester.tap(_arrow('Previous'));
      await tester.pumpAndSettle();
      expect(_horizontalPixels(tester), closeTo(0, 0.5));
      expect(_arrow('Previous'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'hovering a carousel arrow changes its fill, and leaving restores it',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await pumpProgram(tester, _carouselOfFive);
        await tester.pumpAndSettle();
        expect(_arrowFillArgb(tester, 'Next'), 0xB3FDFDFD);

        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(_arrow('Next')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(_arrowFillArgb(tester, 'Next'), 0x0A030303);

        await mouse.moveTo(const Offset(1, 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(_arrowFillArgb(tester, 'Next'), 0xB3FDFDFD);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });

  group('Popover', () {
    testWidgets('tapping the trigger of an open popover closes it', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([p])\np = Popover("i", "Toggle me")',
      );
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Toggle me'), findsOneWidget);

      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Toggle me'), findsNothing);
    });

    testWidgets(
      'hovering a popover trigger mutes its text, and leaving restores it',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([p])\np = Popover("i", "Hover me")',
        );
        final resting = _textArgb(tester, 'i');

        final mouse = await _mouse(tester);
        await mouse.moveTo(tester.getCenter(find.text('i')));
        await tester.pump();
        expect(_textArgb(tester, 'i'), 0x99030303);

        await mouse.moveTo(const Offset(1, 1));
        await tester.pump();
        expect(_textArgb(tester, 'i'), resting);
      },
    );
  });

  group('Shimmer', () {
    testWidgets('a shimmer repaints when the theme brightness changes', (
      tester,
    ) async {
      OpenUiServices loading() => OpenUiServices(
        searchImages: (_) => Completer<List<Uri>>().future,
        mapTiles: null,
      );
      await pumpProgram(
        tester,
        'root = SearchImage("a red bicycle")',
        services: loading(),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final lightPainter = _shimmerPainter(tester);

      await pumpProgram(
        tester,
        'root = SearchImage("a red bicycle")',
        brightness: Brightness.dark,
        services: loading(),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(_shimmerPainter(tester).shouldRepaint(lightPainter), isTrue);
    });
  });

  group('Flashcard', () {
    testWidgets('the hidden face under a flashcard takes no hits', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Flashcard("Front", "Back")])');
      final ghost = tester.renderObject<RenderBox>(
        find
            .byWidgetPredicate((w) => w.runtimeType.toString() == '_Ghost')
            .last,
      );
      final result = BoxHitTestResult();
      final hit = ghost.hitTest(
        result,
        position: ghost.size.center(Offset.zero),
      );
      expect(hit, isFalse);
      expect(result.path, isEmpty);
    });
  });

  group('OpenUiFormValidation', () {
    test('an unregistered field no longer fails the form', () {
      final validation = OpenUiFormValidation();
      addTearDown(validation.dispose);
      validation.registerField('a', const [ParsedRule('required')], () => '');
      validation.unregisterField('a');

      expect(validation.validateForm(), isTrue);
      expect(validation.errors, isEmpty);
    });
  });

  group('color-mix', () {
    test('a percentage on the second colour sets the first colour weight', () {
      expect(
        parseCssColor('color-mix(in srgb, #000000, #ffffff 20%)')!.toARGB32(),
        0xFF333333,
      );
    });

    test('mixing in srgb-linear, 30% white is 149 in sRGB', () {
      expect(
        parseCssColor(
          'color-mix(in srgb-linear, #ffffff 30%, #000000)',
        )!.toARGB32(),
        0xFF959595,
      );
    });

    test('mixing in oklab, 30% white is 46 in sRGB', () {
      expect(
        parseCssColor('color-mix(in oklab, #ffffff 30%, #000000)')!.toARGB32(),
        0xFF2E2E2E,
      );
    });

    test(
      'mixColors rejects a colour space that color-mix does not support',
      () {
        expect(
          () => mixColors(
            const Color(0xFFFFFFFF),
            0.5,
            const Color(0xFF000000),
            space: 'hsl',
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
