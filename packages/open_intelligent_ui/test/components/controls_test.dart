import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/css_color.dart' show CssGradient;

import '../support/pump.dart';

Color? _color(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

BoxDecoration _decoration(WidgetTester tester, String text) =>
    tester
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: find.text(text),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  group('Button', () {
    testWidgets('without an action sends its label to the assistant', (
      tester,
    ) async {
      final pumped = await pumpProgram(tester, 'root = Button("Tell me more")');
      await tester.tap(find.text('Tell me more'));
      await tester.pump();
      expect(pumped.events, hasLength(1));
      expect(pumped.events.single.type, ActionEvent.continueConversation);
      expect(pumped.events.single.humanFriendlyMessage, 'Tell me more');
    });

    testWidgets('a @Set action changes state and the page re-renders', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Text("n=" + \$n), Button("Add", @Set(\$n, \$n + 1))])\n\$n = 0',
      );
      expect(find.text('n=0'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 1);
      expect(find.text('n=1'), findsOneWidget);
      expect(pumped.events, isEmpty);
    });

    testWidgets('a disabled button does nothing', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Text("n=" + \$n), Button("Add", @Set(\$n, 1), "solid", null, null, null, true)])\n\$n = 0',
      );
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 0);
      expect(find.text('n=0'), findsOneWidget);
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.4);
    });

    testWidgets('a streaming program does not run buttons', (tester) async {
      final pumped = await pumpProgram(
        tester,
        '\$n = 0\nroot = Col([Button("Add", @Set(\$n, 1))])\nx = 1\n',
        streaming: true,
      );
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 0);
      expect(pumped.events, isEmpty);
    });

    testWidgets('a submit button sends the form name and fields', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([f])\nf = Form([Input("", "Name"), Button("Send", @ToAssistant("Help me", {id: 4}))])',
      );
      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.tap(find.text('Send'));
      await tester.pump();
      final event = pumped.events.single;
      expect(event.humanFriendlyMessage, 'Help me');
      expect(event.formName, 'f');
      expect(event.formState, {
        'f': {
          'Name': {'value': 'Ana'},
        },
      });
    });

    testWidgets('sizes set the minimum height', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("S", null, "solid", null, "sm"), Button("M"), Button("L", null, "solid", null, "lg")])',
      );
      expect(tester.getSize(find.text('S').hitTestable()).height, lessThan(32));
      final sizes = [
        for (final t in ['S', 'M', 'L'])
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(t),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .height,
      ];
      expect(sizes, [32, 36, 44]);
    });

    testWidgets('variants and colors follow the reference', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("A"), Button("B", null, "solid", "danger"), Button("C", null, "outline", "danger"), Button("D", null, "soft", "success"), Button("E", null, "ghost"), Button("F", null, "outline")])',
      );
      final light = OpenUiTheme.light;
      expect(_color(tester, 'A'), light.onInk);
      expect(_decoration(tester, 'A').color, light.ink);
      expect(_color(tester, 'B'), const Color(0xFFFFFFFF));
      expect(_decoration(tester, 'B').color, light.status['danger']);
      expect(_color(tester, 'C'), light.status['danger']);
      expect(_decoration(tester, 'C').border, isNotNull);
      expect(_color(tester, 'D'), light.status['success']);
      expect(_decoration(tester, 'D').color, light.surface);
      expect(_decoration(tester, 'E').color, isNull);
      expect(_color(tester, 'E'), light.ink);
      expect(_color(tester, 'F'), light.ink);
    });

    testWidgets('dark mode uses the dark tokens', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("A"), Button("B", null, "solid", "success")])',
        brightness: Brightness.dark,
      );
      expect(_color(tester, 'A'), OpenUiTheme.dark.onInk);
      expect(_decoration(tester, 'A').color, OpenUiTheme.dark.ink);
      expect(_color(tester, 'B'), const Color(0xFF121212));
      expect(
        _decoration(tester, 'B').color,
        OpenUiTheme.dark.status['success'],
      );
    });

    testWidgets('an icon shows before the label', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("Copy", null, "solid", null, "sm", "copy"), Button("Plain")])',
      );
      final copy = find
          .ancestor(of: find.text('Copy'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: copy, matching: find.byType(Glyph)),
        findsOneWidget,
      );
      final plain = find
          .ancestor(of: find.text('Plain'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: plain, matching: find.byType(Glyph)),
        findsNothing,
      );
    });

    testWidgets('block fills the width and a normal button hugs its label', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Button("Wide", null, "solid", null, null, null, null, true), Button("Narrow")])',
      );
      final view = tester.getSize(find.byType(OpenUiView)).width;
      final wide = find
          .ancestor(of: find.text('Wide'), matching: find.byType(Container))
          .first;
      final narrow = find
          .ancestor(of: find.text('Narrow'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(wide).width, view);
      expect(tester.getSize(narrow).width, lessThan(view / 2));
    });

    testWidgets('hover and the keyboard work', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Button("Go"), Button("Soft", null, "soft"), Button("Out", null, "outline"), Button("Ghost", null, "ghost"), Button("Red", null, "solid", "danger")])',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Go')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'Go').color, OpenUiTheme.light.inkHover);
      await mouse.moveTo(tester.getCenter(find.text('Soft')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'Soft').color, OpenUiTheme.light.pressed);
      await mouse.moveTo(tester.getCenter(find.text('Out')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'Out').color, isNot(OpenUiTheme.light.canvas));
      await mouse.moveTo(tester.getCenter(find.text('Ghost')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'Ghost').color, OpenUiTheme.light.hover);
      await mouse.moveTo(tester.getCenter(find.text('Red')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _decoration(tester, 'Red').color,
        isNot(OpenUiTheme.light.status['danger']),
      );
      await mouse.moveTo(const Offset(790, 590));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pumped.events.single.humanFriendlyMessage, 'Go');
    });

    testWidgets('pressing darkens the button', (tester) async {
      await pumpProgram(tester, 'root = Col([Button("Go", null, "outline")])');
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'Go').color, isNot(OpenUiTheme.light.canvas));
      await gesture.up();
    });

    testWidgets('a button fades its background over 150ms', (tester) async {
      await pumpProgram(tester, 'root = Col([Button("Go")])');
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Go'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(box.duration, const Duration(milliseconds: 150));
      expect(box.curve, Curves.ease);
    });

    testWidgets('a button with an unknown icon has no icon gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Button("Go", null, "solid", null, "md", "nope"), Button("Ok")])',
      );
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Go'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .width,
        // "Go" at weight 560 is 28.5px in the test font.
        62.5,
      );
    });
  });

  group('IconButton', () {
    testWidgets('runs its action and is named by its label', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Text("n=" + \$n), IconButton("plus", @Set(\$n, \$n + 1), "More")])\n\$n = 0',
      );
      expect(find.byTooltip('More'), findsOneWidget);
      expect(find.bySemanticsLabel('More'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 1);
      expect(find.text('n=1'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('More')), const Size(34, 34));
    });

    testWidgets(
      'without an action it does nothing; the icon names it without a label',
      (tester) async {
        final pumped = await pumpProgram(tester, 'root = IconButton("plus")');
        expect(find.byType(Tooltip), findsNothing);
        expect(find.bySemanticsLabel('plus'), findsOneWidget);
        await tester.tap(find.byType(Glyph));
        await tester.pump();
        expect(pumped.events, isEmpty);
      },
    );

    testWidgets('ghost, solid and outline variants differ', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([IconButton("plus", null, "a", "ghost"), IconButton("plus", null, "b", "solid"), IconButton("plus", null, "c")], 2)',
      );
      BoxDecoration of(String label) =>
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byTooltip(label),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(of('a').color, isNull);
      expect(of('b').color, OpenUiTheme.light.ink);
      expect(of('c').color, OpenUiTheme.light.canvas);
    });

    testWidgets('hover highlights every variant and streaming disables it', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([IconButton("plus", null, "a", "ghost"), IconButton("plus", null, "b", "solid"), IconButton("plus", null, "c")], 2)',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final label in ['a', 'b', 'c']) {
        await mouse.moveTo(tester.getCenter(find.byTooltip(label)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      final pumped = await pumpProgram(
        tester,
        '\$n = 0\nroot = IconButton("plus", @Set(\$n, 1), "More")\nx = 1\n',
        streaming: true,
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 0);
    });
  });

  group('Pressable', () {
    testWidgets('makes its children tappable and shows the selected check', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Text("n=" + \$n), Pressable([Text("Tile")], @Set(\$n, \$n + 1), \$n == 1, 2)])\n\$n = 0',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size.square(12),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Tile'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 1);
      expect(find.text('n=1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size.square(12),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a selected tile whose content is a Row has no ring or check', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Pressable([Row([Text("a")])], null, true)',
      );
      expect(find.byType(Glyph), findsNothing);
    });

    testWidgets(
      'padding, radius and a raw background color with readable ink',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Pressable([Text("Dark")], null, false, 3, "#000000", "xl")',
        );
        final box = tester.widget<Container>(
          find
              .ancestor(of: find.text('Dark'), matching: find.byType(Container))
              .first,
        );
        expect(box.padding, const EdgeInsets.all(12));
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, const Color(0xFF000000));
        expect(decoration.borderRadius, BorderRadius.circular(14));
        expect(
          tester
              .widget<RichText>(
                find.descendant(
                  of: find.byType(AnimatedScale),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style
              ?.color,
          const Color(0xFFFFFFFF),
        );
      },
    );

    testWidgets('the label of a legacy action is the tile text', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Pressable([Text("Tile"), Col([Text("two")]), Button("Inner")], {type: "continue_conversation"})',
      );
      await tester.tap(find.text('Tile'));
      await tester.pump();
      expect(pumped.events.single.humanFriendlyMessage, 'Tile two Inner');
    });

    testWidgets('a button inside keeps its own tap', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Pressable([Text("Tile"), Button("Inner", @Set(\$n, 1))], @Set(\$n, 2))\n\$n = 0',
      );
      await tester.tap(find.text('Inner'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 1);
    });

    testWidgets('streaming makes it inert', (tester) async {
      final pumped = await pumpProgram(
        tester,
        '\$n = 0\nroot = Pressable([Text("Tile")], @Set(\$n, 1))\nx = 1\n',
        streaming: true,
      );
      await tester.tap(find.text('Tile'));
      await tester.pump();
      expect(pumped.session.state[r'$n'], 0);
    });

    testWidgets('hover and press scale the tile', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Pressable([Text("Tile")], null, true), Pressable([Row([Text("r")])])])',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Tile')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale,
        1.01,
      );
      await mouse.down(tester.getCenter(find.text('Tile')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale,
        0.98,
      );
      await mouse.up();
      await mouse.moveTo(tester.getCenter(find.text('r')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).last).scale,
        1,
      );
    });

    testWidgets('selected is announced as pressed, only when given', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(
        tester,
        'root = Col([Pressable([Text("On")], null, true), Pressable([Text("Plain")])])',
      );
      expect(
        tester.getSemantics(find.text('On')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(
        tester.getSemantics(find.text('Plain')),
        isSemantics(isButton: true, hasToggledState: false),
      );
      handle.dispose();
    });

    testWidgets('a row Box inside counts as a row: no check, no scale', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Pressable([Box([Text("a")], "row")], null, true)',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size == const Size.square(12),
        ),
        findsNothing,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('a')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('struck-through text inside is muted unless it has a color', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Pressable([Text("Done", null, null, null, null, true), Text("Red", null, "danger", null, null, true)]), Text("Free", null, null, null, null, true)])',
      );
      Color? ink(String t) =>
          tester.renderObject<RenderParagraph>(find.text(t)).text.style?.color;
      expect(ink('Done'), OpenUiTheme.light.muted);
      expect(ink('Red'), OpenUiTheme.light.status['danger']);
      expect(ink('Free'), OpenUiTheme.light.ink);
    });

    testWidgets('a gradient background paints the tile', (tester) async {
      await pumpProgram(
        tester,
        'root = Pressable([Text("G")], null, false, 2, "linear-gradient(90deg, #000000, #ffffff)")',
      );
      expect(_decoration(tester, 'G').gradient, isA<CssGradient>());
    });

    testWidgets('reduced motion keeps the tile still', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpProgram(tester, 'root = Pressable([Text("Tile")])');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Tile')));
      await tester.pump();
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.scale, 1);
      expect(scale.duration, Duration.zero);
    });
  });

  group('Input', () {
    testWidgets('writes a text value and re-renders while keeping focus', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Input(\$name, "Name", "text", "Your name"), Text("hi " + \$name), Button("Reset", @Set(\$name, "Zed"))])\n\$name = ""',
      );
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ana');
      await tester.pump();
      expect(pumped.session.state[r'$name'], 'Ana');
      expect(find.text('hi Ana'), findsOneWidget);
      var field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Ana');
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Anabel');
      await tester.pump();
      expect(find.text('hi Anabel'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      await tester.tap(find.text('Reset'));
      await tester.pump();
      field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Zed');
      expect(find.text('hi Zed'), findsOneWidget);
    });

    testWidgets(
      'a number field stores numbers and keeps what is typed until it parses',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = Col([Input(\$age, "Age", "number"), Text("age=" + \$age), Button("Seven", @Set(\$age, 7))])\n\$age = 5',
        );
        TextField field() => tester.widget<TextField>(find.byType(TextField));
        expect(field().controller!.text, '5');
        await tester.enterText(find.byType(TextField), '1,234');
        await tester.pump();
        expect(pumped.session.state[r'$age'], 1234);
        await tester.enterText(find.byType(TextField), '42.');
        await tester.pump();
        expect(pumped.session.state[r'$age'], 42);
        expect(field().controller!.text, '42.');
        await tester.enterText(find.byType(TextField), 'abc');
        await tester.pump();
        expect(pumped.session.state[r'$age'], 42);
        expect(field().controller!.text, 'abc');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(field().controller!.text, '42');
        await tester.enterText(find.byType(TextField), '  ');
        await tester.pump();
        expect(pumped.session.state[r'$age'], isNull);
        await tester.enterText(find.byType(TextField), '2.5');
        await tester.pump();
        expect(pumped.session.state[r'$age'], 2.5);
        await tester.tap(find.text('Seven'));
        await tester.pump();
        expect(field().controller!.text, '7');
      },
    );

    testWidgets(
      'without a binding or label it is a form field with its own name',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = Col([Input("start", null, "text", "Type"), field])\nfield = Input("", null, null, "Second")',
        );
        expect(find.text('start'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'hello');
        await tester.pump();
        expect(pumped.session.state['field'], {'value': 'hello'});
        expect(find.text('hello'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'again');
        await tester.pump();
        expect(find.text('again'), findsOneWidget);
        expect(find.text('hello'), findsOneWidget);
      },
    );

    testWidgets('dark mode and a focused field', (tester) async {
      await pumpProgram(
        tester,
        'root = Input("", "Name")',
        brightness: Brightness.dark,
      );
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 200));
      final box = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, OpenUiTheme.dark.canvas);
      expect((decoration.border! as Border).top.color, OpenUiTheme.dark.ink);
      expect(decoration.boxShadow, isNotNull);
    });

    testWidgets('a field label names the field for assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(
        tester,
        'root = Col([Input("", "Name"), DatePicker("2026-03-10", "Due"), DatePicker("2026-03-11")])',
      );
      final input = tester.getSemantics(find.byType(TextField));
      expect(input, isSemantics(isTextField: true));
      expect(input.label, startsWith('Name'));
      expect(
        tester.getSemantics(find.text('03/10/2026')).label,
        startsWith('Due'),
      );
      expect(
        tester.getSemantics(find.text('03/11/2026')).label,
        startsWith('Date'),
      );
      handle.dispose();
    });
  });

  group('TextArea', () {
    testWidgets('writes multi-line text', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([TextArea(\$note, "Note", "Write"), Text("len=" + @Count(@Split(\$note, "\\n")))])\n\$note = ""',
      );
      await tester.enterText(find.byType(TextField), 'a\nb');
      await tester.pump();
      expect(pumped.session.state[r'$note'], 'a\nb');
      expect(find.text('len=2'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 3);
    });

    testWidgets('rows are rounded and clamped between 2 and 20', (
      tester,
    ) async {
      for (final (rows, want) in [(1, 2), (5.4, 5), (50, 20)]) {
        await pumpProgram(tester, 'root = TextArea("", null, null, $rows)');
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(
          (field.minLines, field.maxLines),
          (want, want),
          reason: 'rows $rows',
        );
      }
    });
  });

  group('Select', () {
    testWidgets('chooses an option from the dropdown', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Select(\$c, ["Red", "Green", {value: "b", label: "Blue"}, null], "Colour", "Pick one"), Text("c=" + \$c)])\n\$c = ""',
      );
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Pick one'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green').last);
      await tester.pumpAndSettle();
      expect(pumped.session.state[r'$c'], 'Green');
      expect(find.text('c=Green'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue').last);
      await tester.pumpAndSettle();
      expect(pumped.session.state[r'$c'], 'b');
      expect(find.text('Blue'), findsOneWidget);
    });

    testWidgets('the select chevron is the reference grey at stroke 1.6px', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Select("a", ["a", "b"])');
      final chevron = tester.widget<Glyph>(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'chevron-down'),
      );
      expect(chevron.strokeWidth, 2.4);
      expect(chevron.color, const Color(0xFF676767));
    });

    testWidgets('an unknown value shows the default prompt', (tester) async {
      await pumpProgram(
        tester,
        'root = Select("zzz", ["A"])',
        brightness: Brightness.dark,
      );
      expect(find.text('Choose…'), findsOneWidget);
    });
  });

  group('SegmentedControl', () {
    testWidgets('picks one choice', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([SegmentedControl(\$m, ["Day", {value: "w", label: "Week"}]), Text("m=" + \$m)])\n\$m = "Day"',
      );
      await tester.tap(find.text('Week'));
      await tester.pump();
      expect(pumped.session.state[r'$m'], 'w');
      expect(find.text('m=w'), findsOneWidget);
      await tester.tap(find.text('Day'));
      await tester.pump();
      expect(pumped.session.state[r'$m'], 'Day');
      expect(
        tester.widget<Text>(find.text('Day')).style?.fontWeight,
        OpenUiTheme.weightMedium,
      );
    });

    testWidgets(
      'block stretches the bar, and dark mode selects with a strong surface',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([SegmentedControl("A", ["A", "B"], true), SegmentedControl("A", ["A", "B"])])',
          brightness: Brightness.dark,
        );
        final view = tester.getSize(find.byType(OpenUiView)).width;
        final bars = find.byWidgetPredicate(
          (w) => w is Container && w.padding == const EdgeInsets.all(3),
        );
        expect(tester.getSize(bars.first).width, view);
        expect(tester.getSize(bars.last).width, lessThan(view / 2));
        final selected = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text('A').first,
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(
          (selected.decoration! as BoxDecoration).color,
          OpenUiTheme.dark.surfaceStrong,
        );
      },
    );

    testWidgets('a segmented control is a radio group', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(tester, 'root = SegmentedControl("A", ["A", "B"])');
      bool inGroup(SemanticsNode n) =>
          n.parent != null &&
          (n.parent!.role == SemanticsRole.radioGroup || inGroup(n.parent!));
      expect(inGroup(tester.getSemantics(find.text('B'))), isTrue);
      handle.dispose();
    });
  });

  group('Slider', () {
    testWidgets('dragging and tapping write stepped numbers', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Slider(\$v, 0, 100, 5, "Budget", "\$"), Text("v=" + \$v)])\n\$v = 25',
      );
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('\$25'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pump();
      expect(pumped.session.state[r'$v'], 100);
      expect(find.text('v=100'), findsOneWidget);
      expect(find.text('\$100'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(-4000, 0));
      await tester.pump();
      expect(pumped.session.state[r'$v'], 0);
      final box = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(box.center.dx + 20, box.center.dy));
      await tester.pump();
      final v = pumped.session.state[r'$v'] as num;
      expect(v, greaterThan(50));
      expect(v % 5, 0);
    });

    testWidgets('a fractional step and a unit suffix', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Slider(\$v, 0, 15, 0.5, "Tax", "%")\n\$v = 1',
      );
      final box = tester.getRect(find.byType(Slider));
      await tester.tapAt(box.center);
      await tester.pump();
      expect(pumped.session.state[r'$v'], 7.5);
      expect(find.text('7.5%'), findsOneWidget);
    });

    testWidgets('readout groups digits and keeps two decimals', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Slider(1234.567, 0, 5000, 0.001, "A", " yrs"), Slider(-200, -200, 300, 10, "B", "€")])',
      );
      expect(find.text('1,234.57 yrs'), findsOneWidget);
      expect(find.text('€-200'), findsOneWidget);
    });

    testWidgets('readout expands finite values at the exponential boundary', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Slider(1e21, 0, 2e21, 1e20, "L")');
      expect(find.text('1,000,000,000,000,000,000,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('readout rounds decimal ties like Intl', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Slider(1.005, 0, 2, 0.001, "A"), Slider(-1.005, -2, 0, 0.001, "B")])',
      );
      expect(find.text('1.01'), findsOneWidget);
      expect(find.text('-1.01'), findsOneWidget);
    });

    testWidgets('readout preserves negative zero', (tester) async {
      await pumpProgram(tester, 'root = Slider(-0, -1, 1, 0.01, "L")');
      expect(find.text('-0'), findsOneWidget);
    });

    testWidgets('values clamp into the range, bad ones fall back to min', (
      tester,
    ) async {
      for (final (value, shown) in [('500', '100'), ('-5', '10')]) {
        await pumpProgram(tester, 'root = Slider($value, 10, 100, 1, "L")');
        expect(find.text(shown), findsOneWidget, reason: value);
      }
      await pumpProgram(
        tester,
        'root = Slider(\$v, 10, 100, 1, "L")\n\$v = "text"',
      );
      expect(find.text('10'), findsOneWidget);
      await pumpProgram(tester, 'root = Slider(2, 5, 5, 0, "L")');
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('a unit alone shows the value, marks sit under the track', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Slider(50, 0, 100, 1, null, "%", [{value: 0, label: "Low"}, {value: 50, label: "Mid"}, {value: 100, label: "High"}, {value: 500, label: "Gone"}, 3])',
      );
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Gone'), findsNothing);
      final slider = tester.getRect(find.byType(Slider));
      expect(tester.getTopLeft(find.text('Low')).dx, slider.left);
      expect(tester.getTopRight(find.text('High')).dx, slider.right);
      expect(
        tester.getCenter(find.text('Mid')).dx,
        closeTo(slider.center.dx, 0.5),
      );
      expect(
        tester.getTopLeft(find.text('Mid')).dy,
        closeTo(slider.bottom - 2, 0.01),
      );
    });

    testWidgets('a bound value is read as Number() reads it', (tester) async {
      for (final (raw, shown) in [
        ('"42"', '42'),
        ('true', '1'),
        ('" 0x10 "', '16'),
      ]) {
        await pumpProgram(
          tester,
          'root = Slider(\$v, 0, 100, 1, "L")\n\$v = $raw',
        );
        expect(find.text(shown), findsOneWidget, reason: raw);
      }
    });

    testWidgets('the track spans the width and the thumb stops 12px in', (
      tester,
    ) async {
      for (final (value, fromLeft) in [(0, true), (100, false)]) {
        await tester.pumpWidget(const SizedBox());
        await pumpProgram(tester, 'root = Slider($value, 0, 100, 1, "L")');
        final width = tester.getSize(find.byType(Slider)).width;
        expect(
          tester.renderObject(find.byType(Slider)),
          paints
            ..rrect(
              rrect: RRect.fromRectAndRadius(
                Rect.fromLTWH(0, 8, width, 24),
                const Radius.circular(12),
              ),
            )
            ..circle(x: fromLeft ? 12 : width - 12, y: 20, radius: 9),
        );
      }
    });

    testWidgets('no label or unit shows no readout', (tester) async {
      await pumpProgram(tester, 'root = Slider(50, 0, 100)');
      expect(find.text('50'), findsNothing);
    });
  });

  group('Checkbox', () {
    testWidgets('toggles the bound value', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Checkbox(\$done, "Milk"), Text("done=" + \$done)])\n\$done = false',
      );
      expect(find.byType(Glyph), findsNothing);
      await tester.tap(find.text('Milk'));
      await tester.pump();
      expect(pumped.session.state[r'$done'], true);
      expect(find.text('done=true'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'check'),
        findsOneWidget,
      );
      await tester.tap(find.text('Milk'));
      await tester.pump();
      expect(pumped.session.state[r'$done'], false);
    });

    testWidgets('lineThrough strikes the label only while checked', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Checkbox(\$a, "Struck", true), Checkbox(\$b, "Plain")])\n\$a = false\n\$b = true',
      );
      TextDecoration? decoration(String t) =>
          tester.widget<Text>(find.text(t)).style?.decoration;
      expect(decoration('Struck'), TextDecoration.none);
      await tester.tap(find.text('Struck'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(decoration('Struck'), TextDecoration.lineThrough);
      expect(_color(tester, 'Struck'), OpenUiTheme.light.muted);
      expect(decoration('Plain'), TextDecoration.none);
    });

    testWidgets('a checkbox label takes the surrounding text size', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Checkbox(false, "Milk")])');
      expect(tester.widget<Text>(find.text('Milk')).style!.fontSize, isNull);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Milk'))
            .text
            .style!
            .fontSize,
        14,
      );
    });

    testWidgets('a plain checkbox is a form field', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Checkbox(true, "Agree")',
      );
      expect(find.byType(Glyph), findsOneWidget);
      await tester.tap(find.text('Agree'));
      await tester.pump();
      expect(pumped.session.state['Agree'], {'value': false});
      expect(find.byType(Glyph), findsNothing);
    });
  });

  group('RadioGroup', () {
    testWidgets('list: picks one option and shows the legend', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([RadioGroup(\$s, ["S", {value: "m", label: "Medium", description: "Fits most"}, null], "Size"), Text("s=" + \$s)])\n\$s = "S"',
      );
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('Fits most'), findsOneWidget);
      await tester.tap(find.text('Medium'));
      await tester.pump();
      expect(pumped.session.state[r'$s'], 'm');
      expect(find.text('s=m'), findsOneWidget);
      await tester.tap(find.text('S'));
      await tester.pump();
      expect(pumped.session.state[r'$s'], 'S');
    });

    testWidgets('pills: the selected pill is filled with ink', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = RadioGroup(\$s, ["A", "B"], null, "pills")\n\$s = "A"',
      );
      expect(_decoration(tester, 'A').color, OpenUiTheme.light.ink);
      expect(_color(tester, 'A'), OpenUiTheme.light.onInk);
      await tester.tap(find.text('B'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pumped.session.state[r'$s'], 'B');
      expect(_decoration(tester, 'B').color, OpenUiTheme.light.ink);
      expect(_decoration(tester, 'A').color, isNot(OpenUiTheme.light.ink));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('A')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester, 'A').color, OpenUiTheme.light.hover);
    });

    testWidgets('cards: descriptions, a ring on the selected card, and columns', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pumped = await pumpProgram(
        tester,
        'root = RadioGroup(\$p, [{value: "a", label: "Basic", description: "Free"}, {value: "b", label: "Pro", description: "Paid"}], "Plan", "cards")\n\$p = "a"',
        brightness: Brightness.dark,
      );
      expect(find.text('Free'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Pro')).dx,
        greaterThan(tester.getTopLeft(find.text('Basic')).dx + 100),
      );
      expect(
        tester.widget<Text>(find.text('Basic')).style?.fontWeight,
        OpenUiTheme.weightMedium,
      );
      final ring = (_decoration(tester, 'Basic').border! as Border).top;
      expect(ring.width, 2);
      expect(ring.color, OpenUiTheme.dark.ink);
      await tester.tap(find.text('Pro'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(pumped.session.state[r'$p'], 'b');
      expect((_decoration(tester, 'Pro').border! as Border).top.width, 2);
      expect((_decoration(tester, 'Basic').border! as Border).top.width, 1);
    });

    testWidgets('cards stack on a narrow screen', (tester) async {
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpProgram(
        tester,
        'root = RadioGroup("a", ["a", "b"], null, "cards")',
      );
      expect(
        tester.getTopLeft(find.text('b')).dy,
        greaterThan(tester.getTopLeft(find.text('a')).dy + 20),
      );
    });

    testWidgets(
      'arrow keys move the choice and wrap; Tab stops at the checked one',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = RadioGroup(\$v, ["a", "b", "c"], "Pick")\n\$v = "b"',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final (key, expected) in [
          (LogicalKeyboardKey.arrowDown, 'c'),
          (LogicalKeyboardKey.arrowRight, 'a'),
          (LogicalKeyboardKey.arrowUp, 'c'),
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
          expect(pumped.session.state[r'$v'], expected);
        }
      },
    );

    testWidgets('a radio group is a radio group for assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(tester, 'root = RadioGroup("a", ["a", "b"], "Pick")');
      final b = tester.getSemantics(find.text('b'));
      expect(
        b,
        isSemantics(isInMutuallyExclusiveGroup: true, isChecked: false),
      );
      expect(b.parent!.role, SemanticsRole.radioGroup);
      handle.dispose();
    });
  });

  group('DatePicker', () {
    testWidgets('picks a date from the calendar', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([DatePicker(\$d, "Due"), Text("d=" + \$d)])\n\$d = "2026-03-10"',
      );
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('03/10/2026'), findsOneWidget);
      await tester.tap(find.text('03/10/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(pumped.session.state[r'$d'], '2026-03-15');
      expect(find.text('d=2026-03-15'), findsOneWidget);
      expect(find.text('03/15/2026'), findsOneWidget);
    });

    testWidgets('cancel keeps the value', (tester) async {
      final pumped = await pumpProgram(
        tester,
        'root = DatePicker(\$d)\n\$d = "2026-03-10"',
      );
      await tester.tap(find.text('03/10/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pumped.session.state[r'$d'], '2026-03-10');
    });

    testWidgets(
      'empty or invalid values show the placeholder; min starts the calendar',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = DatePicker(\$d, null, "2099-01-01", "2099-12-31")\n\$d = "2026-02-31"',
          brightness: Brightness.dark,
        );
        expect(find.text('mm/dd/yyyy'), findsOneWidget);
        await tester.tap(find.text('mm/dd/yyyy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('15'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(pumped.session.state[r'$d'], '2099-01-15');
      },
    );

    testWidgets(
      'max pulls an out-of-range date back and bad bounds are ignored',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = Col([a, b])\na = DatePicker("2030-01-01", "A", "nope", "2029-06-10")\nb = DatePicker("", "B", "2030-01-01", "2020-01-01")',
        );
        await tester.tap(find.text('01/01/2030'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(pumped.session.state['A'], {'value': '2029-06-05'});
        await tester.tap(find.text('mm/dd/yyyy'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect((pumped.session.state['B'] as Map)['value'], '2030-01-01');
      },
    );

    testWidgets(
      'on iOS the date opens a Cupertino wheel that writes as it turns',
      (tester) async {
        final pumped = await pumpProgram(
          tester,
          'root = DatePicker(\$d, "Due")\n\$d = "2026-03-10"',
        );
        await tester.tap(find.text('03/10/2026'));
        await tester.pumpAndSettle();
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .onDateTimeChanged(DateTime(2026, 3, 15));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(pumped.session.state[r'$d'], '2026-03-15');
        expect(find.byType(CupertinoDatePicker), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  group('interaction states', () {
    testWidgets('keyboard focus draws a ring; a cancelled press releases', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final pumped = await pumpProgram(
        tester,
        'root = Col([Button("Go", null, "outline"), IconButton("plus", null, "More", "ghost")])',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final rings = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border is Border &&
            ((w.decoration as BoxDecoration).border! as Border).top.width == 2,
      );
      expect(rings, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pumped.events.single.humanFriendlyMessage, 'Go');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('More')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 200));
      await gesture.cancel();
      await tester.pump();
      expect(pumped.events, hasLength(1));
    });

    testWidgets('a pressed ghost icon button is highlighted', (tester) async {
      await pumpProgram(
        tester,
        'root = IconButton("plus", null, "More", "ghost")',
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('More')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find
                        .descendant(
                          of: find.byTooltip('More'),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.color, OpenUiTheme.light.pressed);
      await gesture.up();
    });

    testWidgets('options nested in lists are flattened', (tester) async {
      await pumpProgram(
        tester,
        'root = SegmentedControl("a", [["a", "b"], ["c"]])',
      );
      expect(
        [
          for (final t in ['a', 'b', 'c']) find.text(t).evaluate().length,
        ],
        [1, 1, 1],
      );
    });
  });
}
