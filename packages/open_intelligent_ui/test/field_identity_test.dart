import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

const _segments =
    'root = Col([SegmentedControl("", [{value: "a", label: "A"}, {value: "b", label: "B"}])])';

void main() {
  OpenUiSession open(String program, [Map<String, Object?> state = const {}]) {
    final session = OpenUiSession(intelligentUi, initialState: state)
      ..update(program, streaming: false);
    addTearDown(session.dispose);
    return session;
  }

  Future<void> show(WidgetTester tester, OpenUiSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiView(
            key: UniqueKey(),
            session: session,
            builders: intelligentUiBuilders,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> texts(WidgetTester tester) => [
    for (final f in tester.widgetList<TextField>(find.byType(TextField)))
      f.controller!.text,
  ];

  bool checked(WidgetTester tester, String label) => tester
      .widget<Semantics>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.checked != null,
              ),
            )
            .first,
      )
      .properties
      .checked!;

  testWidgets('a typed value survives a remount and a restore', (tester) async {
    const program = 'root = Col([Input("")])';
    final session = open(program);
    await show(tester, session);
    await tester.enterText(find.byType(TextField), 'Ann');
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await show(tester, session);
    expect(texts(tester), ['Ann']);

    await show(tester, open(program, session.state));
    expect(texts(tester), ['Ann']);
  });

  testWidgets('a picked segment survives a restore after other views', (
    tester,
  ) async {
    final first = open(_segments);
    await show(tester, first);
    await tester.tap(find.text('B'));
    await tester.pump();
    final saved = first.state;

    await show(tester, open('root = Col([Input(""), Input(""), Input("")])'));
    final restored = open(_segments, saved);
    await show(tester, restored);
    expect(checked(tester, 'B'), isTrue);
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(restored.state.keys, saved.keys);
  });

  testWidgets('two controls with the same label keep separate values', (
    tester,
  ) async {
    const program = 'root = Col([Input("", "Name"), Input("", "Name")])';
    final session = open(program);
    await show(tester, session);
    await tester.enterText(find.byType(TextField).at(0), 'Ann');
    await tester.enterText(find.byType(TextField).at(1), 'Bob');
    await tester.pump();
    expect(texts(tester), ['Ann', 'Bob']);

    await show(tester, open(program, session.state));
    expect(texts(tester), ['Ann', 'Bob']);
  });
}
