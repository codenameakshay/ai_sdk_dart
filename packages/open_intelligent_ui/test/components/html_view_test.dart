import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/html_document.dart';
import 'package:open_intelligent_ui/src/components/html_view.dart'
    show HtmlPage;
import 'package:open_intelligent_ui/src/components/media.dart' show Photo;

import '../gallery_fixture.dart';
import '../support/pump.dart';

Finder get _page => find.byType(HtmlPage);

void main() {
  group('htmlViewDocument', () {
    test('puts the CSP meta before the model markup so it covers all of it', () {
      const markup =
          '<script>alert(1)</script><meta http-equiv="Content-Security-Policy" content="default-src *">';
      final doc = htmlViewDocument(
        markup,
        dark: false,
        report: HeightReport.channel,
      );
      final csp = doc.indexOf(
        '<meta http-equiv="Content-Security-Policy" content="$htmlViewCsp">',
      );
      expect(csp, greaterThan(0));
      expect(csp, lessThan(doc.indexOf('<script>alert(1)</script>')));
      expect(doc, startsWith('<!doctype html><meta charset="utf-8">'));
      expect(
        doc,
        endsWith(markup),
        reason: 'the model markup is last and untouched',
      );
    });

    test(
      'the policy blocks everything but inline code, a few script CDNs and https images',
      () {
        expect(htmlViewCsp, contains("default-src 'none'"));
        expect(
          htmlViewCsp,
          contains(
            "script-src 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com https://esm.sh",
          ),
        );
        expect(htmlViewCsp, contains("frame-src 'none'"));
        expect(htmlViewCsp, contains("form-action 'none'"));
        expect(htmlViewCsp, contains("base-uri 'none'"));
        expect(htmlViewCsp, contains('img-src data: blob: https:'));
        expect(htmlViewCsp, contains('connect-src https://cdn.jsdelivr.net'));
        expect(htmlViewCsp, isNot(contains('connect-src *')));
      },
    );

    test('picks the color scheme', () {
      expect(
        htmlViewDocument('', dark: true, report: HeightReport.channel),
        contains(':root{color-scheme:dark}'),
      );
      expect(
        htmlViewDocument('', dark: false, report: HeightReport.channel),
        contains(':root{color-scheme:light}'),
      );
    });

    test('picks how the page reports its height', () {
      final channel = htmlViewDocument(
        '',
        dark: false,
        report: HeightReport.channel,
      );
      expect(channel, contains('IuiHeight.postMessage(String(h))'));
      expect(channel, isNot(contains('parent.postMessage')));
      final parent = htmlViewDocument(
        '',
        dark: false,
        report: HeightReport.parent,
      );
      expect(
        parent,
        contains(
          'parent.postMessage({type:"iui-html-view-height",height:h},"*")',
        ),
      );
      expect(parent, isNot(contains('IuiHeight')));
      expect(parent, contains('ResizeObserver'));
    });

    test('the web page is the reference document byte for byte', () {
      expect(
        htmlViewDocument('<p>x</p>', dark: false, report: HeightReport.parent),
        '<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com https://esm.sh; style-src \'unsafe-inline\' https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com https://esm.sh https://fonts.googleapis.com; font-src https://fonts.gstatic.com data:; img-src data: blob: https:; media-src data: blob:; connect-src https://cdn.jsdelivr.net https://unpkg.com https://cdnjs.cloudflare.com https://esm.sh; frame-src \'none\'; form-action \'none\'; base-uri \'none\'"><meta name="viewport" content="width=device-width,initial-scale=1"><style>:root{color-scheme:light}html,body{margin:0}body{font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}</style><script>(function(){var last=0;function send(){var h=Math.ceil(document.documentElement.getBoundingClientRect().height);if(Math.abs(h-last)>1){last=h;parent.postMessage({type:"iui-html-view-height",height:h},"*")}}addEventListener("message",function(e){if(e.source===parent&&e.data==="iui-html-view-measure"){last=0;send()}});addEventListener("load",send);new ResizeObserver(send).observe(document.documentElement);send()})()</script><p>x</p>',
      );
    });

    test(
      'a native page runs only with an opaque origin, before the reporter and the model',
      () {
        final doc = htmlViewDocument(
          '<p id=m>',
          dark: false,
          report: HeightReport.channel,
        );
        final guard = doc.indexOf(
          'if(self.origin!=="null"){document.write("<plaintext hidden>");return}',
        );
        expect(guard, greaterThan(doc.indexOf('Content-Security-Policy')));
        expect(guard, lessThan(doc.indexOf('IuiHeight.postMessage')));
        expect(
          doc.indexOf('IuiHeight.postMessage'),
          lessThan(doc.indexOf('<p id=m>')),
        );
      },
    );

    test(
      'a native page sees storage, cookies and dialogs as a sandboxed frame does',
      () {
        final doc = htmlViewDocument(
          '',
          dark: false,
          report: HeightReport.channel,
        );
        for (final part in [
          'deny(window,"localStorage")',
          'deny(window,"sessionStorage")',
          'deny(Document.prototype,"cookie")',
          'deny(Navigator.prototype,"serviceWorker")',
          'stub(window,"indexedDB",',
          'stub(window,"caches",',
          'stub(Navigator.prototype,"storage",',
          'put(window,"BroadcastChannel",class BroadcastChannel extends EventTarget',
          'put(window,"open",function(){return null})',
          'put(window,"alert",function(){})',
          'put(window,"confirm",function(){return false})',
          'put(window,"prompt",function(){return null})',
          "The document is sandboxed and lacks the 'allow-same-origin' flag.",
          'd.configurable=false',
        ]) {
          expect(doc, contains(part), reason: part);
        }
      },
    );
  });

  group('clampHeight', () {
    test('keeps 80..2400 and reads numeric text', () {
      expect(clampHeight(300), 300);
      expect(clampHeight(300.5), 300.5);
      expect(clampHeight(10), 80);
      expect(clampHeight(-5), 80);
      expect(clampHeight(5000), 2400);
      expect(clampHeight('450'), 450);
      expect(clampHeight(' 450 '), 450);
      expect(clampHeight('20'), 80);
    });

    test('is null for anything that is not a finite number', () {
      expect(clampHeight(null), isNull);
      expect(clampHeight('abc'), isNull);
      expect(clampHeight(''), isNull);
      expect(clampHeight(double.nan), isNull);
      expect(clampHeight(double.infinity), isNull);
      expect(clampHeight('Infinity'), isNull);
      expect(clampHeight(Object()), isNull);
    });
  });

  group('youTubeId', () {
    const id = 'dQw4w9WgXcQ';

    test('reads a bare id and every URL shape', () {
      expect(youTubeId(id), id);
      expect(youTubeId('  $id  '), id);
      expect(youTubeId('https://www.youtube.com/watch?v=$id'), id);
      expect(youTubeId('https://www.youtube.com/watch?v=$id&t=42s'), id);
      expect(
        youTubeId('https://www.youtube.com/watch?feature=share&v=$id'),
        id,
      );
      expect(youTubeId('https://youtu.be/$id'), id);
      expect(youTubeId('https://youtu.be/$id?si=abc'), id);
      expect(youTubeId('https://www.youtube.com/embed/$id'), id);
      expect(youTubeId('https://www.youtube-nocookie.com/embed/$id'), id);
      expect(youTubeId('https://www.youtube.com/shorts/$id'), id);
      expect(
        youTubeId('https://m.youtube.com/watch?v=a-b_c-d_e-f'),
        'a-b_c-d_e-f',
      );
    });

    test('is null when there is no id', () {
      expect(youTubeId(''), isNull);
      expect(youTubeId('short'), isNull);
      expect(youTubeId('this is not a video'), isNull);
      expect(youTubeId('dQw4w9WgXcQx'), isNull, reason: 'twelve characters');
      expect(youTubeId('https://www.youtube.com/'), isNull);
      expect(youTubeId('https://www.youtube.com/watch?v=short'), isNull);
      expect(youTubeId('https://example.com/page'), isNull);
    });
  });

  group('isYouTubeHost', () {
    test('allows YouTube hosts and their subdomains', () {
      for (final host in [
        'youtube.com',
        'www.youtube.com',
        'm.youtube.com',
        'www.youtube-nocookie.com',
        'i.ytimg.com',
        'ytimg.com',
        'rr1---sn-abc.googlevideo.com',
        'yt3.ggpht.com',
        'www.gstatic.com',
        'accounts.google.com',
        'google.com',
      ]) {
        expect(isYouTubeHost(host), isTrue, reason: host);
      }
    });

    test('rejects look-alikes and others', () {
      for (final host in [
        'evilyoutube.com',
        'youtube.com.evil.test',
        'notgoogle.com',
        'example.com',
        '',
        'youtu.be',
      ]) {
        expect(isYouTubeHost(host), isFalse, reason: host);
      }
    });
  });

  group('HtmlView', () {
    testWidgets(
      'shows a waiting note while the program streams, not the page',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([HtmlView("<p>game</p>", null, "Catch the dot")])',
          streaming: true,
        );
        expect(find.text('Preparing the interactive view…'), findsOneWidget);
        expect(find.text('Catch the dot'), findsNothing);
      },
    );

    testWidgets(
      'shows the unsupported card with its title where no web view runs',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([HtmlView("<p>game</p>", null, "Catch the dot")])',
        );
        expect(find.text('Catch the dot'), findsOneWidget);
        expect(
          find.text(
            'This interactive view runs on Android, iOS, macOS and the web.',
          ),
          findsOneWidget,
        );
        expect(find.text('Preparing the interactive view…'), findsNothing);
        expect(
          find.descendant(
            of: _page,
            matching: find.byWidgetPredicate(
              (w) => w is Glyph && w.name == 'app-window',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a missing or empty title says Interactive view', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>a</p>"), HtmlView("<p>b</p>", null, "")])',
      );
      expect(find.text('Interactive view'), findsNWidgets(2));
    });

    testWidgets('starts 360 high, and a fixed height is clamped to 80..2400', (
      tester,
    ) async {
      Future<double> heightOf(String args) async {
        await pumpProgram(tester, 'root = Col([HtmlView($args)])');
        return tester.getSize(_page).height;
      }

      expect(await heightOf('"<p>a</p>"'), 360);
      expect(await heightOf('"<p>a</p>", 500'), 500);
      expect(await heightOf('"<p>a</p>", 99999'), 2400);
      expect(await heightOf('"<p>a</p>", 0'), 360);
      expect(await heightOf('"<p>a</p>", -3'), 360);
      expect(await heightOf('"<p>a</p>", null'), 360);
    });

    testWidgets('a fixed height under 80 is raised to 80', (tester) async {
      await pumpProgram(tester, 'root = Col([HtmlView("<p>a</p>", 10)])');
      expect(tester.getSize(_page).height, 80);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a small fixed height lays out without overflow', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([HtmlView("<p>a</p>", 10)])');
      expect(tester.getSize(_page).height, 80);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the frame is labelled with the title', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>a</p>", null, "Catch the dot")])',
      );
      expect(find.bySemanticsLabel(RegExp('Catch the dot')), findsWidgets);
      handle.dispose();
    });

    testWidgets('uses the dark tokens in dark mode', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([HtmlView("<p>a</p>")])',
        brightness: Brightness.dark,
      );
      final box = tester.widget<Container>(
        find.descendant(of: _page, matching: find.byType(Container)).first,
      );
      expect((box.decoration! as BoxDecoration).color, OpenUiTheme.dark.canvas);
    });

    testWidgets('the gallery html program renders its card', (tester) async {
      final p = await pumpProgram(tester, galleryProgram('html'));
      expect(p.session.issues, isEmpty);
      expect(find.text('Take a little break'), findsOneWidget);
      expect(find.text('Catch the dot'), findsOneWidget);
    });
  });

  group('YouTube', () {
    const id = 'dQw4w9WgXcQ';

    testWidgets('shows a 16:9 thumbnail card with a play button', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([YouTube("$id", "Never gonna")])');
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio,
        closeTo(16 / 9, 1e-9),
      );
      expect(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'play'),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is Photo), findsOneWidget);
      final photo = tester.widget<Photo>(find.byType(Photo));
      expect(photo.src, 'https://i.ytimg.com/vi/$id/hqdefault.jpg');
    });

    testWidgets('tapping opens the watch URL through services.openUrl', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([YouTube("$id", "Never gonna")])',
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'play'),
      );
      await tester.pump();
      expect(p.opened, [Uri.parse('https://www.youtube.com/watch?v=$id')]);
    });

    testWidgets('a pasted URL works, and the card is named Play <title>', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final p = await pumpProgram(
        tester,
        'root = Col([YouTube("https://youtu.be/$id?si=x", "Never gonna"), YouTube("https://www.youtube.com/shorts/$id")])',
      );
      expect(find.bySemanticsLabel('Play Never gonna'), findsOneWidget);
      expect(find.bySemanticsLabel('Play YouTube video'), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'play').first,
      );
      await tester.pump();
      expect(p.opened.single.toString(), 'https://www.youtube.com/watch?v=$id');
      handle.dispose();
    });

    testWidgets('an invalid video renders nothing', (tester) async {
      await pumpProgram(tester, 'root = Col([Text("only"), YouTube("nope")])');
      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byType(Photo), findsNothing);
      expect(find.text('only'), findsOneWidget);
    });
  });
}
