import 'package:flutter/gestures.dart';
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
  testWidgets(
    'an expanded map updates places during flight and disposes its overlay',
    (tester) async {
      final p = await _pump(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      p.session.update(
        'root = Col([Map([MapMarker("New place", 30, 40)])])',
        streaming: false,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final controller = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      final c = controller.camera;
      final s =
          c.projectAtZoom(const ll.LatLng(30, 40)) - c.projectAtZoom(c.center);
      expect(s.dx, closeTo(0, 1e-6));
      expect(s.dy, closeTo(10, 1e-6));
      expect(find.text('Collapse'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Text('Replacement')));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(fm.FlutterMap), findsNothing);
      expect(find.text('Replacement'), findsOneWidget);
    },
  );

  testWidgets(
    'changing places while routing is disabled drops the old street route',
    (tester) async {
      const first =
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)], true)])';
      const second =
          'root = Col([Map([MapMarker("C place", 30, 40), MapMarker("D place", 31, 41)], false)])';
      final p = await _pump(
        tester,
        first,
        route: (_) async => [
          (lat: 10, lng: 20),
          (lat: 10.5, lng: 20.5),
          (lat: 11, lng: 21),
        ],
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      p.session.update(second, streaming: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      p.session.update(second.replaceFirst('false', 'true'), streaming: true);
      await tester.pump();
      expect(_lines(tester).single.points.first, const ll.LatLng(30, 40));
      expect(_lines(tester).single.points.last, const ll.LatLng(31, 41));
    },
  );

  testWidgets('a route stays hidden until changed places finish framing', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final p = await _pump(tester, _sf);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 800));
    expect(_lines(tester).single.points, [
      const ll.LatLng(37.7955, -122.3937),
      const ll.LatLng(37.8024, -122.4058),
      const ll.LatLng(37.8029, -122.4484),
      const ll.LatLng(37.8199, -122.4783),
    ]);

    p.session.update(
      'root = Col([map])\n'
      'map = Map([MapMarker("New A", 30, 40), MapMarker("New B", 31, 41)], true)',
      streaming: false,
    );
    await tester.pump();
    expect(_lines(tester), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(_lines(tester).single.points, [
      const ll.LatLng(30, 40),
      const ll.LatLng(31, 41),
    ]);
  });

  testWidgets('an interrupted first frame waits for changed places to recover', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const program =
        'root = Col([map])\nmap = Map([MapMarker("A", 30, 40), MapMarker("B", 31, 41)], true)';
    final p = await _pump(tester, program);
    p.session.update(program, streaming: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    p.session.update(program, streaming: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_lines(tester), isEmpty);

    p.session.update(
      'root = Col([map])\nmap = Map([MapMarker("C", 32, 42), MapMarker("D", 33, 43)], true)',
      streaming: false,
    );
    await tester.pump();
    expect(_lines(tester), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 800));
    expect(_lines(tester).single.points, [
      const ll.LatLng(32, 42),
      const ll.LatLng(33, 43),
    ]);
  });

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
    testWidgets('Zoom in eases one level in over 500ms', (tester) async {
      await _pump(tester, _sf);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final camera = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      final before = camera.camera.zoom;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(camera.camera.zoom, greaterThan(before));
      expect(camera.camera.zoom, lessThan(before + 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(camera.camera.zoom, closeTo(before + 1, 1e-9));
    });

    testWidgets('Zoom out is disabled at the minimum zoom', (tester) async {
      await _pump(tester, 'root = Col([Map([])])');
      final camera = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      camera.move(const ll.LatLng(20, 0), 1);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(camera.camera.zoom, 1);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Zoom out')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets(
      'the zoom buttons show only while the map is hovered, tapped or focused',
      (tester) async {
        await _pump(tester, _sf);
        double opacity() => tester
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byTooltip('Zoom in'),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        expect(opacity(), 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.byType(fm.FlutterMap)));
        await tester.pump();
        expect(opacity(), 1);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(opacity(), 0);
        await tester.tapAt(
          tester.getTopLeft(find.byType(fm.FlutterMap)) +
              const Offset(200, 300),
        );
        await tester.pump();
        expect(opacity(), 1, reason: 'touch keeps :hover after a tap');
        await tester.tapAt(const Offset(4, 4));
        await tester.pump();
        expect(opacity(), 0);
        Focus.of(tester.element(find.text('Expand'))).requestFocus();
        await tester.pump();
        expect(opacity(), 1, reason: ':focus-within');
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });

  group('Map pin placement', () {
    testWidgets(
      'a single place sits 10px under the map centre, below the controls',
      (tester) async {
        await _pump(tester, 'root = Col([Map([MapMarker("Solo", 10, 20)])])');
        await tester.pump(const Duration(seconds: 1));
        final pin = tester.getCenter(find.text('1'));
        final map = tester.getCenter(find.byType(fm.FlutterMap));
        expect(pin.dx, closeTo(map.dx, 1));
        expect(pin.dy, closeTo(map.dy + 10, 1));
      },
    );
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
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: false);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _pump(
          tester,
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)], true)])',
        );
        expect(_lines(tester), isEmpty);
        await tester.pump(const Duration(milliseconds: 1000));
        expect(
          _lines(tester).single.points.last,
          isNot(const ll.LatLng(11, 21)),
        );
        await tester.pump(const Duration(milliseconds: 800));
        expect(_lines(tester).single.points, [
          const ll.LatLng(10, 20),
          const ll.LatLng(11, 21),
        ]);
      },
    );
  });
}
