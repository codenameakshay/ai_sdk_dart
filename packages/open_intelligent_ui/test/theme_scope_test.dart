import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/components.dart' show OutlineGlyph;

import 'support/pump.dart';

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('a host onInk reaches solid button text, toned or not', (
    tester,
  ) async {
    const onInk = Color(0xFFEEDDCC);
    await pumpProgram(
      tester,
      'root = Col([Button("Plain"), Button("Pay", null, "solid", "danger")])',
      theme: OpenUiTheme.light.copyWith(onInk: onInk),
    );
    await tester.pumpAndSettle();
    expect(_textColor(tester, 'Plain'), onInk);
    expect(_textColor(tester, 'Pay'), onInk);
  });

  testWidgets('named tokens colour the checkmark, chevron and toned text', (
    tester,
  ) async {
    const onTone = Color(0xFF112233);
    const checkInk = Color(0xFF445566);
    const chevron = Color(0xFF778899);
    await pumpProgram(
      tester,
      'root = Col([Button("Pay", null, "solid", "success"), Pressable([Text("Pick")], null, true), Select(\$v, [{value: "a", label: "A"}])])\n\$v = "a"',
      theme: OpenUiTheme.light.copyWith(
        onTone: onTone,
        checkInk: checkInk,
        chevron: chevron,
      ),
    );
    await tester.pumpAndSettle();
    expect(_textColor(tester, 'Pay'), onTone);
    final dropdown = tester.widget<DropdownButton<int>>(
      find.byType(DropdownButton<int>),
    );
    expect((dropdown.icon! as Glyph).color, chevron);
    final check = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(Stack),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.size == const Size.square(12),
            ),
          )
          .first,
    );
    expect((check.painter! as dynamic).color, checkInk);
  });

  testWidgets('OpenUiThemeScope themes a view with no Material Theme above', (
    tester,
  ) async {
    final session = OpenUiSession(intelligentUi)
      ..update('root = Text("plain")', streaming: false);
    addTearDown(session.dispose);
    final theme = OpenUiTheme.dark.copyWith(ink: const Color(0xFF0A7E3D));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OpenUiThemeScope(
          theme: theme,
          child: OpenUiView(session: session, builders: intelligentUiBuilders),
        ),
      ),
    );
    expect(find.byType(Theme), findsNothing);
    final text = tester.renderObject<RenderParagraph>(find.text('plain'));
    expect(text.text.style?.color, theme.ink);
  });

  testWidgets('with no text colour around it, a Glyph takes the theme ink', (
    tester,
  ) async {
    final theme = OpenUiTheme.light.copyWith(ink: const Color(0xFF7A1F5C));
    final session = OpenUiSession(intelligentUi)
      ..update(
        'root = Svg([Circle(60, 40, 30, "#2563eb")], "0 0 120 80")',
        streaming: false,
      );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OpenUiThemeScope(
          theme: theme,
          child: Column(
            children: [
              const Glyph('check'),
              OpenUiView(session: session, builders: intelligentUiBuilders),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.widget<OutlineGlyph>(find.byType(OutlineGlyph)).color,
      theme.ink,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('OpenUiThemeScope wins over the Material theme extension', (
    tester,
  ) async {
    late OpenUiTheme seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [OpenUiTheme.light]),
        home: OpenUiThemeScope(
          theme: OpenUiTheme.dark,
          child: Builder(
            builder: (context) {
              seen = OpenUiTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen, same(OpenUiTheme.dark));
  });

  testWidgets(
    'the iOS date popup in a dark subtree of a light app is legible',
    (tester) async {
      Impure.now = () => DateTime.utc(2030, 5, 17, 12);
      Impure.useUtc();
      addTearDown(Impure.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpProgram(
          tester,
          'root = DatePicker("")',
          theme: OpenUiTheme.dark,
        );
        await tester.tap(find.bySemanticsLabel('Date'));
        await tester.pumpAndSettle();
        final year = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(CupertinoDatePicker),
            matching: find.text('2030'),
          ),
        );
        final color = year.text.style!.color!;
        expect(
          _contrast(color, OpenUiTheme.dark.canvas),
          greaterThanOrEqualTo(4.5),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('the Material date picker takes the scoped theme', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = DatePicker("")', theme: OpenUiTheme.dark);
    await tester.tap(find.bySemanticsLabel('Date'));
    await tester.pumpAndSettle();
    final dialog = tester.element(find.byType(DatePickerDialog));
    final scheme = Theme.of(dialog).colorScheme;
    expect(scheme.brightness, Brightness.dark);
    expect(scheme.surface, OpenUiTheme.dark.canvas);
    expect(scheme.primary, OpenUiTheme.dark.ink);
    expect(OpenUiTheme.of(dialog).canvas, OpenUiTheme.dark.canvas);
  });

  testWidgets('tooltips, text selection and retry take the theme', (
    tester,
  ) async {
    final theme = OpenUiTheme.dark;
    await pumpProgram(
      tester,
      'root = Col([IconButton("plus", null, "Add"), Input(\$n, "Name")])\n\$n = ""',
      theme: theme,
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect((tooltip.decoration! as BoxDecoration).color, theme.ink);
    expect(tooltip.textStyle?.color, theme.onInk);
    final selection = DefaultSelectionStyle.of(
      tester.element(find.byType(EditableText)),
    );
    expect(selection.cursorColor, theme.ink);
    expect(selection.selectionColor, theme.selection);
  });

  testWidgets('a per-component font size reaches the component', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Pay"), Text("plain")])',
      theme: OpenUiTheme.light.copyWith(
        components: const {'Button': OpenUiComponentStyle(fontSize: 21)},
      ),
    );
    expect(tester.widget<Text>(find.text('Pay')).style?.fontSize, 21);
  });

  testWidgets('the tabularNums flag sets tabular figures on all text', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Text("1,234"), Row(["5,678"])])',
      theme: OpenUiTheme.light.copyWith(
        typography: const OpenUiTypography(tabularNums: true),
      ),
    );
    for (final text in ['1,234', '5,678']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final features = <FontFeature>[];
      paragraph.text.visitChildren((span) {
        features.addAll(span.style?.fontFeatures ?? const []);
        return true;
      });
      features.addAll(
        DefaultTextStyle.of(
              tester.element(find.text(text)),
            ).style.fontFeatures ??
            const [],
      );
      expect(features, contains(const FontFeature.tabularFigures()));
    }
  });

  test('copyWith changes brightness, and derived tokens follow', () {
    final theme = OpenUiTheme.light.copyWith(
      brightness: Brightness.dark,
      onInk: const Color(0xFF010203),
      muted: const Color(0xFF040506),
      shadowSmall: const [BoxShadow(blurRadius: 1)],
    );
    expect(theme.brightness, Brightness.dark);
    expect(theme.onTone, const Color(0xFF010203));
    expect(theme.checkInk, const Color(0xFF010203));
    expect(theme.chevron, const Color(0xFF040506));
    expect(theme.floatShadow, const [BoxShadow(blurRadius: 1)]);
    final kept = OpenUiTheme.light.copyWith(canvas: const Color(0xFFFFFFFF));
    expect(kept.onTone, OpenUiTheme.light.onTone);
    expect(kept.brightness, Brightness.light);
  });
}
