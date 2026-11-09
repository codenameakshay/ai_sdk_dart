// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/components/media.dart' show Photo;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _oldUrl = 'https://photos.test/old.png';
const _newUrl = 'https://photos.test/new.png';
const _query = 'a city at night';

Widget _host(OpenUiServices services, {String? src}) => MaterialApp(
  home: OpenUiScope(
    services: services,
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: Photo(key: const ValueKey('photo'), query: _query, src: src),
        ),
      ),
    ),
  ),
);

OpenUiServices _services({
  Future<List<Uri>> Function(String query)? search,
  ImageProvider? Function(Uri url)? loader,
}) => OpenUiServices(searchImages: search, imageLoader: loader, mapTiles: null);

Future<void> _pumpSearchTimer(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets(
    'a replacement search service wins over its older pending response',
    (tester) async {
      final oldResponse = Completer<List<Uri>>();
      final newResponse = Completer<List<Uri>>();
      var oldCalls = 0;
      var newCalls = 0;
      final oldBytes = Uint8List.fromList(_png);
      // PNG readers ignore trailing bytes; keeping them distinct lets the
      // assertion distinguish the actual MemoryImage selected for each URI.
      final newBytes = Uint8List.fromList([..._png, 0]);
      MemoryImage oldLoader(Uri url) => MemoryImage(oldBytes);
      MemoryImage newLoader(Uri url) =>
          MemoryImage(url.toString() == _newUrl ? newBytes : oldBytes);

      await tester.pumpWidget(
        _host(
          _services(
            search: (query) {
              oldCalls++;
              return oldResponse.future;
            },
            loader: oldLoader,
          ),
        ),
      );
      await _pumpSearchTimer(tester);
      expect(oldCalls, 1);

      await tester.pumpWidget(
        _host(
          _services(
            search: (query) {
              newCalls++;
              return newResponse.future;
            },
            loader: newLoader,
          ),
        ),
      );
      await _pumpSearchTimer(tester);
      expect(newCalls, 1);

      newResponse.complete([Uri.parse(_newUrl)]);
      await tester.pump();
      await tester.pump();
      final newImage = tester.widget<Image>(find.byType(Image));
      expect(newImage.image, isA<MemoryImage>());
      expect((newImage.image as MemoryImage).bytes, newBytes);

      oldResponse.complete([Uri.parse(_oldUrl)]);
      await tester.pump();
      await tester.pump();
      final finalImage = tester.widget<Image>(find.byType(Image));
      expect((finalImage.image as MemoryImage).bytes, newBytes);
      expect(oldCalls, 1);
      expect(newCalls, 1);
    },
  );

  testWidgets('opting out cancels a pending search debounce', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        _services(
          search: (query) async {
            calls++;
            return [Uri.parse(_oldUrl)];
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, 0);

    await tester.pumpWidget(_host(_services()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 0);
  });

  testWidgets('changing image loaders retries a previously failed URL', (
    tester,
  ) async {
    final goodBytes = Uint8List.fromList(_png);
    await tester.pumpWidget(
      _host(
        _services(loader: (url) => MemoryImage(Uint8List.fromList([1, 2, 3]))),
        src: _oldUrl,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(
      _host(_services(loader: (url) => MemoryImage(goodBytes)), src: _oldUrl),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, goodBytes);
  });
}
