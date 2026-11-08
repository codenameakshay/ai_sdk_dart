import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/table.dart';

import '../support/pump.dart';

final _light = OpenUiTheme.light;

String _md(String source) => 'root = Col([Markdown(${_quote(source)})])';

String _quote(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"';

void _phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a markdown table sits in a 14 radius bordered frame', (
    tester,
  ) async {
    await pumpProgram(tester, _md('| Name | Qty |\n|---|---|\n| apple | 3 |'));
    final frame = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(IuiTable),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = frame.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(14));
    expect(decoration.border, Border.all(color: _light.border));
    final head = (tester.widget<Text>(find.text('Name')).textSpan! as TextSpan)
        .children!
        .first
        .style!;
    expect(head.color, _light.ink);
    expect(head.fontSize, 13);
  });

  testWidgets(
    'a long link label wraps onto more than one line at phone width',
    (tester) async {
      _phoneWidth(tester);
      const label = 'a very long link label that cannot fit on one phone line';
      await pumpProgram(tester, _md('[$label](https://example.com)'));
      expect(tester.getSize(find.text(label)).height, greaterThan(26.4));
    },
  );

  testWidgets('tapping a link label opens its url', (tester) async {
    final p = await pumpProgram(
      tester,
      _md('read [the docs](https://example.com/docs) first'),
    );
    await tester.tapOnText(find.textRange.ofSubstring('the docs'));
    await tester.pump();
    expect(p.opened, [Uri.parse('https://example.com/docs')]);
  });

  testWidgets('a link label is announced as a link', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(tester, _md('see [the docs](https://example.com) now'));
    expect(
      find.semantics.byLabel('the docs').evaluate().single,
      isSemantics(isLink: true),
    );
    handle.dispose();
  });

  testWidgets('a heading is announced at its level plus one', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(tester, _md('# H'));
    expect(tester.getSemantics(find.text('H')).headingLevel, 2);
    handle.dispose();
  });
}
