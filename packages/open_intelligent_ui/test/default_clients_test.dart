// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/components/media.dart'
    show MediaRowSlot;

import 'support/pump.dart';

const _carousel =
    'root = Col([Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")], 400)])';

Finder get _horizontal =>
    find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.horizontal);

double _pixels(WidgetTester tester) =>
    tester.state<ScrollableState>(_horizontal).position.pixels;

void main() {
  group('services built without a client', () {
    test('OsrmStreetRoute uses the ambient http client', () async {
      late Uri seen;
      final route = await http.runWithClient(
        () => OsrmStreetRoute()([
          (lat: 38.69, lng: -9.21),
          (lat: 38.71, lng: -9.13),
        ]),
        () => MockClient((request) async {
          seen = request.url;
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': {
                    'coordinates': [
                      [-9.21, 38.69],
                      [-9.13, 38.71],
                    ],
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      expect(seen.host, 'router.project-osrm.org');
      expect(route, [(lat: 38.69, lng: -9.21), (lat: 38.71, lng: -9.13)]);
    });

    test('WikimediaImageSearch uses the ambient http client', () async {
      final hosts = <String>[];
      final urls = await http.runWithClient(
        () => WikimediaImageSearch()('Belem Tower'),
        () => MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('{}', 200);
        }),
      );
      expect(hosts, isNotEmpty);
      expect(hosts.toSet(), everyElement(endsWith('.org')));
      expect(urls, isEmpty);
    });
  });

  group('MediaRowSlot', () {
    testWidgets('stays marked when it is rebuilt around the same child', (
      tester,
    ) async {
      final marked = <bool>[];
      Widget app(int n) => MediaRowSlot(
        child: Builder(
          builder: (context) {
            marked.add(MediaRowSlot.of(context));
            return Text('rebuild $n', textDirection: TextDirection.ltr);
          },
        ),
      );
      await tester.pumpWidget(app(1));
      await tester.pumpWidget(app(2));
      expect(find.text('rebuild 2'), findsOneWidget);
      expect(marked, [true, true]);
    });
  });

  group('Carousel snapping', () {
    testWidgets('a short fling forward goes to the next item', (tester) async {
      await pumpProgram(tester, _carousel);
      await tester.fling(find.text('One'), const Offset(-100, 0), 1000);
      await tester.pumpAndSettle();
      expect(_pixels(tester), closeTo(412, 0.5));
    });

    testWidgets('a short fling back goes to the previous item', (tester) async {
      await pumpProgram(tester, _carousel);
      await tester.drag(find.text('One'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(_pixels(tester), closeTo(412, 0.5));
      await tester.fling(find.text('Two'), const Offset(100, 0), 1000);
      await tester.pumpAndSettle();
      expect(_pixels(tester), closeTo(0, 0.5));
    });

    testWidgets('overscroll on a bouncing platform springs back to the start', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpProgram(tester, _carousel);
        await tester.drag(find.text('One'), const Offset(120, 0));
        await tester.pump();
        expect(_pixels(tester), lessThan(0));
        await tester.pumpAndSettle();
        expect(_pixels(tester), 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('generated element ids', () {
    testWidgets('a Form without a statement name is named after its id', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([Form([Input("", "Name"), Button("Send", @ToAssistant("Hi"))])])',
      );
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(pumped.events.single.formName, 'root/children.0');
    });
  });
}
