import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_intelligent_ui/src/wikimedia.dart';
import 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _page(
  String title,
  int index, {
  String? thumb,
  Map<String, Object?>? info,
}) => {
  'title': title,
  'index': index,
  'thumbnail': ?(thumb == null ? null : {'source': thumb}),
  'imageinfo': ?(info == null ? null : [info]),
};

Map<String, Object?> _pages(List<Map<String, Object?>> pages) => {
  'query': {'pages': pages},
};

/// A fake Wikipedia and Commons: each part can be overridden per test.
class _Wiki {
  _Wiki({
    this.summary = const {},
    this.media = const {},
    this.articles = const {},
    this.files = const {},
    this.summaryStatus = 200,
  });
  final Object? summary;
  final Object? media;
  final Object? articles;
  final Object? files;
  final int summaryStatus;
  final List<http.Request> requests = [];

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final u = request.url;
    if (u.path.contains('/page/summary/')) {
      return _json(summary, summaryStatus);
    }
    if (u.path.contains('/page/media-list/')) return _json(media);
    if (u.host == 'en.wikipedia.org') return _json(articles);
    if (u.host == 'commons.wikimedia.org') return _json(files);
    return http.Response('', 500);
  });

  Iterable<http.Request> to(String host) =>
      requests.where((r) => r.url.host == host);
}

Map<String, Object?> _mediaItem(String src, {String type = 'image'}) => {
  'type': type,
  'srcset': [
    {'src': src},
  ],
};

