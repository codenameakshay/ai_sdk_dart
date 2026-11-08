// ignore_for_file: implementation_imports
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_maps/src/map.dart'
    show flyPath, pinEmoji, placesOf;

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
      expect(
        pinEmoji('🇵🇹'),
        isNull,
        reason: 'regional indicators are not Extended_Pictographic',
      );
      expect(pinEmoji('\u{1FAE8}'), '\u{1FAE8}');
      expect(pinEmoji('▪️'), '▪️');
      expect(pinEmoji('⬀'), isNull);
      expect(pinEmoji('⇿'), isNull);
      expect(pinEmoji('#️⃣'), isNull);
      expect(pinEmoji('👍🏽'), '👍🏽');
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
      expect(
        tester.widget<Text>(find.text('2')).style!.fontWeight,
        OpenUiTheme.weightSemibold,
      );
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

    testWidgets(
      'Expand and About this map are buttons with an expanded state',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _sf);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Expand')),
          isSemantics(isButton: true, isExpanded: false),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('About this map')),
          isSemantics(isButton: true, isExpanded: false),
        );
        await tester.tap(find.bySemanticsLabel('About this map'));
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('About this map')),
          isSemantics(isButton: true, isExpanded: true),
        );
        await tester.tap(find.text('Expand'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Collapse')),
          isSemantics(isButton: true, isExpanded: true),
        );
        handle.dispose();
      },
    );

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
    testWidgets(
      'icons keep map.tsx\'s stroke widths; the pill text is medium',
      (tester) async {
        await _pump(tester, _sf);
        double stroke(String name) => tester
            .widget<Glyph>(
              find.byWidgetPredicate((w) => w is Glyph && w.name == name),
            )
            .strokeWidth;
        // 1.6 on a 16 grid at 14px, 1.6 on 24 at 22px, 1.5 on 20 at 18px and
        // 1.6 on 20 at 14px, in Glyph's 24 grid.
        expect(stroke('chevron-down'), 2.4);
        expect(stroke('navigation'), 1.6);
        expect(stroke('info'), 1.8);
        expect(stroke('expand'), 1.92);
        expect(
          tester.widget<Text>(find.text('Expand')).style!.fontWeight,
          OpenUiTheme.weightMedium,
        );
      },
    );

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
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
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
        expect(_lines(tester), isEmpty, reason: 'frame before route line');
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
          await _settle(tester);
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
      expect(_lines(tester), isEmpty);
      await _settle(tester);
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

    testWidgets('a pin takes keyboard focus; Enter and Space select it', (
      tester,
    ) async {
      final p = await _pump(tester, _sf);
      await _settle(tester);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      Focus.of(tester.element(find.text('Coit Tower'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(p.session.state[r'$stop'], 'Coit Tower');
      final outline = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == null &&
            (w.decoration as BoxDecoration).border?.top.width == 2,
      );
      final box = find
          .ancestor(
            of: find.text('Coit Tower'),
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == 160 && w.height == 52,
            ),
          )
          .first;
      expect(
        tester.getRect(outline),
        Rect.fromLTWH(
          tester.getTopLeft(box).dx + 58,
          tester.getTopLeft(box).dy - 5,
          44,
          62,
        ),
      );
      Focus.of(tester.element(find.text('Golden Gate Bridge'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(p.session.state[r'$stop'], 'Golden Gate Bridge');
    });

    testWidgets('a new pin fades and scales in over 104ms', (tester) async {
      await _pump(tester, _sf);
      FadeTransition fade() => tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Coit Tower'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      final scale = tester.widget<ScaleTransition>(
        find
            .ancestor(
              of: find.text('Coit Tower'),
              matching: find.byType(ScaleTransition),
            )
            .first,
      );
      expect(scale.alignment, const Alignment(0, 17 / 26 - 1));
      expect(fade().opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 104));
      expect(fade().opacity.value, 1);
      expect(scale.scale.value, 1);
    });

    testWidgets('with reduced motion pins appear at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _pump(tester, _sf);
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.text('Coit Tower'),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
    });

    testWidgets('pin labels use Arial and carry the label as a hover title', (
      tester,
    ) async {
      await _pump(tester, _sf);
      final style = tester.widget<Text>(find.text('Coit Tower')).style!;
      expect(style.fontFamily, 'Arial');
      expect(style.fontFamilyFallback, ['Helvetica']);
      expect(style.fontWeight, OpenUiTheme.weightSemibold);
      expect(find.byTooltip('Coit Tower'), findsOneWidget);
    });
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

    testWidgets('the expanded map stays inside the safe area', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
      addTearDown(tester.view.resetPadding);
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      final map = tester.getRect(find.byType(fm.FlutterMap));
      expect(map.top, 62 + 24);
      expect(map.bottom, 600 - 34 - 24);
    });

    testWidgets('screen readers reach the expanded map and its controls', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      expect(find.semantics.byLabel('Collapse').evaluate(), hasLength(1));
      expect(find.semantics.byLabel('Coit Tower').evaluate(), isNotEmpty);
      expect(find.semantics.byLabel('Zoom in').evaluate(), hasLength(1));
      handle.dispose();
    });

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

    testWidgets(
      'the expanded map hides the rest of the page from screen readers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpAbove(
          tester,
          _sf.replaceFirst(
            'root = Col([map])',
            'root = Col([Text("Before the map"), map])',
          ),
        );
        expect(find.semantics.byLabel('Before the map').evaluate(), isNotEmpty);
        await tester.tap(find.text('Expand'));
        await tester.pump();
        expect(find.semantics.byLabel('Before the map').evaluate(), isEmpty);
        expect(find.semantics.byLabel('Coit Tower').evaluate(), isNotEmpty);
        expect(find.semantics.byLabel('Collapse').evaluate(), hasLength(1));
        await tester.tap(find.text('Collapse'));
        await tester.pump();
        expect(find.semantics.byLabel('Before the map').evaluate(), isNotEmpty);
        handle.dispose();
      },
    );

    testWidgets('a map removed while expanded takes its overlay with it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final p = await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      p.session.update('root = Col([Text("No map")])', streaming: false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(fm.FlutterMap), findsNothing);
      expect(find.semantics.byLabel('No map').evaluate(), isNotEmpty);
      handle.dispose();
    });

    testWidgets('the info button works inside the expanded map', (
      tester,
    ) async {
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      await tester.tap(_button('About this map'));
      await tester.pump();
      expect(find.textContaining('Drag to explore'), findsOneWidget);
    });

    testWidgets('popping the expanded route from elsewhere collapses it', (
      tester,
    ) async {
      await _pumpAbove(tester, _sf);
      await tester.tap(find.text('Expand'));
      await tester.pump();
      Navigator.of(tester.element(find.text('Collapse'))).pop();
      await tester.pump();
      await tester.pump();
      expect(find.text('Expand'), findsOneWidget);
      expect(tester.getSize(find.byType(fm.FlutterMap)).height, 400);
    });

    testWidgets(
      'the expanded map keeps Tab inside, in DOM order, and Escape returns focus to Expand',
      (tester) async {
        await _pumpAbove(
          tester,
          _sf.replaceFirst(
            'root = Col([map])',
            'root = Col([Button("Outside"), map])',
          ),
        );
        await _settle(tester);
        FocusNode node(Finder f) => Focus.of(tester.element(f));
        final expand = node(find.text('Expand'));
        expand.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();
        expect(find.text('Collapse'), findsOneWidget);
        final order = [
          for (final label in [
            'Ferry Building',
            'Coit Tower',
            'Palace of Fine Arts',
            'Golden Gate Bridge',
          ])
            node(find.text(label)),
          node(find.byTooltip('Zoom in')),
          node(find.byTooltip('Zoom out')),
          isA<FocusNode>().having(
            (n) => n.debugLabel,
            'debugLabel',
            'DropdownButton<String>',
          ),
          node(
            find.byWidgetPredicate((w) => w is Glyph && w.name == 'navigation'),
          ),
          node(find.byWidgetPredicate((w) => w is Glyph && w.name == 'info')),
          node(find.text('Collapse')),
        ];
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'FlutterMap');
        for (final expected in order) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            FocusManager.instance.primaryFocus,
            expected is FocusNode ? same(expected) : expected,
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'FlutterMap',
          reason: 'wraps to the first',
        );
        await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          same(order.last),
          reason: 'Shift+Tab wraps to the last',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.text('Expand'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, same(expand));
      },
    );

    testWidgets('glass controls blur what is behind them', (tester) async {
      await _pump(tester, _sf);
      expect(
        find.ancestor(
          of: find.text('Expand'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byTooltip('Zoom in'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
    });
  });

  group('Map camera', () {
    fm.MapController controllerOf(WidgetTester tester) =>
        fm.MapController.maybeOf(tester.element(find.byType(fm.MarkerLayer)))!;

    void reducedMotion(WidgetTester tester) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    Offset shift(fm.MapCamera c, ll.LatLng p) =>
        c.projectAtZoom(p) - c.projectAtZoom(c.center);

    testWidgets(
      'an empty map shows the world: lat 20, lng 0, MapLibre zoom 1',
      (tester) async {
        await _pump(tester, 'root = Col([Map([])])');
        final c = controllerOf(tester).camera;
        expect(c.center, const ll.LatLng(20, 0));
        expect(c.zoom, 2);
      },
    );

    testWidgets(
      'the camera anchors on the first marker as soon as it streams in',
      (tester) async {
        final p = await _pump(
          tester,
          'root = Col([Map([MapMarker("A pl',
          streaming: true,
        );
        final controller = controllerOf(tester);
        expect(controller.camera.zoom, 2);
        p.session.update(
          'root = Col([Map([MapMarker("A place", 10, 20)])])',
          streaming: true,
        );
        await tester.pump();
        await tester.pump();
        expect(controller.camera.center, const ll.LatLng(10, 20));
        expect(controller.camera.zoom, 11.5);
        p.session.update(
          'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)])])',
          streaming: false,
        );
        await tester.pump();
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 200));
        final fit = fm.CameraFit.coordinates(
          coordinates: const [ll.LatLng(10, 20), ll.LatLng(11, 21)],
          padding: const EdgeInsets.fromLTRB(72, 70, 72, 50),
          maxZoom: 14,
        ).fit(controller.camera);
        expect(controller.camera.zoom, closeTo(fit.zoom, 1e-6));
        expect(
          controller.camera.center.latitude,
          closeTo(fit.center.latitude, 1e-6),
        );
      },
    );

    testWidgets(
      'one place is framed at MapLibre zoom 13, 10px low for the controls',
      (tester) async {
        reducedMotion(tester);
        await _pump(tester, 'root = Col([Map([MapMarker("Solo", 10, 20)])])');
        final c = controllerOf(tester).camera;
        expect(c.zoom, 14);
        final s = shift(c, const ll.LatLng(10, 20));
        expect(s.dx, closeTo(0, 1e-6));
        expect(s.dy, closeTo(10, 1e-6));
      },
    );

    testWidgets('Show every place frames one place at MapLibre zoom 14', (
      tester,
    ) async {
      reducedMotion(tester);
      await _pump(tester, 'root = Col([Map([MapMarker("Solo", 10, 20)])])');
      final controller = controllerOf(tester);
      controller.move(const ll.LatLng(0, 0), 3);
      await tester.pump();
      await tester.tap(_button('Show every place'));
      await tester.pump();
      expect(controller.camera.zoom, 15);
      final s = shift(controller.camera, const ll.LatLng(10, 20));
      expect(s.dx, closeTo(-3, 1e-6));
      expect(s.dy, closeTo(10, 1e-6));
    });

    testWidgets('two places fit between the frame padding', (tester) async {
      reducedMotion(tester);
      await _pump(
        tester,
        'root = Col([Map([MapMarker("West", 0, -1), MapMarker("East", 0, 1)])])',
      );
      final w = tester.getSize(find.byType(fm.FlutterMap)).width;
      // 2 degrees of longitude fill w - 144 pixels: 2/360 * 256 * 2^z = w - 144.
      expect(
        controllerOf(tester).camera.zoom,
        closeTo(math.log((w - 144) * 360 / 512) / math.ln2, 1e-9),
      );
    });
  });

  group('flyPath', () {
    test('a level pan arcs out and back like MapLibre', () {
      final p = flyPath(w0: 768, u1: 1000, z0: 10, z1: 10, minZoom: 1)!;
      expect(p.length, closeTo(1.529869440230, 1e-9));
      expect(p.at(0.25).zoom, closeTo(9.480376921586, 1e-9));
      expect(p.at(0.25).along, closeTo(0.188661126765, 1e-9));
      expect(p.at(0.5).zoom, closeTo(9.277311468756, 1e-9));
      expect(p.at(0.5).along, closeTo(0.5, 1e-9));
      expect(p.at(1).zoom, 10);
      expect(p.at(1).along, 1);
    });

    test('a zoom in place follows the exponential path', () {
      final p = flyPath(w0: 768, u1: 0, z0: 10, z1: 12, minZoom: 1)!;
      expect(p.length, closeTo(0.976263634591, 1e-9));
      expect(p.at(0.5).zoom, closeTo(11, 1e-9));
      expect(p.at(0.5).along, 0);
    });

    test('a zoom out while panning', () {
      final p = flyPath(w0: 768, u1: 300, z0: 11.5, z1: 9, minZoom: 1)!;
      expect(p.at(0.5).zoom, closeTo(10.239971006084, 1e-9));
      expect(p.at(0.5).along, closeTo(0.150221104822, 1e-9));
    });

    test('no movement is no flight', () {
      expect(flyPath(w0: 768, u1: 0, z0: 10, z1: 10, minZoom: 1), isNull);
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
        expect(find.byType(fm.RichAttributionWidget), findsNothing);
        final credit = find.text('Tiles by Test');
        expect(credit, findsOneWidget);
        expect(tester.widget<Text>(credit).style!.fontSize, 8);
        expect(
          tester.getBottomLeft(credit),
          tester.getBottomLeft(find.byType(fm.FlutterMap)) +
              const Offset(4, -1),
        );
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
