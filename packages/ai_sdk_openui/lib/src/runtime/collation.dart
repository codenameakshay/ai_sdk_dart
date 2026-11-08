import 'dart:convert';

import 'collation_table.dart';

/// `String.prototype.localeCompare` as Node 26 runs it with no locale: ICU's
/// root collation at tertiary strength with punctuation not ignored, on the
/// canonical decomposition of each string. Strings equal at all three levels
/// compare 0, as in JavaScript.
int localeCompare(String a, String b) {
  if (a == b) return 0;
  final x = _elements(a);
  final y = _elements(b);
  for (var level = 0; level < 3; level++) {
    final c = _compareLevel(x, y, level);
    if (c != 0) return c;
  }
  return 0;
}

// A collation element is primary << 14 | secondary << 5 | tertiary: under 2^31, so exact on the web.
int _weight(int ce, int level) => switch (level) {
  0 => ce >> 14,
  1 => (ce >> 5) & 0x1FF,
  _ => ce & 0x1F,
};

int _compareLevel(List<int> x, List<int> y, int level) {
  var i = 0;
  var j = 0;
  while (true) {
    while (i < x.length && _weight(x[i], level) == 0) {
      i++;
    }
    while (j < y.length && _weight(y[j], level) == 0) {
      j++;
    }
    if (i == x.length || j == y.length) {
      return i == x.length ? (j == y.length ? 0 : -1) : 1;
    }
    final d = _weight(x[i], level) - _weight(y[j], level);
    if (d != 0) return d < 0 ? -1 : 1;
    i++;
    j++;
  }
}

final class _Table {
  final Map<int, List<int>> singles = {};
  final Map<int, List<(List<int>, List<int>)>> contractions = {};
  final Map<int, List<int>> decompositions = {};
  final Map<int, int> combiningClass = {};
  final Map<int, int> hanRank = {};
}

final _Table _table = _decode();

_Table _decode() {
  final table = _Table();
  final bytes = base64Decode(collationData);
  var pos = 0;
  int next() {
    var n = 0;
    var scale = 1;
    while (true) {
      final b = bytes[pos++];
      n += (b & 0x7F) * scale;
      if (b < 0x80) return n;
      scale *= 128;
    }
  }

  int signed(int z) => z.isEven ? z ~/ 2 : -(z + 1) ~/ 2;
  var lastP = 0;
  List<int> elements(int count) => [
    for (var k = 0; k < count; k++) (lastP += signed(next())) << 14 | next(),
  ];

  var end = 0;
  for (var r = 0; r < collationCounts[0]; r++) {
    final cp = end + next();
    final head = next();
    final run = head ~/ 32 + 1;
    final ces = elements(head % 32);
    table.singles[cp] = ces;
    for (var k = 1; k < run; k++) {
      table.singles[cp + k] = [ces.single + (k << 14)];
    }
    end = cp + run;
  }
  for (var r = 0; r < collationCounts[1]; r++) {
    final seq = [for (var k = next(); k > 0; k--) next()];
    (table.contractions[seq.first] ??= []).add((
      seq.sublist(1),
      elements(next()),
    ));
  }
  for (final list in table.contractions.values) {
    list.sort((a, b) => b.$1.length - a.$1.length);
  }
  var cp = 0;
  for (var r = 0; r < collationCounts[2]; r++) {
    cp += next();
    table.decompositions[cp] = [for (var k = next(); k > 0; k--) next()];
  }
  end = 0;
  for (var r = 0; r < collationCounts[3]; r++) {
    final start = end + next();
    final run = next();
    final value = next();
    for (var k = 0; k < run; k++) {
      table.combiningClass[start + k] = value;
    }
    end = start + run;
  }
  end = 0;
  var rank = 0;
  for (var r = 0; r < collationCounts[4]; r++) {
    final start = end + signed(next());
    final run = next();
    for (var k = 0; k < run; k++) {
      table.hanRank[start + k] = rank++;
    }
    end = start + run;
  }
  return table;
}

int _ccc(int cp) => _table.combiningClass[cp] ?? 0;

/// The canonical decomposition (NFD) of [s] as code points.
List<int> _nfd(String s) {
  final out = <int>[];
  for (final cp in s.runes) {
    if (cp >= 0xAC00 && cp <= 0xD7A3) {
      final index = cp - 0xAC00;
      out
        ..add(0x1100 + index ~/ 588)
        ..add(0x1161 + (index % 588) ~/ 28);
      if (index % 28 != 0) out.add(0x11A7 + index % 28);
    } else {
      out.addAll(_table.decompositions[cp] ?? [cp]);
    }
  }
  // Canonical ordering: a stable sort of each run of non-starters by combining class.
  for (var i = 1; i < out.length; i++) {
    final cp = out[i];
    final c = _ccc(cp);
    if (c == 0) continue;
    var j = i;
    while (j > 0 && _ccc(out[j - 1]) > c) {
      out[j] = out[j - 1];
      j--;
    }
    out[j] = cp;
  }
  return out;
}

List<int>? _contraction(int first, List<int> tail) {
  for (final (t, ces)
      in _table.contractions[first] ?? const <(List<int>, List<int>)>[]) {
    if (t.length != tail.length) continue;
    var k = 0;
    while (k < t.length && t[k] == tail[k]) {
      k++;
    }
    if (k == t.length) return ces;
  }
  return null;
}

/// UCA's main algorithm, steps S2.1 to S2.4, over the NFD of [s].
List<int> _elements(String s) {
  final cps = _nfd(s);
  final out = <int>[];
  var i = 0;
  while (i < cps.length) {
    final first = cps[i];
    var ces = _table.singles[first];
    var length = 1;
    // S2.1: the longest contiguous match.
    for (final (tail, candidate)
        in _table.contractions[first] ?? const <(List<int>, List<int>)>[]) {
      if (i + tail.length >= cps.length) continue;
      var k = 0;
      while (k < tail.length && cps[i + 1 + k] == tail[k]) {
        k++;
      }
      if (k == tail.length) {
        ces = candidate;
        length = 1 + tail.length;
        break;
      }
    }
    // S2.1.1 to S2.1.3: unblocked non-starters that extend the match.
    if (_table.contractions.containsKey(first)) {
      final matched = cps.sublist(i + 1, i + length);
      var j = i + length;
      var maxSkipped = 0;
      while (j < cps.length && _ccc(cps[j]) != 0) {
        final c = _ccc(cps[j]);
        final extended = maxSkipped < c
            ? _contraction(first, [...matched, cps[j]])
            : null;
        if (extended != null) {
          matched.add(cps.removeAt(j));
          ces = extended;
        } else {
          if (c > maxSkipped) maxSkipped = c;
          j++;
        }
      }
    }
    out.addAll(ces ?? _implicit(first));
    i += length;
  }
  return out;
}

/// Two collation elements for a code point with no entry: Han by its ICU rank, then other scripts, then the rest by code point.
List<int> _implicit(int cp) {
  final rank = _table.hanRank[cp];
  if (rank != null) return _pair(0xFB40 + (rank >> 15), rank & 0x7FFF);
  const r = collationImplicitScripts;
  for (var k = 0; k < r.length; k += 4) {
    if (cp >= r[k] && cp <= r[k + 1]) return _pair(r[k + 2], cp - r[k + 3]);
  }
  return _pair(0xFBC0 + (cp >> 15), cp & 0x7FFF);
}

List<int> _pair(int lead, int low) => [
  lead << 14 | 0x20 << 5 | 2,
  (low | 0x8000) << 14,
];
