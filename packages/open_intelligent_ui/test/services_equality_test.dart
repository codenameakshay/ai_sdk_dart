import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

Future<void> _openUrl(Uri url) async {}

Future<List<Uri>> _searchImages(String query) async => const [];

OpenUiServices _services({String referrer = 'https://app.example'}) =>
    OpenUiServices(
      openUrl: _openUrl,
      searchImages: _searchImages,
      imageLoader: networkImages,
      embedReferrer: referrer,
      mapTiles: const MapTiles(light: 'l', dark: 'd', attribution: 'a').copy(),
    );

extension on MapTiles {
  MapTiles copy() =>
      MapTiles(light: light, dark: dark, attribution: attribution);
}

void main() {
  test('services with the same members are equal', () {
    expect(_services(), _services());
    expect(_services().hashCode, _services().hashCode);
    expect(_services(), isNot(_services(referrer: 'https://other.example')));
    expect(_services(), isNot(const OpenUiServices()));
    expect(
      const OpenUiServices(copyText: _copy),
      isNot(const OpenUiServices()),
    );
    expect(
      const OpenUiServices(fontFamily: 'Host'),
      isNot(const OpenUiServices(fontFamily: 'Other')),
    );
    expect(
      const MapTiles(light: 'l', dark: 'd', attribution: 'a').copy(),
      isNot(const MapTiles(light: 'l', dark: 'd', attribution: 'b')),
    );
  });

  testWidgets('rebuilding the scope with equal services does not rebuild '
      'dependents', (tester) async {
    var builds = 0;
    late StateSetter rebuild;
    final dependent = Builder(
      builder: (context) {
        OpenUiScope.servicesOf(context);
        builds++;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return OpenUiScope(services: _services(), child: dependent);
        },
      ),
    );
    expect(builds, 1);

    rebuild(() {});
    await tester.pump();
    expect(builds, 1);
  });
}

Future<void> _copy(String text) async {}
