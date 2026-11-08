// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/components/media.dart' show Photo;

import '../support/pump.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Serves a 1x1 PNG for every host except `*.invalid`, which answers 404.
class _FakeHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client();
}

class _Client implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.url);
  final Uri url;

  @override
  HttpHeaders get headers => _Headers();

  @override
  Future<HttpClientResponse> close() async =>
      _Response(url.host.endsWith('.invalid') ? 404 : 200);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode);
  @override
  final int statusCode;

  @override
  int get contentLength => _png.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_png).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

typedef _Search = Future<List<Uri>> Function(String query);

OpenUiServices _services(_Search search) =>
    OpenUiServices(searchImages: search, mapTiles: null);

Finder get _emptyGlyph =>
    find.byWidgetPredicate((w) => w is Glyph && w.name == 'image');

double _ratio(WidgetTester tester) =>
    tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => HttpOverrides.global = _FakeHttp());
  tearDown(() => HttpOverrides.global = null);

  group('Icon', () {
    testWidgets('sizes map sm, md, lg and xl, and md is the default', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([Icon("map-pin", "sm"), Icon("map-pin", "md"), Icon("map-pin", "lg"), Icon("map-pin", "xl"), Icon("map-pin")], 2)',
      );
      final sizes = tester
          .widgetList<Glyph>(find.byType(Glyph))
          .map((g) => g.size)
          .toList();
      expect(sizes, [14, 18, 24, 32, 18]);
    });

    testWidgets(
      'color takes a token or a CSS color, and an unknown icon draws nothing',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Row([Icon("map-pin", "md", "danger"), Icon("map-pin", "md", "#00ff00"), Icon("not-an-icon")], 2)',
        );
        final glyphs = tester.widgetList<Glyph>(find.byType(Glyph)).toList();
        expect(glyphs[0].color, OpenUiTheme.light.status['danger']);
        expect(glyphs[1].color, const Color(0xFF00FF00));
        expect(
          find.descendant(
            of: find.byWidget(glyphs[2]),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byWidget(glyphs[0]),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('names resolve in any case or spacing, and aliases too', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([Icon("MapPin"), Icon("map_pin"), Icon(" map pin "), Icon("alarm-check")], 2)',
      );
      expect(
        find.descendant(
          of: find.byType(Glyph),
          matching: find.byType(CustomPaint),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('strokes are 1.8 grid units wide, scaled with the size', (
      tester,
    ) async {
      Future<int Function(int y)> alphaDownTheMiddle(double strokeWidth) async {
        const key = Key('glyph');
        await tester.pumpWidget(
          Center(
            child: OpenUiScope(
              services: const OpenUiServices(icons: lucideIconResolver),
              child: RepaintBoundary(
                key: key,
                child: Glyph(
                  'minus',
                  size: 240,
                  color: const Color(0xFF000000),
                  strokeWidth: strokeWidth,
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
        ))!;
        return (y) => bytes.getUint8((y * image.width + 120) * 4 + 3);
      }

      // "minus" is M5 12h14: at size 240 its centre line is y = 120.
      final thin = await alphaDownTheMiddle(1.8);
      expect([thin(110), thin(111), thin(128), thin(129)], [0, 255, 255, 0]);
      final lucide = await alphaDownTheMiddle(2);
      expect(
        [lucide(109), lucide(110), lucide(129), lucide(130)],
        [0, 255, 255, 0],
      );
    });
  });

  group('Photo without a search service', () {
    testWidgets('SearchImage shows the empty image glyph and its label', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([SearchImage("Alcatraz Island")])');
      expect(_emptyGlyph, findsOneWidget);
      expect(find.bySemanticsLabel('Alcatraz Island'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Image with an http src uses that url', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Image("https://example.test/a.jpg", "A photo of a tower")])',
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://example.test/a.jpg');
      expect(image.fit, BoxFit.cover);
      expect(image.semanticLabel, 'A photo of a tower');
    });

    testWidgets('fit contain is honored', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Image("https://example.test/a.jpg", "A photo", 1.5, "lg", "contain")])',
      );
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    });

    testWidgets('a src that fails to load settles on the empty glyph', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Image("https://example.invalid/none.jpg", "Palace of Fine Arts")])',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(_emptyGlyph, findsOneWidget);
    });

    testWidgets('a non-http src is ignored', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Image("javascript:alert(1)", "Palace of Fine Arts")])',
      );
      expect(find.byType(Image), findsNothing);
      expect(_emptyGlyph, findsOneWidget);
    });
  });

  group('Photo layout', () {
    testWidgets('aspect ratio is kept between 0.2 and 5, else 1.5', (
      tester,
    ) async {
      Future<double> ratioFor(String value) async {
        await pumpProgram(
          tester,
          'root = Col([SearchImage("Alcatraz", $value)])',
        );
        return _ratio(tester);
      }

      expect(await ratioFor('2'), 2);
      expect(await ratioFor('0.25'), 0.25);
      expect(await ratioFor('4.9'), 4.9);
      expect(await ratioFor('0.2'), 1.5);
      expect(await ratioFor('0.1'), 1.5);
      expect(await ratioFor('5'), 1.5);
      expect(await ratioFor('9'), 1.5);
      expect(await ratioFor('-1'), 1.5);
      expect(await ratioFor('null'), 1.5);
    });

    testWidgets('radius takes a name or px and defaults to lg', (tester) async {
      Future<double> radiusFor(String args) async {
        await pumpProgram(tester, 'root = Col([SearchImage($args)])');
        final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
        return (clip.borderRadius as BorderRadius).topLeft.x;
      }

      expect(await radiusFor('"Alcatraz"'), OpenUiTheme.radiusLg);
      expect(await radiusFor('"Alcatraz", 1, "xl"'), OpenUiTheme.radiusXl);
      expect(await radiusFor('"Alcatraz", 1, "sm"'), OpenUiTheme.radiusSm);
      expect(await radiusFor('"Alcatraz", 1, 3'), 3);
      expect(await radiusFor('"Alcatraz", 1, "full"'), 999);
      expect(await radiusFor('"Alcatraz", 1, "huge"'), OpenUiTheme.radiusLg);
    });

    testWidgets(
      'the placeholder is tinted with the surface color in dark mode',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([SearchImage("Alcatraz")])',
          brightness: Brightness.dark,
        );
        final box = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(ClipRRect),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(box.color, OpenUiTheme.dark.surface);
      },
    );

    testWidgets('a photo in a row is 4:3 whatever its aspect ratio', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([r, b])\n'
        'r = Row([Image("https://example.com/a.jpg", "Tram", 1), Text("Tram 28")])\n'
        'b = Row([Box([SearchImage("Alcatraz", 2)]), Text("Island")])',
      );
      final sizes = tester
          .widgetList<AspectRatio>(find.byType(AspectRatio))
          .map((a) => a.aspectRatio)
          .toList();
      expect(sizes, [4 / 3, 4 / 3]);
      expect(
        tester.getSize(find.byType(AspectRatio).first),
        const Size(200, 150),
      );
    });

    testWidgets(
      'a loaded photo fades in over 300ms, or at once with reduced motion',
      (tester) async {
        Finder fade() => find.descendant(
          of: find.byType(Photo),
          matching: find.byType(AnimatedOpacity),
        );
        await pumpProgram(
          tester,
          'root = Col([Image("https://example.com/a.jpg", "Tram")])',
        );
        expect(
          tester.widget<AnimatedOpacity>(fade()).duration,
          const Duration(milliseconds: 300),
        );
        expect(tester.widget<AnimatedOpacity>(fade()).curve, Curves.ease);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpProgram(
          tester,
          'root = Col([Image("https://example.com/b.jpg", "Bus")])',
        );
        expect(tester.widget<AnimatedOpacity>(fade()).duration, Duration.zero);
      },
    );

    testWidgets('the empty photo icon is drawn at stroke 1.5', (tester) async {
      await pumpProgram(tester, 'root = Col([SearchImage("Alcatraz")])');
      expect(tester.widget<Glyph>(find.byType(Glyph)).strokeWidth, 1.5);
    });
  });

  group('Photo with a search service', () {
    testWidgets('the query waits 500ms, then the first result loads', (
      tester,
    ) async {
      final queries = <String>[];
      final a = Uri.parse('https://example.test/first.jpg');
      final b = Uri.parse('https://example.test/second.jpg');
      await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower Lisbon")])',
        services: _services((q) async {
          queries.add(q);
          return [a, b];
        }),
      );
      await tester.pump(const Duration(milliseconds: 499));
      expect(queries, isEmpty);
      expect(find.byType(Image), findsNothing);
      expect(_emptyGlyph, findsNothing, reason: 'still waiting, not settled');

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(queries, ['Belem Tower Lisbon']);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, a.toString());
    });

    testWidgets(
      'a failing image falls back to the next result, then to the glyph',
      (tester) async {
        final dead = Uri.parse('https://example.invalid/1.jpg');
        final alive = Uri.parse('https://example.test/2.jpg');
        Future<void> failures() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          await tester.pump();
        }

        await pumpProgram(
          tester,
          'root = Col([SearchImage("Belem Tower Lisbon")])',
          services: _services((q) async => [dead, alive]),
        );
        await _settle(tester);
        await failures();
        expect(
          (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
          alive.toString(),
        );

        await tester.pumpWidget(const SizedBox());
        await pumpProgram(
          tester,
          'root = Col([SearchImage("Palace of Fine Arts")])',
          services: _services(
            (q) async => [dead, Uri.parse('https://example.invalid/3.jpg')],
          ),
        );
        await _settle(tester);
        await failures();
        await failures();
        expect(find.byType(Image), findsNothing);
        expect(_emptyGlyph, findsOneWidget);
      },
    );

    testWidgets('Image with a non-http src searches its alt text', (
      tester,
    ) async {
      final queries = <String>[];
      await pumpProgram(
        tester,
        'root = Col([Image("not a url", "Palace of Fine Arts")])',
        services: _services((q) async {
          queries.add(q);
          return [Uri.parse('https://example.test/palace.jpg')];
        }),
      );
      await _settle(tester);
      expect(queries, ['Palace of Fine Arts']);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
        'https://example.test/palace.jpg',
      );
    });

    testWidgets('Image with a good src does not search until it fails', (
      tester,
    ) async {
      final queries = <String>[];
      await pumpProgram(
        tester,
        'root = Col([Image("https://example.test/good.jpg", "Palace of Fine Arts")])',
        services: _services((q) async {
          queries.add(q);
          return [];
        }),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(queries, isEmpty);
    });

    testWidgets('a failing src falls back to a search of its alt', (
      tester,
    ) async {
      final queries = <String>[];
      await pumpProgram(
        tester,
        'root = Col([Image("https://example.invalid/palace.jpg", "Palace of Fine Arts")])',
        services: _services((q) async {
          queries.add(q);
          return [Uri.parse('https://example.test/found.jpg')];
        }),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      await _settle(tester);
      expect(queries, ['Palace of Fine Arts']);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as NetworkImage).url,
        'https://example.test/found.jpg',
      );
    });

    testWidgets('queries of two letters or fewer never search', (tester) async {
      final queries = <String>[];
      await pumpProgram(
        tester,
        'root = Col([SearchImage("ab"), SearchImage("   "), SearchImage("")])',
        services: _services((q) async {
          queries.add(q);
          return [];
        }),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(queries, isEmpty);
      expect(_emptyGlyph, findsNWidgets(3));
    });

    testWidgets(
      'a query that changes while streaming searches only the last one',
      (tester) async {
        final queries = <String>[];
        final pumped = await pumpProgram(
          tester,
          'root = Col([SearchImage("Belem")])',
          streaming: true,
          services: _services((q) async {
            queries.add(q);
            return [Uri.parse('https://example.test/x.jpg')];
          }),
        );
        await tester.pump(const Duration(milliseconds: 300));
        pumped.session.update(
          'root = Col([SearchImage("Belem Tower")])',
          streaming: true,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        pumped.session.update(
          'root = Col([SearchImage("Belem Tower Lisbon")])',
          streaming: false,
        );
        await tester.pump();
        await _settle(tester);
        expect(queries, ['Belem Tower Lisbon']);
      },
    );

    testWidgets(
      'equal queries share one request, and urls are filtered and de-duplicated',
      (tester) async {
        var calls = 0;
        await pumpProgram(
          tester,
          'root = Col([SearchImage("Belem Tower"), SearchImage("Belem Tower")])',
          services: _services((q) async {
            calls++;
            return [
              Uri.parse('ftp://example.test/no.jpg'),
              Uri.parse('https://example.test/a.jpg'),
              Uri.parse('https://example.test/a.jpg'),
            ];
          }),
        );
        await _settle(tester);
        expect(calls, 1);
        final images = tester
            .widgetList<Image>(find.byType(Image))
            .map((i) => (i.image as NetworkImage).url);
        expect(images, [
          'https://example.test/a.jpg',
          'https://example.test/a.jpg',
        ]);
      },
    );

    testWidgets('an error or an empty answer is retried the next time', (
      tester,
    ) async {
      var calls = 0;
      Future<List<Uri>> search(String q) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        if (calls == 2) return [];
        return [Uri.parse('https://example.test/ok.jpg')];
      }

      final services = _services(search);
      await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 1);
      expect(_emptyGlyph, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 2);
      expect(_emptyGlyph, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 3);
      expect(find.byType(Image), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 3, reason: 'a good answer is cached');
    });

    testWidgets('no results settles on the glyph', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([SearchImage("qzxv unfindable subject 0000")])',
        services: _services((q) async => []),
      );
      await _settle(tester);
      expect(_emptyGlyph, findsOneWidget);
    });

    testWidgets('removing the photo while a search is pending is safe', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([SearchImage("Belem Tower")])',
        services: _services(
          (q) async => [Uri.parse('https://example.test/a.jpg')],
        ),
      );
      pumped.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('gone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cache holds at most 200 queries', (tester) async {
      var calls = 0;
      final services = _services((q) async {
        calls++;
        return [
          Uri.parse('https://example.test/${q.replaceAll(' ', '_')}.jpg'),
        ];
      });
      for (var i = 0; i < 202; i++) {
        await tester.pumpWidget(const SizedBox());
        await pumpProgram(
          tester,
          'root = Col([SearchImage("query number $i")])',
          services: services,
        );
        await _settle(tester);
      }
      expect(calls, 202);
      await pumpProgram(
        tester,
        'root = Col([SearchImage("query number 201")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 202, reason: 'newest is cached');
      await tester.pumpWidget(const SizedBox());
      await pumpProgram(
        tester,
        'root = Col([SearchImage("query number 0")])',
        services: services,
      );
      await _settle(tester);
      expect(calls, 203, reason: 'oldest was dropped');
    });
  });
}
