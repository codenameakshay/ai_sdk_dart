import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/map.dart' show partialLine;
import 'package:latlong2/latlong.dart' as ll;

import '../support/pump.dart';

const _sf = '''
root = Col([map])
map = Map([m1, m2, m3, m4], true, \$stop)
\$stop = "Ferry Building"
m1 = MapMarker("Ferry Building", 37.7955, -122.3937, "Food", "☕")
m2 = MapMarker("Coit Tower", 37.8024, -122.4058, "Views")
m3 = MapMarker("Palace of Fine Arts", 37.8029, -122.4484, "Landmarks", "🏛️")
m4 = MapMarker("Golden Gate Bridge", 37.8199, -122.4783, "Views", "🌉")
''';

Future<Pumped> _pump(
  WidgetTester tester,
  String program, {
  Future<List<LatLng>?> Function(List<LatLng> stops)? route,
}) async {
  final p = await pumpProgram(
    tester,
    program,
    services: OpenUiServices(streetRoute: route, mapTiles: null),
  );
  await tester.pump();
  await tester.pump();
  return p;
}

List<fm.Polyline> _lines(WidgetTester tester) => tester
    .widgetList<fm.PolylineLayer>(find.byType(fm.PolylineLayer))
    .expand((l) => l.polylines)
    .toList();

void main() {
  group('partialLine', () {
    test('cuts a line at the given share of its length', () {
      expect(partialLine([(lat: 0, lng: 0), (lat: 0, lng: 10)], 0.5), [
        (lat: 0, lng: 0),
        (lat: 0, lng: 5),
      ]);
    });

    test('a full progress keeps every point', () {
      expect(
        partialLine([
          (lat: 0, lng: 0),
          (lat: 0, lng: 10),
          (lat: 5, lng: 10),
        ], 1),
        [(lat: 0, lng: 0), (lat: 0, lng: 10), (lat: 5, lng: 10)],
      );
    });
  });

  group('Map pan on touch', () {
    testWidgets(
      'one finger dragging the map scrolls the page and shows the two-finger hint',
      (tester) async {
        await _pump(
          tester,
          'root = Col([m, b])\nm = Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)])\nb = Box([], "col", null, null, null, null, null, null, 1500)',
        );
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(scroll.position.pixels, 0);
        await tester.drag(find.byType(fm.FlutterMap), const Offset(0, -200));
        await tester.pump();
        expect(scroll.position.pixels, greaterThan(0));
        expect(find.text('Use two fingers to move the map'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(find.text('Use two fingers to move the map'), findsNothing);
      },
    );
  });

  group('Map zoom buttons', () {
    testWidgets('Zoom in raises the camera zoom by one', (tester) async {
      await _pump(tester, _sf);
      await tester.pump(const Duration(seconds: 1));
      final camera = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      final before = camera.camera.zoom;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(camera.camera.zoom, before + 1);
    });
  });

  group('Map pin placement', () {
    testWidgets('a single place puts its pin centre on the map centre', (
      tester,
    ) async {
      await _pump(tester, 'root = Col([Map([MapMarker("Solo", 10, 20)])])');
      await tester.pump(const Duration(seconds: 1));
      final pin = tester.getCenter(find.text('1'));
      final map = tester.getCenter(find.byType(fm.FlutterMap));
      expect(pin.dx, closeTo(map.dx, 1));
      expect(pin.dy, closeTo(map.dy, 1));
    });
  });

  group('Map controls on a phone', () {
    testWidgets('the filter pill sits left of Expand and is at most 180 wide', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      await _pump(tester, _sf);
      final filter = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is ConstrainedBox && w.constraints.maxWidth == 180,
        ),
      );
      final expand = tester.getRect(find.text('Expand'));
      expect(filter.right, lessThan(expand.left));
      expect(filter.width, lessThanOrEqualTo(180));
      handle.dispose();
    });
  });

  group('Map route status', () {
    testWidgets(
      'a failing street route announces the direct connections fallback',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)], true)])',
          route: (stops) async => null,
        );
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            'Street routing unavailable. Showing direct connections.',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );
  });

  group('Map route overview', () {
    testWidgets(
      'the direct line draws out after framing and ends at the last place',
      (tester) async {
        await _pump(
          tester,
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)], true)])',
        );
        expect(
          _lines(tester).single.points.last,
          isNot(const ll.LatLng(11, 21)),
        );
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pump(const Duration(milliseconds: 800));
        final drawn = _lines(tester).single.points.last;
        expect(drawn, const ll.LatLng(11, 21));
      },
    );
  });
}
