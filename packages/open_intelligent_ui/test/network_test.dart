import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  test('services default to no tiles and no images', () {
    const services = OpenUiServices();
    expect(services.mapTiles, isNull);
    expect(services.imageLoader, isNull);
  });

  testWidgets('a blocked image shows the placeholder and makes no request', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Image("https://a.test/x.png", "x")])',
      services: const OpenUiServices(),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.bySemanticsLabel('x'), findsWidgets);
  });

  test('allowImageHosts allows a host and its subdomains only', () {
    final loader = allowImageHosts(['wikimedia.org']);
    expect(loader(Uri.parse('https://upload.wikimedia.org/a')), isNotNull);
    expect(loader(Uri.parse('https://wikimedia.org/a')), isNotNull);
    expect(loader(Uri.parse('https://evil.test/a')), isNull);
    expect(loader(Uri.parse('https://notwikimedia.org')), isNull);
    expect(loader(Uri.parse('ftp://upload.wikimedia.org/a')), isNull);
    expect(
      allowImageHosts(['Wikimedia.ORG'])(
        Uri.parse('https://upload.wikimedia.org/a'),
      ),
      isNotNull,
    );
  });

  testWidgets('a denied src falls back to search, through the loader', (
    tester,
  ) async {
    final loader = allowImageHosts(['ok.test']);
    await pumpProgram(
      tester,
      'root = Col([Image("https://bad.test/a.png", "Belem Tower")])',
      services: OpenUiServices(
        searchImages: (_) async => [Uri.parse('https://ok.test/b.png')],
        imageLoader: loader,
      ),
    );
    final denied = NetworkImage('https://bad.test/a.png');
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image == denied),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 600));
    final image = tester.widget<Image>(find.byType(Image));
    final expected = loader(Uri.parse('https://ok.test/b.png'))!;
    expect(image.image, expected);
    expect(image.image, isNot(isA<NetworkImage>()));
  });

  testWidgets('the map draws no tiles by default', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Map([MapMarker("A place", 10, 20), MapMarker("B place", 11, 21)])])',
      services: const OpenUiServices(),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(fm.TileLayer), findsNothing);
  });
}
