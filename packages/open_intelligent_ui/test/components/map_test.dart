import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/map.dart'
    show pinEmoji, placesOf;

import '../gallery_fixture.dart';
import '../support/pump.dart';

typedef _Route = Future<List<LatLng>?> Function(List<LatLng> stops);

OpenUiServices _services({_Route? route, MapTiles? tiles}) =>
    OpenUiServices(streetRoute: route, mapTiles: tiles);

const _sf = '''
root = Col([map])
map = Map([m1, m2, m3, m4], true, \$stop)
\$stop = "Ferry Building"
m1 = MapMarker("Ferry Building", 37.7955, -122.3937, "Food", "☕")
m2 = MapMarker("Coit Tower", 37.8024, -122.4058, "Views")
m3 = MapMarker("Palace of Fine Arts", 37.8029, -122.4484, "Landmarks", "🏛️")
m4 = MapMarker("Golden Gate Bridge", 37.8199, -122.4783, "Views", "🌉")
''';

const _twoStops = '''
root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)], true)])
''';

List<OpenUiElement> _markers(String program, {bool streaming = false}) {
  final session = OpenUiSession(intelligentUi)
    ..update(program, streaming: streaming);
  addTearDown(session.dispose);
  final map = session.root!.props.elements('children').first;
  return map.props.elements('markers');
}

/// Waits out the camera's fly to the places (920ms), then the route
/// draw-out (760ms) that starts after it.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pump(const Duration(milliseconds: 800));
}

Future<Pumped> _pump(
  WidgetTester tester,
  String program, {
  _Route? route,
  MapTiles? tiles,
  Brightness brightness = Brightness.light,
  bool streaming = false,
}) async {
  final p = await pumpProgram(
    tester,
    program,
    services: _services(route: route, tiles: tiles),
    brightness: brightness,
    streaming: streaming,
  );
  await tester.pump();
  await tester.pump();
  return p;
}

