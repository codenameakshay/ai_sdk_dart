// ignore_for_file: implementation_imports
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/components/table.dart';

void main() {
  testWidgets('table paints separators after a composited input repaints', (
    tester,
  ) async {
    final session = OpenUiSession(intelligentUi)
      ..update(
        'root = Table(["Name"], [[Input("", "Name")]])',
        streaming: false,
      );
    addTearDown(session.dispose);
    const surface = ValueKey('table-paint');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: surface,
              child: SizedBox(
                width: 400,
                child: OpenUiView(
                  session: session,
                  builders: intelligentUiBuilders,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'Painted input');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Painted input'), findsOneWidget);

    final table = tester.allRenderObjects.whereType<RenderIuiTable>().single;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(surface),
    );
    final separator = boundary.globalToLocal(
      table.localToGlobal(
        Offset(table.size.width / 2, table.firstChild!.size.height),
      ),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final index =
          (separator.dy.floor() * image.width + separator.dx.floor()) * 4;
      expect(bytes.buffer.asUint8List(index, 4), [0, 0, 0, 20]);
      image.dispose();
    });
  });
}
