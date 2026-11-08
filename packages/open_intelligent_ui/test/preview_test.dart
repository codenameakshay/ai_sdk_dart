import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

void main() {
  testWidgets('the trigger names the response and opens its view', (
    tester,
  ) async {
    final names = <String?>[];
    final opens = <bool>[];
    const head = ']]>openui:content?name=Q3+report\nroot = Col([Text("body")])';
    final session = OpenUiSession(intelligentUi)..update(head, streaming: true);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiPreview(
            view: OpenUiView(session: session, builders: intelligentUiBuilders),
            onOpenChange: opens.add,
            onMetadata: (metadata) => names.add(metadata.name),
          ),
        ),
      ),
    );
    expect(find.text('Q3 report (generating…)'), findsOneWidget);
    expect(find.text('body'), findsNothing);
    expect(names, ['Q3 report']);

    session.update('$head\n]]>openui:end', streaming: false);
    await tester.pump();
    expect(find.text('Q3 report'), findsOneWidget);

    await tester.tap(find.text('Q3 report'));
    await tester.pump();
    expect(find.text('body'), findsOneWidget);
    expect(opens, [true]);

    await tester.tap(find.text('Close Q3 report'));
    await tester.pump();
    expect(find.text('body'), findsNothing);
    expect(opens, [true, false]);
    expect(names, ['Q3 report']);
  });

  testWidgets('a controlled preview follows open; an unnamed one is untitled', (
    tester,
  ) async {
    final opens = <bool>[];
    final session = OpenUiSession(intelligentUi)
      ..update('root = Col([Text("body")])', streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiPreview(
            open: true,
            view: OpenUiView(session: session, builders: intelligentUiBuilders),
            onOpenChange: opens.add,
          ),
        ),
      ),
    );
    expect(find.text('Untitled artifact'), findsOneWidget);
    expect(find.text('body'), findsOneWidget);
    await tester.tap(find.text('Close Untitled artifact'));
    await tester.pump();
    expect(opens, [false]);
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('a builder lays out the preview and reads it with of', (
    tester,
  ) async {
    final session = OpenUiSession(intelligentUi)
      ..update(
        ']]>openui:content?name=Deck\nroot = Col([Text("body")])',
        streaming: false,
      );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiPreview(
            view: OpenUiView(session: session, builders: intelligentUiBuilders),
            builder: (context, preview, content) => Column(
              children: [
                TextButton(
                  onPressed: OpenUiPreview.of(context).open,
                  child: Text('Show ${preview.metadata.name}'),
                ),
                ?content,
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('body'), findsNothing);
    await tester.tap(find.text('Show Deck'));
    await tester.pump();
    expect(find.text('body'), findsOneWidget);
  });
}
