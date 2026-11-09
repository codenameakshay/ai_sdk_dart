// ignore_for_file: implementation_imports
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/src/components/flex_row.dart';
import 'package:open_intelligent_ui_core/src/components/table.dart';

const _surfaceKey = ValueKey('surface');

Future<void> _paintedAt(
  WidgetTester tester,
  Finder target,
  List<int> rgba,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surfaceKey),
  );
  final point = boundary.globalToLocal(tester.getCenter(target));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
    expect(bytes.buffer.asUint8List(index, 4), rgba);
    image.dispose();
  });
}

Widget _app(Widget child, TextDirection direction) => MaterialApp(
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _surfaceKey,
          child: SizedBox(width: 300, child: child),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('RTL row paints and hits the mirrored child positions', (
    tester,
  ) async {
    final taps = <String>[];
    Widget child(String id, Color color, double width) => GestureDetector(
      onTap: () => taps.add(id),
      child: ColoredBox(
        key: ValueKey(id),
        color: color,
        child: SizedBox(width: width, height: 40),
      ),
    );
    Widget row() => FlexRow(
      gap: 10,
      children: [
        child('first', const Color(0xffff0000), 40),
        child('second', const Color(0xff0000ff), 60),
      ],
    );
    await tester.pumpWidget(_app(row(), TextDirection.ltr));
    expect(tester.getRect(find.byKey(const ValueKey('first'))).left, 0);
    await tester.pumpWidget(_app(row(), TextDirection.rtl));
    final first = find.byKey(const ValueKey('first'));
    final second = find.byKey(const ValueKey('second'));
    expect(tester.getRect(first), const Rect.fromLTWH(260, 0, 40, 40));
    expect(tester.getRect(second), const Rect.fromLTWH(190, 0, 60, 40));
    await _paintedAt(tester, first, [255, 0, 0, 255]);
    await _paintedAt(tester, second, [0, 0, 255, 255]);
    await tester.tapAt(const Offset(280, 20));
    await tester.tapAt(const Offset(220, 20));
    expect(taps, ['first', 'second']);
  });

  testWidgets('RTL table paints and hits the mirrored cells', (tester) async {
    final taps = <String>[];
    Widget cell(String id, Color color) => GestureDetector(
      onTap: () => taps.add(id),
      child: ColoredBox(
        key: ValueKey(id),
        color: color,
        child: const SizedBox(width: 24, height: 24),
      ),
    );
    Widget table() => IuiTable(
      head: const [Text('First'), Text('Second')],
      numeric: const [false, true],
      rows: [
        [
          IuiCell(cell('first', const Color(0xffff0000))),
          IuiCell(cell('second', const Color(0xff0000ff))),
        ],
      ],
    );
    await tester.pumpWidget(_app(table(), TextDirection.ltr));
    final firstLtr = tester.getCenter(find.byKey(const ValueKey('first')));
    final secondLtr = tester.getCenter(find.byKey(const ValueKey('second')));
    expect(firstLtr.dx, lessThan(secondLtr.dx));
    await tester.pumpWidget(_app(table(), TextDirection.rtl));
    final first = find.byKey(const ValueKey('first'));
    final second = find.byKey(const ValueKey('second'));
    expect(tester.getCenter(first).dx, closeTo(300 - firstLtr.dx, 0.5));
    expect(tester.getCenter(second).dx, closeTo(300 - secondLtr.dx, 0.5));
    expect(
      tester.getCenter(find.text('First')).dx,
      greaterThan(tester.getCenter(find.text('Second')).dx),
    );
    await _paintedAt(tester, first, [255, 0, 0, 255]);
    await _paintedAt(tester, second, [0, 0, 255, 255]);
    await tester.tapAt(tester.getCenter(first));
    await tester.tapAt(tester.getCenter(second));
    expect(taps, ['first', 'second']);
  });

  testWidgets('RTL wrapped row starts each painted hit target at the right', (
    tester,
  ) async {
    final taps = <String>[];
    Widget child(String id, Color color) => GestureDetector(
      onTap: () => taps.add(id),
      child: ColoredBox(
        key: ValueKey(id),
        color: color,
        child: const SizedBox(width: 140, height: 40),
      ),
    );
    await tester.pumpWidget(
      _app(
        FlexRow(
          gap: 10,
          wrap: true,
          children: [
            child('first', const Color(0xffff0000)),
            child('second', const Color(0xff0000ff)),
            child('third', const Color(0xff00ff00)),
          ],
        ),
        TextDirection.rtl,
      ),
    );
    final first = find.byKey(const ValueKey('first'));
    final second = find.byKey(const ValueKey('second'));
    final third = find.byKey(const ValueKey('third'));
    expect(tester.getRect(first), const Rect.fromLTWH(160, 0, 140, 40));
    expect(tester.getRect(second), const Rect.fromLTWH(10, 0, 140, 40));
    expect(tester.getRect(third), const Rect.fromLTWH(160, 50, 140, 40));
    await _paintedAt(tester, third, [0, 255, 0, 255]);
    await tester.tapAt(const Offset(230, 20));
    await tester.tapAt(const Offset(80, 20));
    await tester.tapAt(const Offset(230, 70));
    expect(taps, ['first', 'second', 'third']);
  });
}
