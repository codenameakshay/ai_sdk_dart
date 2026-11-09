// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_web/src/html_document.dart';

void main() {
  group('WikimediaImageSearch requests', () {
    test(
      'MediaWiki API calls ask for anonymous CORS, REST calls do not',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 404);
        });
        await WikimediaImageSearch(client: client)('Lisbon Tower');

        final api = requests.where((r) => r.url.path == '/w/api.php').toList();
        final rest = requests
            .where((r) => r.url.path.contains('/rest_v1/'))
            .toList();
        expect(api, isNotEmpty);
        expect(rest, isNotEmpty);
        for (final r in api) {
          expect(r.url.queryParameters['origin'], '*');
        }
        for (final r in rest) {
          expect(r.url.queryParameters.containsKey('origin'), isFalse);
        }
      },
    );
  });

  group('HtmlView documents', () {
    const model = '<p id=game>hi</p>';

    test(
      'the channel page denies storage after the policy and before the model',
      () {
        final doc = htmlViewDocument(
          model,
          dark: false,
          report: HeightReport.channel,
        );
        final csp = doc.indexOf('Content-Security-Policy');
        final deny = doc.indexOf('deny(window,"localStorage")');
        expect(deny, greaterThan(csp));
        expect(deny, lessThan(doc.indexOf(model)));
        expect(doc, contains('deny(window,"sessionStorage")'));
        expect(doc, contains('stub(window,"indexedDB",'));
      },
    );

    test('the parent page does not deny storage', () {
      final doc = htmlViewDocument(
        model,
        dark: false,
        report: HeightReport.parent,
      );
      expect(doc, isNot(contains('self.origin')));
      expect(doc, contains(model));
    });
  });

  group('OpenUiServices', () {
    test('keeps the embed referrer it is given', () {
      expect(
        const OpenUiServices(embedReferrer: 'https://a.b').embedReferrer,
        'https://a.b',
      );
    });

    test('has no embed referrer by default', () {
      expect(const OpenUiServices().embedReferrer, isNull);
    });
  });
}
