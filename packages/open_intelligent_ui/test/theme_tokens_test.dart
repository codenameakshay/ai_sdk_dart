import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/components.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

BoxDecoration? _decorationOf(Widget w) {
  final decoration = switch (w) {
    Container(:final decoration) => decoration,
    DecoratedBox(:final decoration) => decoration,
    _ => null,
  };
  return decoration is BoxDecoration ? decoration : null;
}

BoxDecoration _decorationAbove(WidgetTester tester, String text) {
  final ancestors = find.ancestor(
    of: find.text(text),
    matching: find.byWidgetPredicate((w) => _decorationOf(w) != null),
  );
  return _decorationOf(tester.widget(ancestors.first))!;
}

void main() {
  test('defaults are the reference values', () {
    final theme = OpenUiTheme.light;
    expect(theme.radii.lg, OpenUiTheme.radiusLg);
    expect(theme.spacing.group, OpenUiTheme.spaceGroup);
    expect(theme.typography.medium, OpenUiTheme.weightMedium);
    expect(theme.typography.text['sm']!.fontSize, 14);
  });

  testWidgets('radii drive the Card corner', (tester) async {
    await pumpProgram(
      tester,
      'root = Card([Text("body")])',
      theme: OpenUiTheme.light.copyWith(radii: const OpenUiRadii(xl: 3)),
    );
    expect(
      _decorationAbove(tester, 'body').borderRadius,
      BorderRadius.circular(3),
    );
  });

  testWidgets('spacing.unit scales model gaps', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text("a"), Text("b")], 2)',
      theme: OpenUiTheme.light.copyWith(spacing: const OpenUiSpacing(unit: 5)),
    );
    final gap =
        tester.getRect(find.text('b')).top -
        tester.getRect(find.text('a')).bottom;
    expect(gap, closeTo(10, 0.5));
  });

  testWidgets('type.scale scales built-in sizes', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Table(["A"], [["x"]]), Text("sm", "sm")])',
      theme: OpenUiTheme.light.copyWith(
        typography: const OpenUiTypography(scale: 2),
      ),
    );
    expect(tester.widget<Text>(find.text('A')).style?.fontSize, 26);
    expect(tester.widget<Text>(find.text('sm')).style?.fontSize, 28);
  });

  testWidgets('tabularFigures false drops tabular figures', (tester) async {
    List<FontFeature>? features() => tester
        .renderObject<RenderParagraph>(find.text('1.5'))
        .text
        .style
        ?.fontFeatures;
    const program = 'root = Col([Table(["Amount"], [[1.5]])])';
    await pumpProgram(tester, program);
    expect(features(), const [FontFeature.tabularFigures()]);
    await pumpProgram(
      tester,
      program,
      theme: OpenUiTheme.light.copyWith(
        typography: const OpenUiTypography(tabularFigures: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(features(), isNull);
  });

  testWidgets('component styles restyle Card, Button, Badge and Table', (
    tester,
  ) async {
    final theme = OpenUiTheme.light.copyWith(
      components: const {
        'Card': OpenUiComponentStyle(background: Colors.red, radius: 2),
        'Button.outline': OpenUiComponentStyle(border: Colors.green),
        'Badge': OpenUiComponentStyle(background: Colors.blue),
        'Table': OpenUiComponentStyle(radius: 0),
      },
    );

    await pumpProgram(tester, 'root = Card([Text("body")])', theme: theme);
    final card = _decorationAbove(tester, 'body');
    expect(card.color, Colors.red);
    expect(card.borderRadius, BorderRadius.circular(2));

    await pumpProgram(
      tester,
      'root = Col([Button("Go", null, "outline")])',
      theme: theme,
    );
    expect(
      (_decorationAbove(tester, 'Go').border! as Border).top.color,
      Colors.green,
    );

    await pumpProgram(tester, 'root = Col([Badge("New")])', theme: theme);
    expect(_decorationAbove(tester, 'New').color, Colors.blue);

    await pumpProgram(
      tester,
      'root = Col([Table(["A"], [["x"]])])',
      theme: theme,
    );
    expect(
      _decorationAbove(tester, 'x').borderRadius,
      BorderRadius.circular(0),
    );
  });

  test('fromColorScheme maps the scheme', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final theme = OpenUiTheme.fromColorScheme(scheme);
    expect(theme.canvas, scheme.surface);
    expect(theme.ink, scheme.onSurface);
    expect(theme.status['danger'], scheme.error);
    expect(theme.fontFamily, isNull);
  });

  test("fromMaterial takes the text theme's font", () {
    final theme = OpenUiTheme.fromMaterial(ThemeData(fontFamily: 'Roboto'));
    expect(theme.fontFamily, 'Roboto');
  });

  testWidgets('a host can wrap a stock builder', (tester) async {
    final builders = composeBuilders([
      {
        'Card': (context, node) => Container(
          key: const ValueKey('wrapper'),
          child: buildCard(context, node),
        ),
      },
    ]);
    final session = OpenUiSession(intelligentUi, initialState: const {})
      ..update('root = Card([Text("body")])', streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiView(session: session, builders: builders),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('wrapper')), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
  });
}
