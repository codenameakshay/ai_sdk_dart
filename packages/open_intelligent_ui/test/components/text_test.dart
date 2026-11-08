import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

Finder _circles() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).shape == BoxShape.circle,
);

Finder _connectors() => find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == OpenUiTheme.light.borderStrong,
);

Finder _headers(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.header == true,
  ),
);

Color? _decorationColor(WidgetTester tester, String text) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
  );
  return (container.decoration! as BoxDecoration).color;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Color? _ink(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

void main() {
  const titleSizes = <String, (double, double, double)>{
    'sm': (15, 1.5, 0),
    'md': (17, 1.4, -0.2),
    'lg': (21, 1.3, -0.55),
    'xl': (25, 1.2, -0.8),
    '2xl': (32, 1.15, -1),
    '3xl': (40, 1.1, -1.4),
  };
  for (final MapEntry(key: size, value: (fontSize, height, spacing))
      in titleSizes.entries) {
    testWidgets('Title size $size uses the reference metrics', (tester) async {
      await pumpProgram(tester, 'root = Col([Title("Size $size", "$size")])');
      final style = tester.widget<Text>(find.text('Size $size')).style!;
      expect(style.fontSize, fontSize);
      expect(style.height, height);
      expect(style.letterSpacing, spacing);
      expect(style.fontWeight, OpenUiTheme.weightSemibold);
    });
  }

  testWidgets('on a phone lg, 2xl and 3xl titles shrink; card titles stay 18', (
    tester,
  ) async {
    _phone(tester);
    await pumpProgram(
      tester,
      'root = Col([Title("L", "lg"), Title("X", "xl"), Title("D", "2xl"), '
      'Title("T", "3xl"), Card([Title("C", "2xl")])])',
    );
    double size(String t) => tester.widget<Text>(find.text(t)).style!.fontSize!;
    expect(
      [size('L'), size('X'), size('D'), size('T'), size('C')],
      [19, 25, 28, 34, 18],
    );
  });

  testWidgets('Title without a size is md and takes a model color', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Title("Plain"), Title("Alert", "lg", "danger")])',
    );
    final plain = tester.widget<Text>(find.text('Plain')).style!;
    expect(plain.fontSize, 17);
    expect(plain.color, OpenUiTheme.light.ink);
    final alert = tester.widget<Text>(find.text('Alert')).style!;
    expect(alert.fontSize, 21);
    expect(alert.color, OpenUiTheme.light.status['danger']);
  });

  testWidgets('Title is a header for assistive technology', (tester) async {
    await pumpProgram(tester, 'root = Col([Title("Heading", "xl")])');
    expect(_headers('Heading'), findsOneWidget);
  });

  testWidgets('Text sizes and default metrics', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text("Extra small", "xs"), Text("Small", "sm"), '
      'Text("Medium", "md"), Text("Large", "lg"), Text("Plain")])',
    );
    expect(tester.widget<Text>(find.text('Extra small')).style!.fontSize, 12);
    expect(tester.widget<Text>(find.text('Small')).style!.fontSize, 14);
    expect(tester.widget<Text>(find.text('Medium')).style!.fontSize, 16);
    expect(tester.widget<Text>(find.text('Large')).style!.fontSize, 18);
    final plain = tester.widget<Text>(find.text('Plain')).style!;
    expect(plain.fontSize, isNull);
    expect(plain.height, 1.6);
    expect(plain.color, isNull);
    expect(_ink(tester, 'Plain'), OpenUiTheme.light.ink);
  });

  testWidgets('Text without a color takes the hovered popover trigger color', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([Popover(Text("Term"), "Meaning")])');
    expect(_ink(tester, 'Term'), OpenUiTheme.light.ink);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Term')));
    await tester.pump();
    expect(_ink(tester, 'Term'), OpenUiTheme.light.muted);
  });

  testWidgets('Text applies color, weight and decoration props', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Text("Styled", null, "danger", "semibold", true, true, true), '
      'Text("Light", null, null, "normal"), Text("Middle", null, null, "medium")])',
    );
    final styled = tester.widget<Text>(find.text('Styled')).style!;
    expect(styled.color, OpenUiTheme.light.status['danger']);
    expect(styled.fontWeight, OpenUiTheme.weightSemibold);
    expect(styled.fontStyle, FontStyle.italic);
    expect(styled.decoration, TextDecoration.lineThrough);
    expect(styled.fontFeatures, const [FontFeature.tabularFigures()]);
    expect(
      tester.widget<Text>(find.text('Light')).style!.fontWeight,
      OpenUiTheme.weightNormal,
    );
    expect(
      tester.widget<Text>(find.text('Middle')).style!.fontWeight,
      OpenUiTheme.weightMedium,
    );
  });

  testWidgets('Text renders inline Markdown', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text("**Bold** and *soft* and `code`")])',
    );
    expect(find.text('Bold and soft and ￼'), findsOneWidget);
    expect(find.text('code'), findsOneWidget);
  });

  testWidgets('Text keeps line breaks from the model', (tester) async {
    await pumpProgram(tester, 'root = Col([Text("First line\\nSecond line")])');
    expect(find.text('First line\nSecond line'), findsOneWidget);
  });

  testWidgets('Text clamps to maxLines with an ellipsis', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text("Clamped", null, null, null, false, false, false, 2.4), '
      'Text("Open", null, null, null, false, false, false, 0)])',
    );
    final clamped = tester.widget<Text>(find.text('Clamped'));
    expect(clamped.maxLines, 2);
    expect(clamped.overflow, TextOverflow.ellipsis);
    final open = tester.widget<Text>(find.text('Open'));
    expect(open.maxLines, isNull);
    expect(open.overflow, isNull);
  });

  testWidgets('Text list mixes strings, numbers, nulls and Badges', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Text(["Ready ", Badge("Easy", "success"), " 25 min"]), '
      'Text(["Count ", 4, " left"])])',
    );
    expect(find.textContaining('Ready'), findsOneWidget);
    expect(find.text('Easy'), findsOneWidget);
    expect(
      _decorationColor(tester, 'Easy'),
      OpenUiTheme.light.badgeSoft['success'],
    );
    expect(find.text('Count 4 left'), findsOneWidget);
  });

  testWidgets('a Text whose text is not a string or list shows no text', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([Text(5)])');
    expect(find.text('5'), findsNothing);
  });

  testWidgets('Caption is small and muted, with a model color override', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Caption("Muted note"), Caption("Good note", "success")])',
    );
    final muted = tester.widget<Text>(find.text('Muted note')).style!;
    expect(muted.fontSize, 12);
    expect(muted.height, 1.6);
    expect(muted.color, OpenUiTheme.light.muted);
    expect(
      tester.widget<Text>(find.text('Good note')).style!.color,
      OpenUiTheme.light.status['success'],
    );
  });

  testWidgets('Label is 14 medium in ink', (tester) async {
    await pumpProgram(tester, 'root = Col([Label("Field name")])');
    final style = tester.widget<Text>(find.text('Field name')).style!;
    expect(style.fontSize, 14);
    expect(style.height, 1.4);
    expect(style.fontWeight, OpenUiTheme.weightMedium);
    expect(style.color, OpenUiTheme.light.ink);
  });

  testWidgets('Badge neutral by default, with no icon', (tester) async {
    await pumpProgram(tester, 'root = Col([Badge("Plain")])');
    expect(
      _decorationColor(tester, 'Plain'),
      OpenUiTheme.light.badgeNeutralSoft,
    );
    expect(
      tester.widget<Text>(find.text('Plain')).style!.color,
      OpenUiTheme.light.ink,
    );
    expect(find.byType(Glyph), findsNothing);
  });

  testWidgets('Badge info uses the status tint and an icon', (tester) async {
    await pumpProgram(tester, 'root = Col([Badge("Clock", "info", "clock")])');
    expect(
      _decorationColor(tester, 'Clock'),
      OpenUiTheme.light.statusSoft['info'],
    );
    expect(
      tester.widget<Text>(find.text('Clock')).style!.color,
      OpenUiTheme.light.status['info'],
    );
    expect(find.byType(Glyph), findsOneWidget);
  });

  testWidgets('a Badge icon sits 8px in, 2px left of the text padding', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([Badge("Clock", "info", "clock")])');
    final badge = find
        .ancestor(of: find.text('Clock'), matching: find.byType(Container))
        .first;
    expect(
      tester.getTopLeft(find.byType(Glyph)).dx - tester.getTopLeft(badge).dx,
      8,
    );
  });

  testWidgets('Badge takes status colors and skips an unknown icon', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Badge("Done", "success", "no-such-icon")])',
    );
    expect(
      _decorationColor(tester, 'Done'),
      OpenUiTheme.light.badgeSoft['success'],
    );
    expect(
      tester.widget<Text>(find.text('Done')).style!.color,
      OpenUiTheme.light.badge['success'],
    );
    expect(find.byType(Glyph), findsNothing);
  });

  testWidgets('Badge in dark mode uses the dark status tokens', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Title("Night", "md"), Badge("Dark", "success"), Text("Body")])',
      brightness: Brightness.dark,
    );
    expect(
      tester.widget<Text>(find.text('Night')).style!.color,
      OpenUiTheme.dark.ink,
    );
    expect(
      _decorationColor(tester, 'Dark'),
      OpenUiTheme.dark.badgeSoft['success'],
    );
    expect(
      tester.widget<Text>(find.text('Dark')).style!.color,
      OpenUiTheme.dark.badge['success'],
    );
    expect(_ink(tester, 'Body'), OpenUiTheme.dark.ink);
  });

  testWidgets('Link opens an http URL when tapped', (tester) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([Link("Bureau of Economic Analysis", "https://www.bea.gov")])',
    );
    expect(find.byType(Glyph), findsOneWidget);
    await tester.tap(find.textContaining('Bureau of Economic Analysis'));
    await tester.pump();
    expect(pumped.opened, [Uri.parse('https://www.bea.gov')]);
  });

  testWidgets('Link without text shows the host name', (tester) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([Link("", "https://www.bea.gov/data")])',
    );
    expect(find.textContaining('www.bea.gov'), findsOneWidget);
    await tester.tap(find.textContaining('www.bea.gov'));
    await tester.pump();
    expect(pumped.opened, [Uri.parse('https://www.bea.gov/data')]);
  });

  testWidgets('Link underline turns to the text color on hover', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Link("Hover me", "https://example.com")])',
    );
    final resting = tester.widget<Text>(find.textContaining('Hover me')).style!;
    expect(resting.decorationColor, OpenUiTheme.light.borderStrong);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.textContaining('Hover me')));
    await tester.pump();
    final hovered = tester.widget<Text>(find.textContaining('Hover me')).style!;
    expect(hovered.decorationColor, resting.color);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.textContaining('Hover me'))
          .style!
          .decorationColor,
      OpenUiTheme.light.borderStrong,
    );
  });

  testWidgets('Link takes keyboard focus and opens on Enter', (tester) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([Link("Docs", "https://example.com/a")])',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pumped.opened, [Uri.parse('https://example.com/a')]);
  });

  testWidgets('Link with a non-http URL is plain text and does not open', (
    tester,
  ) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([Link("Unsafe link", "javascript:alert(1)")])',
    );
    expect(find.text('Unsafe link'), findsOneWidget);
    expect(find.byType(Glyph), findsNothing);
    await tester.tap(find.text('Unsafe link'));
    await tester.pump();
    expect(pumped.opened, isEmpty);
  });

  testWidgets('a bullet List draws one dot per item', (tester) async {
    await pumpProgram(tester, 'root = Col([List(["One", "Two", "Three"])])');
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(_circles(), findsNWidgets(3));
    expect(_connectors(), findsNothing);
    final first = tester.getTopLeft(find.text('One')).dx;
    expect(tester.getTopLeft(find.text('Two')).dx, first);
  });

  testWidgets('a number List numbers its items', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([List(["First", "Second"], "number")])',
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(_circles(), findsNWidgets(2));
  });

  testWidgets('number circles are 24px, also around a step chip', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List(["a", "b"], "number"), List([ListItem("Prep", null, "A")], "number")])',
    );
    expect(
      tester.getSize(
        find
            .ancestor(of: find.text('1'), matching: find.byType(Container))
            .first,
      ),
      const Size(24, 24),
    );
    expect(
      find.ancestor(
        of: find.text('A'),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 24 && w.height == 24,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a none List has no markers', (tester) async {
    await pumpProgram(tester, 'root = Col([List(["Plain"], "none")])');
    expect(find.text('Plain'), findsOneWidget);
    expect(_circles(), findsNothing);
  });

  testWidgets('List items take inline Markdown, numbers and nested lists', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List(["**Bold** item", 4, null, ["Nested"]])])',
    );
    expect(find.text('Bold item'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Nested'), findsOneWidget);
  });

  testWidgets('a timeline joins the markers with a line between items', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List(["Start", "Middle", "End"], "bullet", true)])',
    );
    expect(_connectors(), findsNWidgets(2));
    expect(_circles(), findsNWidgets(3));
  });

  testWidgets('a timeline with no markers draws no line', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([List(["Start", "End"], "none", true)])',
    );
    expect(find.text('Start'), findsOneWidget);
    expect(_connectors(), findsNothing);
  });

  testWidgets('a number timeline keeps its numbers', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([List(["Start", "Middle", "End"], "number", true)])',
    );
    expect(_connectors(), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('ListItem markers: short steps are chips, longer ones are text', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List([ListItem("Prepare", "", "A"), ListItem("Cook", "", "★")])])',
    );
    expect(find.text('A'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('A')).style!.color,
      OpenUiTheme.light.onInk,
    );
    expect(find.text('★'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('★')).style!.color,
      OpenUiTheme.light.muted,
    );
    final titleLeft = tester.getTopLeft(find.text('Prepare')).dx;
    expect(tester.getCenter(find.text('A')).dx, closeTo(titleLeft - 24, 0.5));
  });

  testWidgets('a time marker gets a wide lane', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([List([ListItem("Prepare", "", "10:45 AM"), '
      'ListItem("Serve", "", "1:00 PM")])])',
    );
    expect(find.text('10:45 AM'), findsOneWidget);
    final markTop = tester.getTopLeft(find.text('10:45 AM')).dx;
    final titleTop = tester.getTopLeft(find.text('Prepare')).dx;
    expect(titleTop - markTop, closeTo(92, 0.5));
  });

  testWidgets('a timeline with time markers draws lines in the wide lane', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List([ListItem("Prepare", "", "10:45 AM"), '
      'ListItem("Serve", "", "1:00 PM")], "bullet", true)])',
    );
    expect(_connectors(), findsOneWidget);
    expect(find.text('Serve'), findsOneWidget);
  });

  testWidgets('on a phone a wide list lane is 64px with a 20px gap', (
    tester,
  ) async {
    _phone(tester);
    await pumpProgram(
      tester,
      'root = Col([List([ListItem("Arrive", null, "09:00"), ListItem("Leave", null, "11:30")], "bullet", true)])',
    );
    expect(tester.getTopLeft(find.text('Arrive')).dx, 16 + 64 + 20);
    expect(tester.getTopLeft(_connectors()).dx, 16 + 73);
    final ring = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border ==
              Border.all(color: OpenUiTheme.light.ink, width: 2),
    );
    expect(tester.getTopLeft(ring.first).dx, 16 + 70);
  });

  testWidgets('a List is a list of list items for assistive technology', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(tester, 'root = Col([List(["Milk", "Eggs"])])');
    final item = tester.getSemantics(find.text('Milk'));
    expect(item.role, SemanticsRole.listItem);
    expect(item.parent!.role, SemanticsRole.list);
    handle.dispose();
  });

  testWidgets('a ListItem shows its title, description and children', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([List([ListItem("Pack", "Bring tools", "1", [Text("Note inside")])], "number")])',
    );
    expect(find.text('Pack'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Pack')).style!.fontWeight,
      OpenUiTheme.weightMedium,
    );
    final description = tester.widget<Text>(find.text('Bring tools')).style!;
    expect(description.color, OpenUiTheme.light.muted);
    expect(find.text('Note inside'), findsOneWidget);
    expect(_circles(), findsNothing);
  });

  testWidgets('a ListItem on its own is a plain title and description', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([ListItem("Solo", "Desc")])');
    expect(tester.widget<Text>(find.text('Solo')).style!.fontWeight, isNull);
    expect(find.text('Desc'), findsOneWidget);
  });

  testWidgets('a ListItem with only a title has no description', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([ListItem("Only title")])');
    expect(find.text('Only title'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('a ListItem drops medium weight when its row stops being rich', (
    tester,
  ) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([List([ListItem("Pack", "Bring tools")])])',
    );
    expect(
      tester.widget<Text>(find.text('Pack')).style!.fontWeight,
      OpenUiTheme.weightMedium,
    );
    pumped.session.update(
      'root = Col([List([ListItem("Pack")])])',
      streaming: false,
    );
    await tester.pump();
    expect(tester.widget<Text>(find.text('Pack')).style!.fontWeight, isNull);
  });
}