/// flutter_map's attribution asks for a logo asset the test bundle lacks.
void _ignoreLogoAsset() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('flutter_map_logo')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Like [_pump], with the services above the Navigator, as an app would have
/// them, so pushed routes see them too.
Future<Pumped> _pumpAbove(WidgetTester tester, String program) async {
  final session = OpenUiSession(intelligentUi)
    ..update(program, streaming: false);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => OpenUiScope(
        services: const OpenUiServices(mapTiles: null),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: OpenUiView(session: session, builders: intelligentUiBuilders),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return Pumped(session, [], [], []);
}

Finder get _polylines => find.byType(fm.PolylineLayer);

List<fm.Polyline> _lines(WidgetTester tester) => tester
    .widgetList<fm.PolylineLayer>(_polylines)
    .expand((l) => l.polylines)
    .toList();

Finder _button(String tooltip) => find.byTooltip(tooltip);

void main() {
  group('pinEmoji', () {
    test('is the first emoji, and nothing for words or empty input', () {
      expect(pinEmoji('☕'), '☕');
      expect(pinEmoji('🏛️'), '🏛️');
      expect(pinEmoji('  🌉 Bridge'), '🌉');
      expect(pinEmoji('🇵🇹'), '🇵🇹');
      expect(pinEmoji('©'), '©');
      expect(pinEmoji('Coffee'), isNull);
      expect(pinEmoji('A'), isNull);
      expect(pinEmoji(''), isNull);
      expect(pinEmoji('   '), isNull);
      expect(pinEmoji(7), isNull);
      expect(pinEmoji(null), isNull);
    });
  });

  group('placesOf', () {
    test('keeps good markers in order with their category and emoji', () {
      final places = placesOf(_markers(_sf), streaming: false);
      expect(places.map((p) => p.label), [
        'Ferry Building',
        'Coit Tower',
        'Palace of Fine Arts',
        'Golden Gate Bridge',
      ]);
      expect(places.map((p) => p.order), [0, 1, 2, 3]);
      expect(places.map((p) => p.category), [
        'Food',
        'Views',
        'Landmarks',
        'Views',
      ]);
      expect(places.map((p) => p.icon), ['☕', null, '🏛️', '🌉']);
      expect(places.first.lat, 37.7955);
      expect(places.first.lng, -122.3937);
      expect(places.first.point.latitude, 37.7955);
    });

    test('a repeated label gets (2), (3) in its key and keeps its label', () {
      final places = placesOf(
        _markers(
          'root = Col([Map([MapMarker("Cafe", 1, 1), MapMarker("Cafe", 2, 2), MapMarker("Bar", 3, 3), MapMarker("Cafe", 4, 4)])])',
        ),
        streaming: false,
      );
      expect(places.map((p) => p.key), ['Cafe', 'Cafe (2)', 'Bar', 'Cafe (3)']);
      expect(places.map((p) => p.label), ['Cafe', 'Cafe', 'Bar', 'Cafe']);
    });

    test('invalid coordinates and blank labels are dropped', () {
      final places = placesOf(
        _markers(
          'root = Col([Map([MapMarker("lat", 91, 0), MapMarker("lng", 0, 181), MapMarker("neg", -91, 0), '
          'MapMarker("", 1, 1), MapMarker("  ", 1, 1), MapMarker("text", "a", "b"), MapMarker("edge", 90, -180), MapMarker("ok", 0, 0)])])',
        ),
        streaming: false,
      );
      expect(places.map((p) => p.label), ['edge', 'ok']);
      expect(places.last.order, greaterThan(places.first.order));
    });

    test('a blank category is no category', () {
      final places = placesOf(
        _markers(
          'root = Col([Map([MapMarker("A", 1, 1, "  "), MapMarker("B", 2, 2, " Food ")])])',
        ),
        streaming: false,
      );
      expect(places.map((p) => p.category), [null, 'Food']);
    });

    test('other element types in the list are ignored', () {
      final session = OpenUiSession(intelligentUi)
        ..update(
          'root = Col([Map([MapMarker("A", 1, 1), Text("x")])])',
          streaming: false,
        );
      addTearDown(session.dispose);
      final markers = session.root!.props
          .elements('children')
          .first
          .props
          .elements('markers');
      expect(placesOf(markers, streaming: false), hasLength(1));
    });

    test(
      'while streaming a half-written marker is dropped, and kept once complete',
      () {
        const cut =
            'root = Col([map])\nmap = Map([m1, m2])\nm1 = MapMarker("A", 1, 2)\nm2 = MapMarker("B", 3,';
        expect(
          placesOf(_markers(cut, streaming: true), streaming: true),
          isEmpty,
        );
        expect(
          placesOf(
            _markers(cut, streaming: true),
            streaming: false,
          ).map((p) => p.label),
          ['A'],
        );
        const done =
            'root = Col([map])\nmap = Map([m1, m2])\nm1 = MapMarker("A", 1, 2)\nm2 = MapMarker("B", 3, 4)\n';
        expect(
          placesOf(
            _markers(done, streaming: true),
            streaming: true,
          ).map((p) => p.label),
          ['A', 'B'],
        );
      },
    );
  });

  group('MapMarker', () {
    testWidgets('outside a Map renders nothing', (tester) async {
      await pumpProgram(tester, 'root = Col([MapMarker("Lone", 1, 1)])');
      expect(find.text('Lone'), findsNothing);
      expect(find.byType(fm.FlutterMap), findsNothing);
    });
  });

  group('Map pins', () {
    testWidgets('show a numbered pin or the emoji, with every label', (
      tester,
    ) async {
      await _pump(tester, _sf);
      for (final label in [
        'Ferry Building',
        'Coit Tower',
        'Palace of Fine Arts',
        'Golden Gate Bridge',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('☕'), findsOneWidget);
      expect(find.text('🏛️'), findsOneWidget);
      expect(find.text('🌉'), findsOneWidget);
      expect(
        find.text('2'),
        findsOneWidget,
        reason: 'Coit Tower has no emoji, so its number',
      );
      expect(find.text('1'), findsNothing);
    });

    testWidgets('tapping a pin sets the bound \$selected', (tester) async {
      final p = await _pump(tester, _sf);
      await _settle(tester);
      expect(p.session.state[r'$stop'], 'Ferry Building');
      await tester.tap(find.text('Coit Tower'));
      await tester.pump();
      expect(p.session.state[r'$stop'], 'Coit Tower');
      await tester.tap(find.text('Golden Gate Bridge'));
      await tester.pump();
      expect(p.session.state[r'$stop'], 'Golden Gate Bridge');
    });

    testWidgets('the selected emoji pin is 34 wide with a 3px ink ring', (
      tester,
    ) async {
      await _pump(tester, _sf);
      final face = find.ancestor(
        of: find.text('☕'),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getSize(face.first), const Size(34, 34));
      final rings = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border?.top.width == 3,
      );
      expect(rings, findsOneWidget);
      final border =
          (tester.widget<DecoratedBox>(rings).decoration as BoxDecoration)
                  .border!
              as Border;
      expect(border.top.color, OpenUiTheme.light.ink);
    });

    testWidgets('pins are announced as selectable buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _sf);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ferry Building')),
        isSemantics(isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Coit Tower')),
        isSemantics(isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('an unbound Map still selects (its own field)', (tester) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 10.01, 20.01)])])',
      );
      await tester.tap(find.text('B place'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('markers dropped by validation do not appear', (tester) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("Good place", 10, 20), MapMarker("Bad place", 120, 20), MapMarker("Same place", 10.01, 20.01), MapMarker("Same place", 10.02, 20.02)])])',
      );
      expect(find.text('Good place'), findsOneWidget);
      expect(find.text('Bad place'), findsNothing);
      expect(find.text('Same place'), findsNWidgets(2));
    });

    testWidgets(
      'a single marker is centered, and no markers shows an empty world',
      (tester) async {
        await _pump(
          tester,
          'root = Col([Map([MapMarker("Only place", 10, 20)])])',
        );
        expect(find.text('Only place'), findsOneWidget);
        await _pump(tester, 'root = Col([Map([])])');
        expect(find.byType(fm.FlutterMap), findsOneWidget);
        expect(find.byType(fm.MarkerLayer), findsOneWidget);
        expect(find.text('Only place'), findsNothing);
      },
    );

    testWidgets('the Map is labelled and sized by height, clamped to 200..720', (
      tester,
    ) async {
      Future<double> heightFor(String height) async {
        await _pump(
          tester,
          'root = Col([Map([MapMarker("A place", 1, 1)], false, null, $height)])',
        );
        return tester.getSize(find.byType(fm.FlutterMap)).height;
      }

      expect(await heightFor('null'), 400);
      expect(await heightFor('250'), 250);
      expect(await heightFor('100'), 200);
      expect(await heightFor('5000'), 656);
    });
  });

  group('Map category filter', () {
    testWidgets('appears with two or more categories and filters the pins', (
      tester,
    ) async {
      await _pump(tester, _sf);
      expect(find.text('All places'), findsOneWidget);
      await tester.tap(find.text('All places'));
      await tester.pumpAndSettle();
      for (final c in ['Food', 'Views', 'Landmarks']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      await tester.tap(find.text('Views').last);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.text('Coit Tower'), findsOneWidget);
      expect(find.text('Golden Gate Bridge'), findsOneWidget);
      expect(find.text('Ferry Building'), findsNothing);
      expect(find.text('Palace of Fine Arts'), findsNothing);

      await tester.tap(find.text('Views').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All places').last);
      await tester.pumpAndSettle();
      await tester.pump();
      expect(find.text('Ferry Building'), findsOneWidget);
    });

    testWidgets('is absent with one category or none', (tester) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 1, 1, "Food"), MapMarker("B place", 1.1, 1.1, "Food")])])',
      );
      expect(find.text('All places'), findsNothing);
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 1, 1), MapMarker("B place", 1.1, 1.1)])])',
      );
      expect(find.text('All places'), findsNothing);
    });

    testWidgets('resets to all when its category goes away', (tester) async {
      final p = await _pump(tester, _sf);
      await tester.tap(find.text('All places'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      expect(find.text('Coit Tower'), findsNothing);
      p.session.update(
        'root = Col([Map([MapMarker("Coit Tower", 37.8024, -122.4058, "Views"), MapMarker("Pier", 37.8087, -122.4098, "Views")])])',
        streaming: false,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Coit Tower'), findsOneWidget);
      expect(find.text('Pier'), findsOneWidget);
    });
  });

  group('Map toolbar', () {
    testWidgets('the info button toggles the help text, with a note on the route', (
      tester,
    ) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 1, 1), MapMarker("B place", 1.1, 1.1)])])',
      );
      const help =
          'Drag to explore and use + and − to zoom. Select a place to highlight it.';
      expect(find.text(help), findsNothing);
      await tester.tap(_button('About this map'));
      await tester.pump();
      expect(find.text(help), findsOneWidget);
      await tester.tap(_button('About this map'));
      await tester.pump();
      expect(find.text(help), findsNothing);
    });

    testWidgets(
      'the help notes that the route is only an overview when streets are unavailable',
      (tester) async {
        await _pump(tester, _twoStops);
        await tester.tap(_button('About this map'));
        await tester.pump();
        expect(
          find.textContaining(
            'The line joins the places in order. Street routing is loading or unavailable.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the help says the line follows streets once a street route is loaded',
      (tester) async {
        await _pump(
          tester,
          _twoStops,
          route: (stops) async => [
            for (final s in stops) s,
            (lat: 10.5, lng: 20.5),
          ],
        );
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump();
        await tester.tap(_button('About this map'));
        await tester.pump();
        expect(
          find.textContaining(
            'The line follows streets; it is an overview, not turn-by-turn directions.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Show every place re-fits the camera', (tester) async {
      await _pump(tester, _sf);
      await _settle(tester);
      final controller = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      controller.move(const ll.LatLng(0, 0), 3);
      await tester.pump();
      expect(find.text('Coit Tower'), findsNothing);
      await tester.tap(_button('Show every place'));
      await tester.pump();
      await _settle(tester);
      expect(find.text('Coit Tower'), findsOneWidget);
      expect(find.text('Golden Gate Bridge'), findsOneWidget);
    });

    testWidgets(
      'the camera starts near the first marker and fits all once ready',
      (tester) async {
        await _pump(tester, _sf);
        final camera = fm.MapController.maybeOf(
          tester.element(find.byType(fm.MarkerLayer)),
        )!.camera;
        expect(camera.center.latitude, closeTo(37.81, 0.05));
        expect(camera.center.longitude, closeTo(-122.43, 0.08));
      },
    );
  });

  group('Map route', () {
    testWidgets('without route=true there is no line', (tester) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)])])',
      );
      expect(_lines(tester), isEmpty);
      expect(find.text('Route overview'), findsNothing);
    });

    testWidgets(
      'with a street route service the street path becomes the polyline',
      (tester) async {
        final asked = <List<LatLng>>[];
        await _pump(
          tester,
          _twoStops,
          route: (stops) async {
            asked.add(stops);
            return [
              (lat: 10.0, lng: 20.0),
              (lat: 10.4, lng: 20.9),
              (lat: 11.0, lng: 21.0),
            ];
          },
        );
        expect(
          _lines(tester).single.points,
          hasLength(2),
          reason: 'straight segments while loading',
        );
        expect(find.text('Route overview'), findsNothing);
        await tester.pump(const Duration(milliseconds: 699));
        expect(asked, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(asked, [
          [(lat: 10.0, lng: 20.0), (lat: 11.0, lng: 21.0)],
        ]);
        await _settle(tester);
        final line = _lines(tester).single;
        expect(line.points, hasLength(3));
        expect(line.points[1].latitude, 10.4);
        expect(line.points[1].longitude, 20.9);
        expect(line.strokeWidth, closeTo(3.2, 0.001));
        expect(find.text('Route overview'), findsNothing);
      },
    );

    testWidgets(
      'a failing street service leaves straight segments and the Route overview badge',
      (tester) async {
        for (final route in <_Route>[
          (stops) async => null,
          (stops) async => throw StateError('offline'),
          (stops) async => [stops.first],
        ]) {
          await _pump(tester, _twoStops, route: route);
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump();
          expect(find.text('Route overview'), findsOneWidget);
          expect(_lines(tester).single.points, hasLength(2));
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('with no street service the overview badge shows right away', (
      tester,
    ) async {
      await _pump(tester, _twoStops);
      expect(find.text('Route overview'), findsOneWidget);
      expect(_lines(tester).single.points, hasLength(2));
    });

    testWidgets('one place has no route', (tester) async {
      await _pump(
        tester,
        'root = Col([Map([MapMarker("A place", 10, 20)], true)])',
      );
      expect(_lines(tester), isEmpty);
      expect(find.text('Route overview'), findsNothing);
    });

    testWidgets('no route is asked for while the program streams', (
      tester,
    ) async {
      var asked = 0;
      await _pump(
        tester,
        _twoStops,
        streaming: true,
        route: (stops) async {
          asked++;
          return null;
        },
      );
      await tester.pump(const Duration(seconds: 2));
      expect(asked, 0);
    });

    testWidgets('the whole route is asked for once the program is complete', (
      tester,
    ) async {
      final asked = <List<LatLng>>[];
      await _pump(
        tester,
        _sf,
        route: (stops) async {
          asked.add(stops);
          return null;
        },
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(asked.single, hasLength(4));
      expect(asked.single.first, (lat: 37.7955, lng: -122.3937));
    });

    testWidgets('the route is asked again for the visible places', (
      tester,
    ) async {
      final asked = <List<LatLng>>[];
      await _pump(
        tester,
        _sf,
        route: (stops) async {
          asked.add(stops);
          return null;
        },
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.tap(find.text('All places'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Views').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(asked, hasLength(2));
      expect(asked.last, hasLength(2));
      expect(asked.last.first, (lat: 37.8024, lng: -122.4058));
    });

    testWidgets('removing the map before the debounce fires is safe', (
      tester,
    ) async {
      var asked = 0;
      final p = await _pump(
        tester,
        _twoStops,
        route: (stops) async {
          asked++;
          return null;
        },
      );
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(asked, 0);
      expect(find.text('gone'), findsOneWidget);
    });

    testWidgets(
      'a slow route that finishes after the places changed is ignored',
      (tester) async {
        final p = await _pump(
          tester,
          _twoStops,
          route: (stops) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return [
              for (var i = 0; i < (stops.last.lat == 11 ? 3 : 4); i++)
                (lat: i.toDouble(), lng: 0.0),
            ];
          },
        );
        await tester.pump(const Duration(milliseconds: 700));
        p.session.update(
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("C place", 12, 22)], true)])',
          streaming: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        expect(
          _lines(tester).single.points,
          hasLength(2),
          reason: 'the old answer (3 points) is dropped',
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();
        expect(_lines(tester).single.points, hasLength(4));
      },
    );
  });

  group('Map Expand', () {
    testWidgets(
      'expands in place over the page with the same live map, and a pin '
      'tap collapses it',
      (tester) async {
        final p = await _pumpAbove(tester, _sf);
        await _settle(tester);
        final before = tester.state(find.byType(fm.FlutterMap));
        await tester.tap(find.text('Expand'));
        await tester.pump();
        expect(find.text('Collapse'), findsOneWidget);
        expect(find.text('Expand'), findsNothing);
        expect(find.byType(fm.FlutterMap), findsOneWidget);
        expect(
          tester.state(find.byType(fm.FlutterMap)),
          same(before),
          reason: 'the map moves into the overlay; it is not a copy',
        );
        expect(find.byType(ModalBarrier), findsWidgets);
        expect(
          tester.getSize(find.byType(fm.FlutterMap)),
          const Size(800 - 48, 600 - 48),
        );

        await tester.tap(find.text('Coit Tower'));
        await tester.pump();
        expect(p.session.state[r'$stop'], 'Coit Tower');
        expect(find.text('Expand'), findsOneWidget);
        expect(tester.getSize(find.byType(fm.FlutterMap)).height, 400);
      },
    );

    testWidgets('Escape and Collapse return the map to the page', (
      tester,
    ) async {
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Expand'), findsOneWidget);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      await tester.tap(find.text('Collapse'));
      await tester.pump();
      expect(find.text('Expand'), findsOneWidget);
    });

    testWidgets('the expanded map keeps mapTiles: null', (tester) async {
      await _pump(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      expect(find.byType(fm.TileLayer), findsNothing);
    });

    testWidgets('a drag before framing keeps the camera where the user left it', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const program =
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)])])';
      final p = await _pump(tester, program, streaming: true);
      final controller = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      await tester.timedDrag(
        find.byType(fm.FlutterMap),
        const Offset(-120, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump();
      final dragged = controller.camera.center;
      expect(dragged, isNot(const ll.LatLng(10, 20)));
      p.session.update(program, streaming: false);
      await tester.pump();
      await _settle(tester);
      expect(controller.camera.center, dragged);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Map framing', () {
    testWidgets('the camera flies to the places over 920ms', (tester) async {
      await _pump(tester, _sf);
      final controller = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      final start = controller.camera.zoom;
      await tester.pump(const Duration(milliseconds: 460));
      final middle = controller.camera.zoom;
      await _settle(tester);
      final end = controller.camera.zoom;
      expect(end, isNot(closeTo(start, 0.01)));
      expect((middle - start).abs(), greaterThan(0.01));
      expect((end - middle).abs(), greaterThan(0.01));
    });

    testWidgets('with reduced motion the camera jumps to the frame', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(tester, _sf);
      final controller = fm.MapController.maybeOf(
        tester.element(find.byType(fm.MarkerLayer)),
      )!;
      final framed = controller.camera.zoom;
      await _settle(tester);
      expect(controller.camera.zoom, framed);

      controller.move(const ll.LatLng(0, 0), 3);
      await tester.pump();
      await tester.tap(_button('Show every place'));
      await tester.pump();
      expect(controller.camera.zoom, greaterThan(10));
      expect(controller.camera.center.latitude, closeTo(37.81, 0.05));
    });

    testWidgets('the back button collapses an expanded map', (tester) async {
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Expand'), findsOneWidget);
    });

    testWidgets('a glass control lightens under the pointer', (tester) async {
      await _pump(tester, _sf);
      Color fill() => tester
          .widget<Material>(
            find
                .ancestor(
                  of: find.text('Expand'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      expect(fill(), OpenUiTheme.light.glass);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Expand')));
      await tester.pump();
      expect(fill(), OpenUiTheme.light.glassHover);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(fill(), OpenUiTheme.light.glass);
    });
  });

  group('Map tiles', () {
    testWidgets('no tiles service shows no tile layer or attribution', (
      tester,
    ) async {
      await _pump(tester, _sf);
      expect(find.byType(fm.TileLayer), findsNothing);
      expect(find.byType(fm.RichAttributionWidget), findsNothing);
    });

    testWidgets(
      'tiles pick the light or dark template and show the attribution',
      (tester) async {
        const tiles = MapTiles(
          light: 'https://tiles.test/light/{z}/{x}/{y}.png',
          dark: 'https://tiles.test/dark/{z}/{x}/{y}.png',
          attribution: 'Tiles by Test',
        );
        _ignoreLogoAsset();
        await _pump(tester, _sf, tiles: tiles);
        expect(
          tester.widget<fm.TileLayer>(find.byType(fm.TileLayer)).urlTemplate,
          tiles.light,
        );
        expect(find.byType(fm.RichAttributionWidget), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, _sf, tiles: tiles, brightness: Brightness.dark);
        expect(
          tester.widget<fm.TileLayer>(find.byType(fm.TileLayer)).urlTemplate,
          tiles.dark,
        );
      },
    );
  });

  group('gallery map program', () {
    testWidgets(
      'shows the starting point and updates it when a pin is tapped',
      (tester) async {
        final p = await _pump(tester, galleryProgram('map'));
        await _settle(tester);
        expect(p.session.issues, isEmpty);
        expect(find.textContaining('Ferry Building'), findsWidgets);
        await tester.tap(find.text('Coit Tower'));
        await tester.pump();
        expect(p.session.state[r'$stop'], 'Coit Tower');
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText() == 'Starting at Coit Tower',
          ),
          findsOneWidget,
        );
        expect(find.text('Route overview'), findsOneWidget);
      },
    );

    testWidgets('renders in dark mode', (tester) async {
      await _pump(tester, galleryProgram('map'), brightness: Brightness.dark);
      expect(find.text('Golden Gate Bridge'), findsOneWidget);
    });
  });
}
