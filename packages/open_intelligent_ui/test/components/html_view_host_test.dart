// webview_flutter_platform_interface is what webview_flutter builds on; a fake
// platform from it is how a test supplies a web view.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../support/pump.dart';

class _FakePlatform extends WebViewPlatform {
  final List<_FakeController> controllers = [];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final c = _FakeController(params);
    controllers.add(c);
    return c;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWidget(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeDelegate(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  final Map<String, void Function(JavaScriptMessage)> channels = {};
  final List<String> html = [];
  final List<Uri> requests = [];
  JavaScriptMode? mode;
  _FakeDelegate? delegate;
  int cleared = 0;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async =>
      mode = javaScriptMode;

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams p) async =>
      channels[p.name] = p.onMessageReceived;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate d,
  ) async => delegate = d as _FakeDelegate;

  @override
  Future<void> loadHtmlString(String document, {String? baseUrl}) async =>
      html.add(document);

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      requests.add(params.uri);

  @override
  Future<void> clearLocalStorage() async => cleared++;

  @override
  Future<void> clearCache() async => cleared++;
}

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key('fake-web-view'));
}

class _FakeDelegate extends PlatformNavigationDelegate {
  _FakeDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onRequest;
  PageEventCallback? onFinished;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async =>
      onRequest = cb;

  @override
  Future<void> setOnPageFinished(PageEventCallback cb) async => onFinished = cb;

  Future<NavigationDecision> ask(String url) async =>
      await onRequest!(NavigationRequest(url: url, isMainFrame: true));
}

_FakePlatform _install() {
  final platform = _FakePlatform();
  WebViewPlatform.instance = platform;
  return platform;
}