void main() {
  group('WikimediaImageSearch', () {
    test(
      'asks the article first, then both searches, with the documented params',
      () async {
        final wiki = _Wiki();
        final search = WikimediaImageSearch(client: wiki.client);
        await search('  Belem   Tower ');

        final summary = wiki.requests.singleWhere(
          (r) => r.url.path.contains('/page/summary/'),
        );
        expect(
          summary.url.toString(),
          'https://en.wikipedia.org/api/rest_v1/page/summary/Belem_Tower',
        );
        expect(
          wiki.requests.any(
            (r) =>
                r.url.toString() ==
                'https://en.wikipedia.org/api/rest_v1/page/media-list/Belem_Tower',
          ),
          isTrue,
        );

        final article = wiki
            .to('en.wikipedia.org')
            .singleWhere((r) => r.url.path == '/w/api.php')
            .url
            .queryParameters;
        expect(article, {
          'action': 'query',
          'format': 'json',
          'origin': '*',
          'formatversion': '2',
          'generator': 'search',
          'gsrsearch': 'Belem Tower',
          'gsrlimit': '6',
          'prop': 'pageimages',
          'piprop': 'thumbnail',
          'pithumbsize': '960',
        });

        final commons = wiki
            .to('commons.wikimedia.org')
            .map((r) => r.url.queryParameters)
            .toList();
        expect(commons.first, {
          'action': 'query',
          'format': 'json',
          'formatversion': '2',
          'origin': '*',
          'generator': 'search',
          'gsrsearch': 'Belem Tower filetype:bitmap',
          'gsrnamespace': '6',
          'gsrlimit': '6',
          'prop': 'imageinfo',
          'iiprop': 'url|mime',
          'iiurlwidth': '960',
        });
        for (final r in wiki.requests) {
          expect(r.headers['User-Agent'], contains('open_intelligent_ui'));
        }
      },
    );

    test(
      'puts the article lead image first, then the media-list photos',
      () async {
        final wiki = _Wiki(
          summary: {
            'thumbnail': {
              'source': 'https://upload.wikimedia.org/a/320px-Lead.jpg',
            },
          },
          media: {
            'items': [
              _mediaItem('//upload.wikimedia.org/b/Second.jpg'),
              _mediaItem('//upload.wikimedia.org/c/Third.jpg'),
              _mediaItem('//upload.wikimedia.org/d/Fourth.jpg'),
            ],
          },
          articles: _pages([
            _page(
              'Belem Tower',
              0,
              thumb: 'https://upload.wikimedia.org/e/Search.jpg',
            ),
          ]),
        );
        final urls = await WikimediaImageSearch(client: wiki.client)(
          'Belem Tower',
        );
        expect(urls.map((u) => u.toString()), [
          'https://upload.wikimedia.org/a/320px-Lead.jpg',
          'https://upload.wikimedia.org/b/Second.jpg',
          'https://upload.wikimedia.org/c/Third.jpg',
          'https://upload.wikimedia.org/e/Search.jpg',
        ]);
      },
    );

    test('skips svg, logo, map and flag media and non-images', () async {
      final wiki = _Wiki(
        media: {
          'items': [
            _mediaItem('//u.org/x/Diagram.svg'),
            _mediaItem('//u.org/x/Site_logo.png'),
            _mediaItem('//u.org/x/Locator_map.png'),
            _mediaItem('//u.org/x/Flag_of_X.png'),
            _mediaItem('//u.org/x/Video.webm', type: 'video'),
            {'type': 'image', 'srcset': []},
            'not a map',
            _mediaItem('//u.org/x/Good.jpg'),
          ],
        },
      );
      final urls = await WikimediaImageSearch(client: wiki.client)('Lisbon');
      expect(urls.map((u) => u.toString()), ['https://u.org/x/Good.jpg']);
    });

    test(
      'drops media that repeats the lead image under another size',
      () async {
        final wiki = _Wiki(
          summary: {
            'thumbnail': {'source': 'https://u.org/t/330px-Tower.jpg'},
          },
          media: {
            'items': [
              _mediaItem('//u.org/t/640px-Tower.jpg'),
              _mediaItem('//u.org/t/Other.jpg'),
            ],
          },
        );
        final urls = await WikimediaImageSearch(client: wiki.client)('Tower');
        expect(urls.map((u) => u.toString()), [
          'https://u.org/t/330px-Tower.jpg',
          'https://u.org/t/Other.jpg',
        ]);
      },
    );

    test('keeps https only', () async {
      final wiki = _Wiki(
        summary: {
          'thumbnail': {'source': 'http://u.org/insecure.jpg'},
        },
        articles: _pages([
          _page('Belem Tower', 0, thumb: 'http://u.org/also-insecure.jpg'),
          _page('Belem Tower', 1, thumb: 'https://u.org/secure.jpg'),
        ]),
      );
      final urls = await WikimediaImageSearch(client: wiki.client)(
        'Belem Tower',
      );
      expect(urls.map((u) => u.toString()), ['https://u.org/secure.jpg']);
    });

    test(
      'article search keeps pages whose title shares a word, in index order',
      () async {
        final wiki = _Wiki(
          articles: _pages([
            _page('Tower Bridge', 2, thumb: 'https://u.org/bridge.jpg'),
            _page('Unrelated', 0, thumb: 'https://u.org/unrelated.jpg'),
            _page('Belem Tower', 1, thumb: 'https://u.org/belem.jpg'),
            _page('Belem Tower', 3),
            {'title': 'Belem'},
          ]),
        );
        final urls = await WikimediaImageSearch(client: wiki.client)(
          'Belem Tower',
        );
        expect(urls.map((u) => u.toString()), [
          'https://u.org/belem.jpg',
          'https://u.org/bridge.jpg',
        ]);
      },
    );

    test(
      'commons results skip svg, logo, map, flag, non-images and http',
      () async {
        Map<String, Object?> file(
          String name,
          int i, {
          String mime = 'image/jpeg',
          String? thumb,
        }) => _page(
          name,
          i,
          info: {
            'mime': mime,
            'thumburl': thumb ?? 'https://c.org/$name',
            'url': 'https://c.org/full/$name',
          },
        );
        final wiki = _Wiki(
          files: _pages([
            file('a.svg', 0),
            file('company_logo.png', 1),
            file('road_map.png', 2),
            file('flag.png', 3),
            file('sound.ogg', 4, mime: 'audio/ogg'),
            file('plain.png', 5, thumb: 'http://c.org/plain.png'),
            _page('NoInfo', 6),
            _page('BadInfo', 7, info: {'mime': 5}),
            {
              'index': 8,
              'imageinfo': ['x'],
            },
            {'index': 9, 'imageinfo': []},
            _page(
              'FullUrl',
              10,
              info: {'mime': 'image/png', 'url': 'https://c.org/full.png'},
            ),
            file('good.jpg', 11),
          ]),
        );
        final urls = await WikimediaImageSearch(client: wiki.client)('Lisbon');
        expect(urls.map((u) => u.toString()), [
          'https://c.org/full.png',
          'https://c.org/good.jpg',
        ]);
      },
    );

    test(
      'tries shorter commons queries until three photos, then stops',
      () async {
        final wiki = _Wiki();
        await WikimediaImageSearch(client: wiki.client)(
          'alpha beta gamma delta',
        );
        final searches = wiki
            .to('commons.wikimedia.org')
            .map((r) => r.url.queryParameters['gsrsearch']);
        expect(searches, [
          'alpha beta gamma delta filetype:bitmap',
          'alpha beta gamma filetype:bitmap',
          'alpha beta filetype:bitmap',
        ]);

        final rich = _Wiki(
          files: _pages([
            for (var i = 0; i < 6; i++)
              _page(
                'f$i',
                i,
                info: {
                  'mime': 'image/jpeg',
                  'thumburl': 'https://c.org/f$i.jpg',
                },
              ),
          ]),
        );
        final urls = await WikimediaImageSearch(client: rich.client)(
          'alpha beta gamma delta',
        );
        expect(rich.to('commons.wikimedia.org'), hasLength(1));
        expect(urls, hasLength(4), reason: 'at most four photos');
      },
    );

    test('a second call for the same query makes no request', () async {
      final wiki = _Wiki(
        summary: {
          'thumbnail': {'source': 'https://u.org/lead.jpg'},
        },
      );
      final search = WikimediaImageSearch(client: wiki.client);
      final first = await search('Belem Tower');
      final count = wiki.requests.length;
      expect(count, greaterThan(0));
      final second = await search('  Belem    Tower ');
      expect(second, first);
      expect(wiki.requests, hasLength(count));
    });

    test(
      'without results nothing is cached, so the next call asks again',
      () async {
        final wiki = _Wiki();
        final search = WikimediaImageSearch(client: wiki.client);
        expect(await search('Nowhere'), isEmpty);
        final count = wiki.requests.length;
        expect(await search('Nowhere'), isEmpty);
        expect(wiki.requests.length, count * 2);
      },
    );

    test('the cache keeps the newest 200 queries', () async {
      final wiki = _Wiki(
        summary: {
          'thumbnail': {'source': 'https://u.org/lead.jpg'},
        },
      );
      final search = WikimediaImageSearch(client: wiki.client);
      await search('query 000');
      for (var i = 1; i <= 200; i++) {
        await search('query ${i.toString().padLeft(3, '0')}');
      }
      final before = wiki.requests.length;
      await search('query 200');
      expect(wiki.requests, hasLength(before), reason: 'newest is cached');
      await search('query 000');
      expect(
        wiki.requests.length,
        greaterThan(before),
        reason: 'oldest was evicted',
      );
    });

    test('a missing article (404) is just no article photos', () async {
      final wiki = _Wiki(
        summaryStatus: 404,
        articles: _pages([
          _page('Belem Tower', 0, thumb: 'https://u.org/search.jpg'),
        ]),
      );
      final urls = await WikimediaImageSearch(client: wiki.client)(
        'Belem Tower',
      );
      expect(urls.map((u) => u.toString()), ['https://u.org/search.jpg']);
    });

    test('an API error body and a non-200 both mean no results', () async {
      final errorBody = _Wiki(
        summaryStatus: 404,
        articles: {
          'error': {'code': 'badvalue'},
        },
      );
      expect(
        await WikimediaImageSearch(client: errorBody.client)('Belem Tower'),
        isEmpty,
      );

      final server = MockClient((_) async => http.Response('boom', 500));
      expect(
        await WikimediaImageSearch(client: server)('Belem Tower'),
        isEmpty,
      );

      final garbage = MockClient((_) async => http.Response('<html>', 200));
      expect(
        await WikimediaImageSearch(client: garbage)('Belem Tower'),
        isEmpty,
      );

      final offline = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(
        await WikimediaImageSearch(client: offline)('Belem Tower'),
        isEmpty,
      );
    });

    test('too short or too long a query asks nothing', () async {
      final wiki = _Wiki();
      final search = WikimediaImageSearch(client: wiki.client);
      expect(await search(' a '), isEmpty);
      expect(await search(''), isEmpty);
      expect(await search('x' * 201), isEmpty);
      expect(wiki.requests, isEmpty);
    });
  });

  group('OsrmStreetRoute', () {
    const stops = [(lat: 38.69, lng: -9.21), (lat: 38.71, lng: -9.13)];

    Map<String, Object?> ok(List<Object?> coordinates) => {
      'code': 'Ok',
      'routes': [
        {
          'geometry': {'coordinates': coordinates},
        },
      ],
    };

    test(
      'asks the OSRM route service with lng,lat order and swaps it back',
      () async {
        late http.Request seen;
        final client = MockClient((request) async {
          seen = request;
          return _json(
            ok([
              [-9.21, 38.69],
              [-9.17, 38.70],
              [-9.13, 38.71],
            ]),
          );
        });
        final route = await OsrmStreetRoute(client: client)(stops);
        expect(
          seen.url.toString(),
          'https://router.project-osrm.org/route/v1/driving/-9.21,38.69;-9.13,38.71'
          '?overview=full&geometries=geojson&steps=false',
        );
        expect(seen.headers['User-Agent'], contains('open_intelligent_ui'));
        expect(route, [
          (lat: 38.69, lng: -9.21),
          (lat: 38.70, lng: -9.17),
          (lat: 38.71, lng: -9.13),
        ]);
      },
    );

    test('uses a custom server', () async {
      late Uri seen;
      final client = MockClient((request) async {
        seen = request.url;
        return _json(
          ok([
            [1, 2],
            [3, 4],
          ]),
        );
      });
      final route = await OsrmStreetRoute(
        client: client,
        baseUrl: 'https://osrm.example.test',
      )(stops);
      expect(seen.host, 'osrm.example.test');
      expect(route, [(lat: 2.0, lng: 1.0), (lat: 4.0, lng: 3.0)]);
    });

    test(
      'fewer than two or more than 25 stops, or invalid coordinates, ask nothing',
      () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return _json(ok([]));
        });
        final osrm = OsrmStreetRoute(client: client);
        expect(await osrm([stops.first]), isNull);
        expect(await osrm(const []), isNull);
        expect(
          await osrm([
            for (var i = 0; i < 26; i++) (lat: i.toDouble(), lng: 0.0),
          ]),
          isNull,
        );
        expect(await osrm([stops.first, (lat: 91.0, lng: 0.0)]), isNull);
        expect(await osrm([stops.first, (lat: 0.0, lng: -181.0)]), isNull);
        expect(calls, 0);
        expect(OsrmStreetRoute.maxStops, 25);
      },
    );

    test('25 stops are allowed', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(
          ok([
            [0, 0],
            [1, 1],
          ]),
        );
      });
      final route = await OsrmStreetRoute(client: client)([
        for (var i = 0; i < 25; i++) (lat: i.toDouble(), lng: 0.0),
      ]);
      expect(route, hasLength(2));
      expect(calls, 1);
    });

    test('a bad answer is null', () async {
      Future<List<LatLngRecord>?> run(http.Response Function() answer) =>
          OsrmStreetRoute(client: MockClient((_) async => answer()))(stops);

      expect(await run(() => http.Response('nope', 500)), isNull);
      expect(await run(() => http.Response('not json', 200)), isNull);
      expect(await run(() => _json({'code': 'NoRoute', 'routes': []})), isNull);
      expect(
        await run(
          () => _json({
            'code': 'NoRoute',
            'routes': [
              {
                'geometry': {
                  'coordinates': [
                    [0, 0],
                    [1, 1],
                  ],
                },
              },
            ],
          }),
        ),
        isNull,
      );
      expect(
        await run(
          () => _json(
            ok([
              [0, 0],
            ]),
          ),
        ),
        isNull,
        reason: 'one point is not a route',
      );
      expect(
        await run(
          () => _json(
            ok([
              [0, 0],
              ['x', 1],
              [1],
              'y',
            ]),
          ),
        ),
        isNull,
        reason: 'fewer than two usable points',
      );
      expect(await run(() => _json({'code': 'Ok'})), isNull);
      expect(
        await OsrmStreetRoute(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        )(stops),
        isNull,
      );
    });

    test('drops unusable points but keeps the rest', () async {
      final client = MockClient(
        (_) async => _json(
          ok([
            [0, 0],
            ['x', 1],
            [5],
            [2, 3, 99],
          ]),
        ),
      );
      expect(await OsrmStreetRoute(client: client)(stops), [
        (lat: 0.0, lng: 0.0),
        (lat: 3.0, lng: 2.0),
      ]);
    });

    test('a second call for the same stops makes no request', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(
          ok([
            [0, 0],
            [1, 1],
          ]),
        );
      });
      final osrm = OsrmStreetRoute(client: client);
      final first = await osrm(stops);
      expect(await osrm(stops), first);
      expect(calls, 1);
      await osrm(stops.reversed.toList());
      expect(calls, 2);
    });

    test('failures are not cached', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('', 503);
      });
      final osrm = OsrmStreetRoute(client: client);
      await osrm(stops);
      await osrm(stops);
      expect(calls, 2);
    });

    test('the cache keeps the newest 200 routes', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(
          ok([
            [0, 0],
            [1, 1],
          ]),
        );
      });
      final osrm = OsrmStreetRoute(client: client);
      List<LatLngRecord> pair(int i) => [
        (lat: i / 10, lng: 0.0),
        (lat: 0.0, lng: 1.0),
      ];
      for (var i = 0; i < 201; i++) {
        await osrm(pair(i));
      }
      expect(calls, 201);
      await osrm(pair(200));
      expect(calls, 201, reason: 'newest is cached');
      await osrm(pair(0));
      expect(calls, 202, reason: 'oldest was evicted');
    });
  });
}

typedef LatLngRecord = ({double lat, double lng});
