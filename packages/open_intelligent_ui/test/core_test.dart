// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/css_color.dart';
import 'package:open_intelligent_ui_core/src/view.dart' show webUri;

import 'support/pump.dart';

Matcher _rgba(int r, int g, int b, [int a = 255]) => predicate<Color?>((c) {
  if (c == null) return false;
  int ch(double v) => (v * 255).round();
  return (ch(c.r) - r).abs() <= 1 &&
      (ch(c.g) - g).abs() <= 1 &&
      (ch(c.b) - b).abs() <= 1 &&
      (ch(c.a) - a).abs() <= 1;
}, 'is rgba($r, $g, $b, $a)');

void main() {
  group('parseCssColor', () {
    test('hex in 3, 4, 6 and 8 digits', () {
      expect(parseCssColor('#abc'), const Color(0xFFAABBCC));
      expect(parseCssColor('#abcd'), const Color(0xDDAABBCC));
      expect(parseCssColor('#aabbcc'), const Color(0xFFAABBCC));
      expect(parseCssColor('#AABBCC80'), const Color(0x80AABBCC));
      expect(parseCssColor('  #FFF  '), const Color(0xFFFFFFFF));
    });

    test('rgb() and rgba() with commas, spaces, slash alpha and percents', () {
      expect(parseCssColor('rgb(255, 0, 0)'), _rgba(255, 0, 0));
      expect(parseCssColor('rgb(10 20 30)'), _rgba(10, 20, 30));
      expect(parseCssColor('rgba(0, 0, 255, 0.5)'), _rgba(0, 0, 255, 128));
      expect(parseCssColor('rgb(0 255 0 / 50%)'), _rgba(0, 255, 0, 128));
      expect(parseCssColor('rgb(100%, 0%, 50%)'), _rgba(255, 0, 128));
      expect(parseCssColor('RGB(1,2,3)'), _rgba(1, 2, 3));
    });

    test('out-of-range channels and alpha clamp', () {
      expect(parseCssColor('rgb(300, -5, 0)'), _rgba(255, 0, 0));
      expect(parseCssColor('rgba(0, 0, 0, 7)'), _rgba(0, 0, 0));
      expect(parseCssColor('rgba(0, 0, 0, -1)'), _rgba(0, 0, 0, 0));
    });

    test('hsl() reaches every hue sector', () {
      expect(parseCssColor('hsl(0, 100%, 50%)'), _rgba(255, 0, 0));
      expect(parseCssColor('hsl(60, 100%, 50%)'), _rgba(255, 255, 0));
      expect(parseCssColor('hsl(120, 100%, 50%)'), _rgba(0, 255, 0));
      expect(parseCssColor('hsl(180, 100%, 50%)'), _rgba(0, 255, 255));
      expect(parseCssColor('hsl(240deg 100% 50%)'), _rgba(0, 0, 255));
      expect(parseCssColor('hsl(300, 100%, 50%)'), _rgba(255, 0, 255));
      expect(parseCssColor('hsl(-60, 100%, 50%)'), _rgba(255, 0, 255));
      expect(parseCssColor('hsl(0, 100%, 25%)'), _rgba(128, 0, 0));
      expect(parseCssColor('hsl(0, 0%, 50%)'), _rgba(128, 128, 128));
      expect(parseCssColor('hsla(240, 100%, 50%, 0.5)'), _rgba(0, 0, 255, 128));
    });

    test('named colors and transparent', () {
      expect(parseCssColor('red'), const Color(0xFFFF0000));
      expect(parseCssColor(' RebeccaPurple '), const Color(0xFF663399));
      expect(parseCssColor('transparent'), const Color(0x00000000));
    });

    test('anything that is not a color is null', () {
      for (final bad in [
        'url(https://x.test/a.png)',
        'var(--x)',
        'rgb(url(x))',
        '#12',
        '#12345',
        'rgb(1, 2)',
        'rgb(1, 2, 3, 4, 5)',
        'rgb(a, b, c)',
        'rgb(1, 2, 3, x)',
        'hsl(x, 1, 1)',
        'hsl(0, 50%, y)',
        'notacolor',
        '',
        'calc(1+2)',
      ]) {
        expect(parseCssColor(bad), isNull, reason: bad);
      }
    });
  });

  group('OpenUiTheme tokens', () {
    final t = OpenUiTheme.light;

    test('fg resolves tokens, statuses, charts and CSS colors', () {
      expect(t.fg('ink'), t.ink);
      expect(t.fg('muted'), t.muted);
      expect(t.fg('faint'), t.muted);
      expect(t.fg('canvas'), t.canvas);
      expect(t.fg('surface'), t.surface);
      expect(t.fg('success'), t.status['success']);
      expect(t.fg('info'), t.status['info']);
      expect(t.fg('chart1'), t.chart[0]);
      expect(t.fg('chart6'), t.chart[5]);
      expect(t.fg('chart7'), isNull);
      expect(t.fg('#ff0000'), const Color(0xFFFF0000));
      expect(t.fg('nonsense'), isNull);
      expect(t.fg(12), isNull);
      expect(t.fg(null), isNull);
    });

    test('bg turns statuses into soft tints and allows border tokens', () {
      expect(t.bg('success'), t.statusSoft['success']);
      expect(t.bg('info'), t.statusSoft['info']);
      expect(t.bg('surface-strong'), t.surfaceStrong);
      expect(t.bg('border'), t.border);
      expect(t.bg('chart3'), t.chart[2]);
      expect(t.bg('ink'), t.ink);
      expect(t.bg('#fff'), const Color(0xFFFFFFFF));
      expect(t.bg('url(x)'), isNull);
      expect(t.bg(3), isNull);
    });

    test('inkOn picks readable ink for raw colors only', () {
      expect(t.inkOn('#ffffff'), const Color(0xFF0D0D0D));
      expect(t.inkOn('#000000'), const Color(0xFFFFFFFF));
      expect(t.inkOn('#0285ff'), const Color(0xFFFFFFFF));
      expect(t.inkOn('#fde68a'), const Color(0xFF0D0D0D));
      expect(t.inkOn('transparent'), isNull);
      for (final token in [
        'ink',
        'success',
        'border',
        'surface-strong',
        'chart2',
      ]) {
        expect(t.inkOn(token), isNull, reason: token);
      }
      expect(t.inkOn('nonsense'), isNull);
      expect(t.inkOn(null), isNull);
      expect(t.inkOn(5), isNull);
    });

    test('derived tints follow the ink and the dark palette differs', () {
      expect(t.surface.a, closeTo(0.04, 0.001));
      expect(t.border.a, closeTo(0.08, 0.001));
      expect(t.borderStrong.a, closeTo(0.10, 0.001));
      expect(t.hover.a, closeTo(0.05, 0.001));
      expect(t.pressed.a, closeTo(0.08, 0.001));
      expect(t.rangeTrack.a, closeTo(0.06, 0.001));
      expect(t.badgeNeutralSoft.a, closeTo(0.06, 0.001));
      expect(t.surfaceHover.a, closeTo(0.08, 0.001));
      expect(t.inkHover, isNot(t.ink));
      expect(OpenUiTheme.dark.ink, isNot(t.ink));
      expect(OpenUiTheme.dark.brightness, Brightness.dark);
      expect(OpenUiTheme.dark.fg('danger'), OpenUiTheme.dark.status['danger']);
    });

    test('space counts 4px steps and is never negative', () {
      expect(OpenUiTheme.space(3), 12);
      expect(OpenUiTheme.space(0.5), 2);
      expect(OpenUiTheme.space(-2), 0);
      expect(OpenUiTheme.space('3'), isNull);
      expect(OpenUiTheme.space(double.nan), isNull);
      expect(OpenUiTheme.space(double.infinity), isNull);
    });

    test('length reads px, numeric strings and percents', () {
      expect(OpenUiTheme.length(5), (px: 5.0, fraction: null));
      expect(OpenUiTheme.length(-3), (px: 0.0, fraction: null));
      expect(OpenUiTheme.length('12px'), (px: 12.0, fraction: null));
      expect(OpenUiTheme.length(' 8 '), (px: 8.0, fraction: null));
      expect(OpenUiTheme.length('50%'), (px: null, fraction: 0.5));
      expect(OpenUiTheme.length('abc'), (px: null, fraction: null));
      expect(OpenUiTheme.length('-4px'), (px: null, fraction: null));
      expect(OpenUiTheme.length(double.nan), (px: null, fraction: null));
      expect(OpenUiTheme.length(true), (px: null, fraction: null));
      expect(OpenUiTheme.length(null), (px: null, fraction: null));
    });

    test('radius takes names or px', () {
      expect(OpenUiTheme.radius('sm'), OpenUiTheme.radiusSm);
      expect(OpenUiTheme.radius('md'), OpenUiTheme.radiusMd);
      expect(OpenUiTheme.radius('lg'), OpenUiTheme.radiusLg);
      expect(OpenUiTheme.radius('xl'), OpenUiTheme.radiusXl);
      expect(OpenUiTheme.radius('full'), 999);
      expect(OpenUiTheme.radius(8), 8);
      expect(OpenUiTheme.radius('7px'), 7);
      expect(OpenUiTheme.radius('huge'), isNull);
      expect(OpenUiTheme.radius(null), isNull);
    });

    test('copyWith replaces only what it is given', () {
      final c = t.copyWith(ink: const Color(0xFFFF0000), fontFamily: 'Inter');
      expect(c.ink, const Color(0xFFFF0000));
      expect(c.fontFamily, 'Inter');
      expect(c.canvas, t.canvas);
      expect(c.muted, t.muted);
      expect(c.status, t.status);
      expect(c.brightness, Brightness.light);
      final d = t.copyWith(
        canvas: const Color(0xFF111111),
        onInk: const Color(0xFF222222),
        muted: const Color(0xFF333333),
      );
      expect(d.canvas, const Color(0xFF111111));
      expect(d.onInk, const Color(0xFF222222));
      expect(d.muted, const Color(0xFF333333));
      expect(d.ink, t.ink);
    });

    test('withInk swaps the ink and softens the muted color from it', () {
      final w = t.withInk(const Color(0xFFFFFFFF));
      expect(w.ink, const Color(0xFFFFFFFF));
      expect(w.muted.a, closeTo(0.72, 0.01));
      expect(w.muted.r, 1);
    });

    test('lerp blends two themes and keeps its own for null', () {
      expect(t.lerp(null, 0.5), same(t));
      final start = t.lerp(OpenUiTheme.dark, 0);
      expect(start.canvas, t.canvas);
      expect(start.brightness, Brightness.light);
      expect(start.chart[0], t.chart[0]);
      expect(start.fontFamily, t.fontFamily);
      final end = t.lerp(OpenUiTheme.dark, 1);
      expect(end.canvas, OpenUiTheme.dark.canvas);
      expect(end.brightness, Brightness.dark);
      expect(end.status['success'], OpenUiTheme.dark.status['success']);
      expect(end.chart[2], OpenUiTheme.dark.chart[2]);
      expect(end.mapWater, OpenUiTheme.dark.mapWater);
      final mid = t.lerp(OpenUiTheme.dark, 0.5);
      expect(mid.canvas, Color.lerp(t.canvas, OpenUiTheme.dark.canvas, 0.5));
      expect(mid.ink, isNot(t.ink));
      expect(mid.shadow.single.blurRadius, 20);
    });
  });

  group('OpenUiTheme.of', () {
    Future<OpenUiTheme> read(WidgetTester tester, ThemeData theme) async {
      late OpenUiTheme found;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              found = OpenUiTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return found;
    }

    testWidgets('light and dark apps get the matching tokens', (tester) async {
      expect(await read(tester, ThemeData()), same(OpenUiTheme.light));
      expect(
        await read(tester, ThemeData(brightness: Brightness.dark)),
        same(OpenUiTheme.dark),
      );
    });

    testWidgets('a registered extension wins', (tester) async {
      final custom = OpenUiTheme.light.copyWith(ink: const Color(0xFF123456));
      final found = await read(tester, ThemeData(extensions: [custom]));
      expect(found.ink, const Color(0xFF123456));
    });
  });

  group('OpenUiServices', () {
    testWidgets('given callbacks are used', (tester) async {
      final opened = <Uri>[];
      final copied = <String>[];
      final services = OpenUiServices(
        openUrl: (u) async => opened.add(u),
        copyText: (t) async => copied.add(t),
      );
      await services.openUrl(Uri.parse('https://a.test'));
      await services.copyText('hi');
      expect(opened, [Uri.parse('https://a.test')]);
      expect(copied, ['hi']);
    });

    testWidgets('the default copy uses the system clipboard', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await const OpenUiServices().copyText('to clipboard');
      final set = calls.singleWhere((c) => c.method == 'Clipboard.setData');
      expect((set.arguments as Map)['text'], 'to clipboard');
    });

    testWidgets('the umbrella view launches urls outside the app by default', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await const OpenUiServices().openUrl(Uri.parse('https://a.test/core'));
      expect(calls, isEmpty);
      final session = OpenUiSession(intelligentUi);
      addTearDown(session.dispose);
      await OpenUiView(
        session: session,
        builders: intelligentUiBuilders,
      ).fallbackServices.openUrl(Uri.parse('https://a.test/x'));
      final launch = calls.singleWhere((c) => c.method == 'launch');
      expect((launch.arguments as Map)['url'], 'https://a.test/x');
    });

    test('map tiles are off by default and Esri is opt-in', () {
      expect(const OpenUiServices().mapTiles, isNull);
      expect(
        OpenUiServices(mapTiles: esriStreetTiles).mapTiles,
        same(esriStreetTiles),
      );
      expect(esriStreetTiles.light, contains('World_Street_Map'));
      expect(esriStreetTiles.dark, contains('World_Dark_Gray_Base'));
      expect(esriStreetTiles.attribution, contains('Esri'));
    });

    testWidgets('a scope provides services, and none gives the defaults', (
      tester,
    ) async {
      OpenUiServices? seen;
      var builds = 0;
      final probe = Builder(
        builder: (context) {
          builds++;
          seen = OpenUiScope.servicesOf(context);
          return const SizedBox();
        },
      );
      Widget app(OpenUiServices? services) => services == null
          ? probe
          : OpenUiScope(services: services, child: probe);

      await tester.pumpWidget(app(null));
      expect(seen!.mapTiles, isNull);
      expect(seen!.searchImages, isNull);

      final a = OpenUiServices(searchImages: (_) async => []);
      await tester.pumpWidget(app(a));
      expect(seen, same(a));
      final before = builds;
      await tester.pumpWidget(app(a));
      expect(builds, before, reason: 'same services do not notify dependents');
      final b = OpenUiServices(searchImages: (_) async => []);
      await tester.pumpWidget(app(b));
      expect(seen, same(b));
    });
  });

  group('webUri', () {
    test('only http(s) urls with a host', () {
      expect(webUri('https://a.test/x?y=1'), Uri.parse('https://a.test/x?y=1'));
      expect(webUri('  http://a.test '), Uri.parse('http://a.test'));
      expect(webUri('javascript:alert(1)'), isNull);
      expect(webUri('ftp://a.test'), isNull);
      expect(webUri('file:///etc/passwd'), isNull);
      expect(webUri('https://'), isNull);
      expect(webUri('/relative'), isNull);
      expect(webUri('http://[bad'), isNull);
      expect(webUri(5), isNull);
      expect(webUri(null), isNull);
    });
  });

  group('OpenUiView event routing', () {
    testWidgets('@OpenUrl on http(s) goes to services.openUrl only', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Go", @OpenUrl("https://example.com/a"))])',
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(p.opened, [Uri.parse('https://example.com/a')]);
      expect(p.events, isEmpty);
    });

    testWidgets('@OpenUrl on other schemes opens nothing', (tester) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("A", @OpenUrl("javascript:alert(1)")), Button("B", @OpenUrl("ftp://x.test/f"))])',
      );
      await tester.tap(find.text('A'));
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(p.opened, isEmpty);
      expect(p.events, isEmpty);
    });

    testWidgets('@CopyToClipboard copies and also reports to onAction', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Copy", @CopyToClipboard("hello"))])',
      );
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(p.copied, ['hello']);
      expect(p.events.single.type, 'CopyToClipboard');
      expect(p.events.single.params['text'], 'hello');
    });

    testWidgets('@ToAssistant goes to onToAssistant', (tester) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Ask", @ToAssistant("Tell me more"))])',
      );
      await tester.tap(find.text('Ask'));
      await tester.pump();
      expect(p.events.single.type, ActionEvent.continueConversation);
      expect(p.events.single.humanFriendlyMessage, 'Tell me more');
      expect(p.copied, isEmpty);
      expect(p.opened, isEmpty);
    });

    testWidgets('a Button without an action sends its label', (tester) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Surprise me")])',
      );
      await tester.tap(find.text('Surprise me'));
      await tester.pump();
      expect(p.events.single.type, ActionEvent.continueConversation);
      expect(p.events.single.humanFriendlyMessage, 'Surprise me');
    });

    testWidgets('an action object of another type goes to onAction', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Other", {type: "custom_thing", params: {a: 1}})])',
      );
      await tester.tap(find.text('Other'));
      await tester.pump();
      expect(p.events.single.type, 'custom_thing');
      expect(p.copied, isEmpty);
      expect(p.opened, isEmpty);
    });

    testWidgets('events are dropped quietly when no handler is given', (
      tester,
    ) async {
      final session = OpenUiSession(intelligentUi)
        ..update(
          'root = Col([Button("Ask"), Button("Copy", @CopyToClipboard("x"))])',
          streaming: false,
        );
      addTearDown(session.dispose);
      final copied = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiScope(
            services: OpenUiServices(copyText: (t) async => copied.add(t)),
            child: OpenUiView(
              session: session,
              builders: intelligentUiBuilders,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ask'));
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, ['x']);
      expect(tester.takeException(), isNull);
    });
  });

  group('OpenUiView state', () {
    testWidgets('an empty session renders nothing', (tester) async {
      final session = OpenUiSession(intelligentUi);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(session: session, builders: intelligentUiBuilders),
        ),
      );
      expect(find.byType(OpenUiElementView), findsNothing);
      session.update('root = Col([Text("late")])', streaming: false);
      await tester.pump();
      expect(find.text('late'), findsOneWidget);
    });

    testWidgets('a pending Query dims the content and shows a spinner', (
      tester,
    ) async {
      final done = Completer<Object?>();
      final p = await pumpProgram(
        tester,
        'root = Col([Text("n=" + q.n)])\nq = Query("slow", {}, {n: 0})',
        tools: [OpenUiTool(name: 'slow', call: (_) => done.future)],
      );
      await tester.pump();
      expect(p.session.isQueryLoading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0.7,
      );
      done.complete({'n': 9});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('n=9'), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    });

    testWidgets('a queryLoader replaces the default spinner', (tester) async {
      final done = Completer<Object?>();
      final session =
          OpenUiSession(
            intelligentUi,
            tools: [OpenUiTool(name: 'slow', call: (_) => done.future)],
          )..update(
            'root = Col([Text("n=" + q.n)])\nq = Query("slow", {}, {n: 0})',
            streaming: false,
          );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(
            session: session,
            builders: intelligentUiBuilders,
            queryLoader: const Text('fetching'),
          ),
        ),
      );
      expect(find.text('fetching'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      done.complete({'n': 1});
      await tester.pump();
      await tester.pump();
      expect(find.text('fetching'), findsNothing);
      expect(find.text('n=1'), findsOneWidget);
    });

    testWidgets('slots show a Query failure, retry it, and report retrying', (
      tester,
    ) async {
      final answers = <Completer<Object?>>[];
      final session =
          OpenUiSession(
            intelligentUi,
            tools: [
              OpenUiTool(
                name: 't',
                call: (_) {
                  final answer = Completer<Object?>();
                  answers.add(answer);
                  return answer.future;
                },
              ),
            ],
          )..update(
            'root = Col([Text("n=" + q.n)])\nq = Query("t", {}, {n: 0})',
            streaming: false,
          );
      addTearDown(session.dispose);
      late OpenUiQueryState query;
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(
            session: session,
            builders: intelligentUiBuilders,
            child: Builder(
              builder: (context) {
                query = OpenUiView.queryOf(context);
                return const Column(
                  children: [
                    OpenUiQueryError(child: Text('failed')),
                    OpenUiRetry(child: Text('Retry')),
                    OpenUiQueryLoading(child: Text('loading')),
                    OpenUiContent(),
                  ],
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);
      expect(find.text('n=0'), findsOneWidget);

      answers[0].completeError(Exception('down'));
      await tester.pump();
      await tester.pump();
      expect(find.text('failed'), findsOneWidget);
      expect(find.text('loading'), findsNothing);
      expect(find.text('n=0'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(answers, hasLength(2));
      expect(query.isRetrying, isTrue);
      expect(find.text('loading'), findsNothing);

      answers[1].complete({'n': 7});
      await tester.pump();
      await tester.pump();
      expect(find.text('failed'), findsNothing);
      expect(find.text('n=7'), findsOneWidget);
      expect(query.isRetrying, isFalse);
    });

    testWidgets('swapping the session listens to the new one only', (
      tester,
    ) async {
      final a = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("from a")])', streaming: false);
      final b = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("from b")])', streaming: false);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      Widget app(OpenUiSession s) => MaterialApp(
        home: OpenUiView(session: s, builders: intelligentUiBuilders),
      );
      await tester.pumpWidget(app(a));
      expect(find.text('from a'), findsOneWidget);
      await tester.pumpWidget(app(b));
      expect(find.text('from b'), findsOneWidget);
      a.update('root = Col([Text("a changed")])', streaming: false);
      await tester.pump();
      expect(find.text('a changed'), findsNothing);
      expect(find.text('from b'), findsOneWidget);
      b.update('root = Col([Text("b changed")])', streaming: false);
      await tester.pump();
      expect(find.text('b changed'), findsOneWidget);
    });

    testWidgets('a type without a builder renders nothing', (tester) async {
      final session = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("x")])', streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(session: session, builders: (_) => null),
        ),
      );
      expect(find.text('x'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OpenUiElementView without an OpenUiView says so', (
      tester,
    ) async {
      final session = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("x")])', streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(home: OpenUiElementView(element: session.root!)),
      );
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('needs an OpenUiView'));
    });
  });

  group('OpenUiElementView', () {
    testWidgets(
      'keeps the last good widget when a builder throws on a rebuild',
      (tester) async {
        var explode = false;
        Widget col(BuildContext context, OpenUiNode node) {
          if (explode) throw StateError('half-written props');
          return Text(node.props.list('children').length.toString());
        }

        final session = OpenUiSession(intelligentUi)
          ..update('root = Col([Text("a")])', streaming: false);
        addTearDown(session.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: OpenUiView(
              session: session,
              builders: (name) => name == 'Col' ? col : null,
            ),
          ),
        );
        expect(find.text('1'), findsOneWidget);

        explode = true;
        session.update('root = Col([Text("a"), Text("b")])', streaming: false);
        await tester.pump();
        expect(
          find.text('1'),
          findsOneWidget,
          reason: 'last good widget stays',
        );
        expect(tester.takeException(), isA<StateError>());

        explode = false;
        session.update('root = Col([Text("a"), Text("b")])', streaming: false);
        await tester.pump();
        session.update(
          'root = Col([Text("a"), Text("b"), Text("c")])',
          streaming: false,
        );
        await tester.pump();
        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets('a builder that throws on its first build renders nothing', (
      tester,
    ) async {
      final session = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("a")])', streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(
            session: session,
            builders: (_) =>
                (_, _) => throw StateError('never good'),
          ),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(OpenUiElementView), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a builder that throws reports a render-error to onError', (
      tester,
    ) async {
      final reports = <List<Map<String, Object?>>>[];
      final session = OpenUiSession(
        intelligentUi,
        onError: (errors) => reports.add([for (final e in errors) e.toJson()]),
      )..update('root = Col([Text("a")])', streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(
            session: session,
            builders: (_) =>
                (_, _) => throw StateError('never good'),
          ),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      await tester.pump();
      expect(reports.last, [
        {
          'source': 'runtime',
          'code': 'render-error',
          'component': 'Col',
          'message': 'Component Col render failed: never good',
        },
      ]);
    });
  });

  group('OpenUiNode', () {
    testWidgets('render flattens elements, text, numbers and lists', (
      tester,
    ) async {
      late List<Widget> rendered;
      late List<Widget> kids;
      late bool streaming;
      late bool hasAction;
      late String? form;
      Widget probe(BuildContext context, OpenUiNode node) {
        rendered = node.render([
          'one',
          2,
          true,
          null,
          {'ignored': 1},
          ['nested', 3.5],
        ]);
        kids = node.children('children');
        streaming = node.isStreaming;
        hasAction = node.hasAction('missing');
        form = node.formName;
        node.run('missing');
        return Column(children: [...rendered, ...kids]);
      }

      final session = OpenUiSession(intelligentUi)
        ..update('root = Col([Text("child")])', streaming: true);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OpenUiView(
            session: session,
            builders: (name) =>
                name == 'Col' ? probe : intelligentUiBuilders(name),
          ),
        ),
      );
      expect(rendered, hasLength(5));
      expect(find.text('one'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('true'), findsOneWidget);
      expect(find.text('nested'), findsOneWidget);
      expect(find.text('3.5'), findsOneWidget);
      expect(kids, hasLength(1));
      expect(find.text('child'), findsOneWidget);
      expect(streaming, isTrue);
      expect(hasAction, isFalse);
      expect(form, isNull);
    });

    testWidgets(
      'a node reads Query loading and another form, and sets a default after the frame',
      (tester) async {
        late bool loading;
        late Object? city;
        Widget probe(BuildContext context, OpenUiNode node) {
          loading = node.isQueryLoading;
          city = node.fieldValue('City', formName: 'billing');
          node.setDefaultValue('Zip', '4000');
          return const SizedBox.shrink();
        }

        final session =
            OpenUiSession(
              intelligentUi,
              tools: [
                OpenUiTool(
                  name: 'slow',
                  call: (_) => Completer<Object?>().future,
                ),
              ],
              initialState: {
                'billing': {
                  'City': {'value': 'Porto'},
                },
              },
            )..update(
              'root = Col([Text("x")])\nq = Query("slow", {}, 0)',
              streaming: false,
            );
        addTearDown(session.dispose);
        expect(session.state.containsKey('Zip'), isFalse);
        await tester.pumpWidget(
          MaterialApp(
            home: OpenUiView(
              session: session,
              builders: (name) => name == 'Col' ? probe : null,
            ),
          ),
        );
        expect(loading, isTrue);
        expect(city, 'Porto');
        expect(session.state['Zip'], {'value': '4000'});
      },
    );
  });
}
