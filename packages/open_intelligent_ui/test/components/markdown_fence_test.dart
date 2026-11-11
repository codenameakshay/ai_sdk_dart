import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/components.dart' show MarkdownBlocks;

import '../support/pump.dart';

String _md(String source) => 'root = Col([Markdown(${_quote(source)})])';

String _quote(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"';

/// A builder that records each fence it draws and shows `<tag>:<body>`.
MarkdownFenceBuilder _recording(List<MarkdownFence> seen) => (context, fence) {
  seen.add(fence);
  return Text('${fence.tag}:${fence.body}');
};

Future<void> _pumpBlocks(
  WidgetTester tester,
  String text, {
  Map<String, MarkdownFenceBuilder>? fences,
  OpenUiServices services = const OpenUiServices(),
}) => tester.pumpWidget(
  MaterialApp(
    home: OpenUiScope(
      services: services,
      child: Scaffold(body: MarkdownBlocks(text, fences: fences)),
    ),
  ),
);

void main() {
  testWidgets('a registered tag draws the host widget in place of the code', (
    tester,
  ) async {
    final seen = <MarkdownFence>[];
    await pumpProgram(
      tester,
      _md('```chart bar\n{"a":1}\n```'),
      services: OpenUiServices(markdownFences: {'chart': _recording(seen)}),
    );

    expect(seen.single.info, 'chart bar');
    expect(seen.single.tag, 'chart');
    expect(seen.single.body, '{"a":1}');
    expect(seen.single.isComplete, isTrue);
    expect(find.text('chart:{"a":1}'), findsOneWidget);
    expect(find.text('{"a":1}'), findsNothing);
  });

  testWidgets('an unknown tag, an empty tag or a null result keeps the plain '
      'code block', (tester) async {
    final seen = <MarkdownFence>[];
    await pumpProgram(
      tester,
      _md(
        '```mermaid\ngraph TD\n```\n\n```\nno tag\n```\n\n```chart\nbad\n```',
      ),
      services: OpenUiServices(
        markdownFences: {
          'Mermaid': _recording(seen),
          '': _recording(seen),
          'chart': (context, fence) {
            seen.add(fence);
            return null;
          },
        },
      ),
    );

    expect(find.text('graph TD'), findsOneWidget);
    expect(find.text('no tag'), findsOneWidget);
    expect(find.text('bad'), findsOneWidget);
    expect([for (final f in seen) f.info], ['chart']);
  });

  testWidgets('a streaming fence reaches its builder unfinished, then '
      'finished once it closes', (tester) async {
    final seen = <MarkdownFence>[];
    final fences = {'chart': _recording(seen)};

    await _pumpBlocks(tester, 'Sales:\n\n```chart\n{"a":', fences: fences);
    expect(seen.last.body, '{"a":');
    expect(seen.last.isComplete, isFalse);
    expect(find.text('chart:{"a":'), findsOneWidget);

    await _pumpBlocks(
      tester,
      'Sales:\n\n```chart\n{"a":1}\n```',
      fences: fences,
    );
    expect(seen.last.body, '{"a":1}');
    expect(seen.last.isComplete, isTrue);
    expect(find.text('chart:{"a":1}'), findsOneWidget);
    expect(find.text('chart:{"a":'), findsNothing);
  });

  testWidgets('each fence in a document gets its own body, in order', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      _md(
        'Two charts follow.\n\n'
        '```chart\nfirst\n```\n\n'
        '```mermaid\ngraph LR\n```\n\n'
        '```chart\nsecond\n```',
      ),
      services: OpenUiServices(markdownFences: {'chart': _recording([])}),
    );

    expect(find.text('Two charts follow.'), findsOneWidget);
    expect(find.text('graph LR'), findsOneWidget);
    final first = tester.getTopLeft(find.text('chart:first'));
    final mermaid = tester.getTopLeft(find.text('graph LR'));
    final second = tester.getTopLeft(find.text('chart:second'));
    expect(first.dy, lessThan(mermaid.dy));
    expect(mermaid.dy, lessThan(second.dy));
  });

  testWidgets('MarkdownBlocks fences take precedence over the scope', (
    tester,
  ) async {
    await _pumpBlocks(
      tester,
      '```chart\nx\n```',
      fences: {'chart': (context, fence) => const Text('local')},
      services: OpenUiServices(
        markdownFences: {'chart': (context, fence) => const Text('scope')},
      ),
    );

    expect(find.text('local'), findsOneWidget);
    expect(find.text('scope'), findsNothing);
  });
}
