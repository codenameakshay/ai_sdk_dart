import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

const _userAgent = {
  'User-Agent':
      'open_intelligent_ui (https://github.com/codenameakshay/ai_sdk_dart)',
};
const _timeout = Duration(seconds: 8);

/// Photo search for `SearchImage`, called straight from the app: the
/// Wikipedia article with that exact title first (its lead image and up to two
/// more photos), then a Wikipedia and Wikimedia Commons search. A port of the
/// reference's `/api/wiki` and `/api/image-search` routes. Pass an instance as
/// [OpenUiServices.searchImages].
final class WikimediaImageSearch {
  WikimediaImageSearch({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  final Map<String, List<Uri>> _cache = {};

  static final _skip = RegExp(
    r'\.svg|icon|logo|map|flag|seal|coat_of_arms|signature|diagram',
    caseSensitive: false,
  );
  static final _skipArticle = RegExp(
    r'\.svg|icon|logo|map|flag|seal',
    caseSensitive: false,
  );
  static const _width = 960;

  Future<List<Uri>> call(String query) async {
    final q = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.length < 2 || q.length > 200) return const [];
    if (_cache[q] case final hit?) return hit;
    final results = await Future.wait([_article(q), _search(q)]);
    final all = <Uri>[];
    for (final u in [...results[0], ...results[1]]) {
      if (!all.contains(u)) all.add(u);
    }
    if (all.isNotEmpty) {
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      _cache[q] = all;
    }
    return all;
  }

  Future<Object?> _get(Uri url) async {
    final response = await _client
        .get(url, headers: _userAgent)
        .timeout(_timeout);
    if (response.statusCode == 404) return const <String, Object?>{};
    if (response.statusCode != 200) {
      throw http.ClientException('${url.host} ${response.statusCode}', url);
    }
    return jsonDecode(response.body);
  }

  Future<List<Uri>> _article(String title) async {
    try {
      final t = Uri.encodeComponent(title.replaceAll(' ', '_'));
      final results = await Future.wait([
        _get(Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$t')),
        _get(
          Uri.parse('https://en.wikipedia.org/api/rest_v1/page/media-list/$t'),
        ),
      ]);
      final summary = results[0], media = results[1];
      final photos = <String>[];
      String key(String u) => Uri.decodeComponent(
        u.split('?').first.split('/').last,
      ).replaceFirst(RegExp(r'^\d+px-'), '');
      final lead = _path(summary, ['thumbnail', 'source']);
      if (lead is String) photos.add(lead);
      for (final item in _list(_path(media, ['items']))) {
        if (photos.length >= 3) break;
        if (item is! Map || item['type'] != 'image') continue;
        final srcset = _list(item['srcset']);
        final src = srcset.isEmpty ? null : _path(srcset.first, ['src']);
        if (src is! String || _skipArticle.hasMatch(src)) continue;
        final url = src.startsWith('//') ? 'https:$src' : src;
        if (!photos.any((p) => key(p) == key(url))) photos.add(url);
      }
      return [for (final p in photos) ?_https(p)];
    } on Object {
      return const [];
    }
  }

  Future<List<Object?>> _query(String host, Map<String, String> params) async {
    final url = Uri.https(host, '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
      ...params,
    });
    final data = await _get(url);
    if (data is Map && data['error'] != null) {
      throw http.ClientException('$host error', url);
    }
    final pages = [
      ..._list(_path(data, ['query', 'pages'])),
    ];
    int index(Object? p) =>
        p is Map && p['index'] is num ? (p['index'] as num).toInt() : 0;
    pages.sort((a, b) => index(a) - index(b));
    return pages;
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 3)
      .toList();

  Future<List<Uri>> _search(String q) async {
    try {
      final images = <String>[];
      void add(Object? url) {
        if (url is String &&
            url.startsWith('https://') &&
            !_skip.hasMatch(url) &&
            !images.contains(url)) {
          images.add(url);
        }
      }

      final wanted = _words(q).toSet();
      final articles = await _query('en.wikipedia.org', {
        'generator': 'search',
        'gsrsearch': q,
        'gsrlimit': '6',
        'prop': 'pageimages',
        'piprop': 'thumbnail',
        'pithumbsize': '$_width',
      });
      for (final page in articles) {
        final title = _path(page, ['title']);
        if (title is String && _words(title).any(wanted.contains)) {
          add(_path(page, ['thumbnail', 'source']));
        }
      }
      final terms = q.split(RegExp(r'\s+'));
      final tries = {
        terms.join(' '),
        terms.take(3).join(' '),
        terms.take(2).join(' '),
      };
      for (final t in tries) {
        if (images.length >= 3) break;
        final files = await _query('commons.wikimedia.org', {
          'generator': 'search',
          'gsrsearch': '$t filetype:bitmap',
          'gsrnamespace': '6',
          'gsrlimit': '6',
          'prop': 'imageinfo',
          'iiprop': 'url|mime',
          'iiurlwidth': '$_width',
        });
        for (final page in files) {
          final info = _list(_path(page, ['imageinfo']));
          if (info.isEmpty || info.first is! Map) continue;
          final first = info.first as Map;
          if (first['mime'] is String &&
              (first['mime'] as String).startsWith('image/')) {
            add(first['thumburl'] ?? first['url']);
          }
        }
      }
      return [for (final i in images.take(4)) ?_https(i)];
    } on Object {
      return const [];
    }
  }
}

Object? _path(Object? v, List<Object> keys) {
  var cur = v;
  for (final k in keys) {
    if (k is int && cur is List && k < cur.length) {
      cur = cur[k];
    } else if (k is String && cur is Map) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur;
}

List<Object?> _list(Object? v) => v is List ? v : const [];

Uri? _https(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'https' ? uri : null;
}