// The platform cannot be unset; every test file runs in its own isolate, so
// this stays inside this file.
void main() {
  group('HtmlView with a web view', () {
    testWidgets(
      'loads the model page inside the security policy with JavaScript on',
      (tester) async {
        final platform = _install();
        await pumpProgram(
          tester,
          'root = Col([HtmlView("<p id=game>hi</p>", null, "Game")])',
        );
        final c = platform.controllers.single;
        expect(find.byKey(const Key('fake-web-view')), findsOneWidget);
        expect(c.mode, JavaScriptMode.unrestricted);
        expect(c.html, hasLength(1));
        final doc = c.html.single;
        expect(doc, contains('Content-Security-Policy'));
        expect(
          doc.indexOf('Content-Security-Policy'),
          lessThan(doc.indexOf('<p id=game>hi</p>')),
        );
        expect(doc, contains('color-scheme:light'));
        expect(doc, contains('IuiHeight.postMessage'));
        expect(c.channels.keys, ['IuiHeight']);
      },
    );

    testWidgets('uses the dark color scheme in dark mode', (tester) async {
      final platform = _install();
      await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>hi</p>")])',
        brightness: Brightness.dark,
      );
      expect(
        platform.controllers.single.html.single,
        contains('color-scheme:dark'),
      );
    });

    testWidgets('the page height follows what the page reports, clamped', (
      tester,
    ) async {
      final platform = _install();
      await pumpProgram(tester, 'root = Col([HtmlView("<p>hi</p>")])');
      final report = platform.controllers.single.channels['IuiHeight']!;
      expect(
        tester.getSize(find.byKey(const Key('fake-web-view'))).height,
        closeTo(360, 2),
      );
      report(const JavaScriptMessage(message: '500'));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('fake-web-view'))).height,
        closeTo(500, 2),
      );
      report(const JavaScriptMessage(message: '99999'));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('fake-web-view'))).height,
        closeTo(2400, 2),
      );
      report(const JavaScriptMessage(message: 'oops'));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('fake-web-view'))).height,
        closeTo(2400, 2),
        reason: 'junk is ignored',
      );
    });

    testWidgets('a fixed height ignores what the page reports', (tester) async {
      final platform = _install();
      await pumpProgram(tester, 'root = Col([HtmlView("<p>hi</p>", 300)])');
      platform.controllers.single.channels['IuiHeight']!(
        const JavaScriptMessage(message: '700'),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('fake-web-view'))).height,
        closeTo(300, 2),
      );
    });

    testWidgets('after the first load every navigation is blocked', (
      tester,
    ) async {
      final platform = _install();
      await pumpProgram(tester, 'root = Col([HtmlView("<p>hi</p>")])');
      final d = platform.controllers.single.delegate!;
      expect(await d.ask('about:blank'), NavigationDecision.navigate);
      d.onFinished!('about:blank');
      expect(await d.ask('https://evil.test/'), NavigationDecision.prevent);
    });

    testWidgets('blocks external navigation before the page finishes loading', (
      tester,
    ) async {
      final platform = _install();
      await pumpProgram(tester, 'root = Col([HtmlView("<p>hi</p>")])');
      final delegate = platform.controllers.single.delegate!;
      expect(
        await delegate.ask('https://evil.test/'),
        NavigationDecision.prevent,
      );
      expect(
        await delegate.ask('javascript:alert(1)'),
        NavigationDecision.prevent,
      );
      expect(await delegate.ask('about:blank'), NavigationDecision.navigate);
      delegate.onFinished!('about:blank');
      expect(await delegate.ask('about:blank'), NavigationDecision.prevent);
    });

    testWidgets('ignores height messages after the view is removed', (
      tester,
    ) async {
      final platform = _install();
      final p = await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>hi</p>")])',
      );
      final report = platform.controllers.single.channels['IuiHeight']!;
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      expect(
        () => report(const JavaScriptMessage(message: '500')),
        returnsNormally,
      );
      expect(find.text('gone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('new html reloads the page and allows its first load again', (
      tester,
    ) async {
      final platform = _install();
      final p = await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>one</p>")])',
      );
      final c = platform.controllers.single;
      c.delegate!.onFinished!('about:blank');
      p.session.update(
        'root = Col([HtmlView("<p>two</p>")])',
        streaming: false,
      );
      await tester.pump();
      expect(c.html, hasLength(2));
      expect(c.html.last, contains('<p>two</p>'));
      expect(await c.delegate!.ask('about:blank'), NavigationDecision.navigate);
      p.session.update(
        'root = Col([HtmlView("<p>two</p>")])',
        streaming: false,
      );
      await tester.pump();
      expect(c.html, hasLength(2), reason: 'same page is not reloaded');
    });

    testWidgets('removing the view leaves the app web storage alone', (
      tester,
    ) async {
      final platform = _install();
      final p = await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>hi</p>")])',
      );
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      expect(platform.controllers.single.cleared, 0);
    });

    testWidgets('while streaming the page is not loaded at all', (
      tester,
    ) async {
      final platform = _install();
      await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>hi</p>")])',
        streaming: true,
      );
      expect(platform.controllers, isEmpty);
      expect(find.text('Preparing the interactive view…'), findsOneWidget);
    });
  });

  group('YouTube with a web view', () {
    const id = 'dQw4w9WgXcQ';

    testWidgets(
      'embeds the privacy-friendly player and not the thumbnail card',
      (tester) async {
        final platform = _install();
        final p = await pumpProgram(
          tester,
          'root = Col([YouTube("$id", "Clip")])',
        );
        final c = platform.controllers.single;
        expect(c.requests, [
          Uri.parse('https://www.youtube-nocookie.com/embed/$id'),
        ]);
        expect(c.mode, JavaScriptMode.unrestricted);
        expect(find.byKey(const Key('fake-web-view')), findsOneWidget);
        expect(
          find.byWidgetPredicate((w) => w is Glyph && w.name == 'play'),
          findsNothing,
        );
        expect(
          tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
          closeTo(16 / 9, 1e-9),
        );
        expect(p.opened, isEmpty);
      },
    );

    testWidgets('updates the embedded video when its id changes', (
      tester,
    ) async {
      final platform = _install();
      final p = await pumpProgram(tester, 'root = Col([YouTube("$id")])');
      final controller = platform.controllers.single;
      p.session.update(
        'root = Col([YouTube("a-b_c-d_e-f")])',
        streaming: false,
      );
      await tester.pump();
      expect(platform.controllers, hasLength(1));
      expect(controller.requests, [
        Uri.parse('https://www.youtube-nocookie.com/embed/$id'),
        Uri.parse('https://www.youtube-nocookie.com/embed/a-b_c-d_e-f'),
      ]);
      p.session.update(
        'root = Col([YouTube("a-b_c-d_e-f", "New title")])',
        streaming: false,
      );
      await tester.pump();
      expect(controller.requests, hasLength(2));
    });

    testWidgets('may navigate only inside YouTube over https', (tester) async {
      final platform = _install();
      await pumpProgram(tester, 'root = Col([YouTube("$id")])');
      final d = platform.controllers.single.delegate!;
      expect(
        await d.ask('https://www.youtube.com/embed/$id'),
        NavigationDecision.navigate,
      );
      expect(
        await d.ask('https://i.ytimg.com/vi/$id/hq.jpg'),
        NavigationDecision.navigate,
      );
      expect(
        await d.ask('http://www.youtube.com/embed/$id'),
        NavigationDecision.prevent,
      );
      expect(await d.ask('https://evil.test/'), NavigationDecision.prevent);
      expect(
        await d.ask('https://youtube.com.evil.test/'),
        NavigationDecision.prevent,
      );
      expect(await d.ask('not a url at all'), NavigationDecision.prevent);
    });
  });
}
