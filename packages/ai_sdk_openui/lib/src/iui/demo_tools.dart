import '../lang/js.dart';
import '../spec/library.dart';

const _days = {
  'type': 'number',
  'description': 'How many days back from today, 1 to 365 (default 90)',
};

Map<String, Object?> _rows(Map<String, Object?> item) => {
  'type': 'object',
  'properties': {
    'rows': {'type': 'array', 'items': item},
  },
};

/// Demo data tools for Query-backed dashboards: a store's orders, support
/// tickets and website traffic for the days up to today. A day's rows depend
/// only on its date. [now] defaults to the current time.
List<OpenUiTool> demoTools({DateTime Function()? now}) {
  final clock = now ?? DateTime.now;
  return [
    OpenUiTool(
      name: 'get_orders',
      description: "An online store's orders, one row per order, newest last",
      inputSchema: const {
        'type': 'object',
        'properties': {'days': _days},
      },
      outputSchema: _rows({
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'region': {
            'type': 'string',
            'enum': ['North', 'South', 'East', 'West'],
          },
          'channel': {
            'type': 'string',
            'enum': ['Web', 'Mobile', 'Retail'],
          },
          'category': {'type': 'string'},
          'product': {'type': 'string'},
          'units': {'type': 'number'},
          'amount': {'type': 'number', 'description': 'Order total in USD'},
        },
      }),
      call: (args) async => {'rows': _orders(_lastDays(args, clock()))},
    ),
    OpenUiTool(
      name: 'get_tickets',
      description:
          'Support tickets opened, one row per ticket; hours and csat are set once a ticket is solved',
      inputSchema: const {
        'type': 'object',
        'properties': {'days': _days},
      },
      outputSchema: _rows({
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'opened': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'team': {
            'type': 'string',
            'enum': ['Billing', 'Technical', 'Accounts', 'Shipping'],
          },
          'priority': {
            'type': 'string',
            'enum': ['low', 'normal', 'high', 'urgent'],
          },
          'status': {
            'type': 'string',
            'enum': ['open', 'pending', 'solved'],
          },
          'hours': {'type': 'number', 'description': 'Hours to resolve'},
          'csat': {'type': 'number', 'description': 'Satisfaction 1 to 5'},
        },
      }),
      call: (args) async => {'rows': _tickets(_lastDays(args, clock()))},
    ),
    OpenUiTool(
      name: 'get_traffic',
      description:
          'Daily website visits and signups, one row per day and source',
      inputSchema: const {
        'type': 'object',
        'properties': {'days': _days},
      },
      outputSchema: _rows({
        'type': 'object',
        'properties': {
          'date': {'type': 'string', 'description': 'YYYY-MM-DD'},
          'source': {
            'type': 'string',
            'enum': ['Search', 'Social', 'Email', 'Direct', 'Referral'],
          },
          'visits': {'type': 'number'},
          'signups': {'type': 'number'},
        },
      }),
      call: (args) async => {'rows': _traffic(_lastDays(args, clock()))},
    ),
  ];
}

const _dayMs = 86400000;

/// JavaScript `Math.imul`, exact on the web too.
int _imul(int a, int b) {
  final aLo = a & 0xffff, aHi = (a >>> 16) & 0xffff;
  return ((aLo * b) + (((aHi * b) & 0xffff) << 16)).toSigned(32);
}

/// mulberry32 seeded from a string, as the reference's `rng`.
double Function() _rng(String seed) {
  var h = 1779033703;
  for (final c in seed.codeUnits) {
    h = _imul(h ^ c, 3432918353);
  }
  var a = h.toUnsigned(32);
  return () {
    a = (a + 0x6d2b79f5).toSigned(32);
    var t = _imul(a ^ (a.toUnsigned(32) >>> 15), 1 | a);
    t = (t + _imul(t ^ (t.toUnsigned(32) >>> 7), 61 | t)).toSigned(32) ^ t;
    return (t ^ (t.toUnsigned(32) >>> 14)).toUnsigned(32) / 4294967296;
  };
}

T _pick<T>(double Function() r, List<T> list, [List<num>? weights]) {
  if (weights == null) return list[(r() * list.length).floor()];
  var x = r() * weights.fold<num>(0, (a, b) => a + b);
  for (var i = 0; i < list.length; i++) {
    x -= weights[i];
    if (x < 0) return list[i];
  }
  return list.last;
}

List<String> _lastDays(Map<String, Object?> input, DateTime now) {
  final raw = Js.number(input['days'] ?? 90);
  final n = raw.isFinite ? raw.round().clamp(1, 365) : 90;
  final today = now.millisecondsSinceEpoch ~/ _dayMs;
  return [
    for (var i = 0; i < n; i++)
      DateTime.fromMillisecondsSinceEpoch(
        (today - n + 1 + i) * _dayMs,
        isUtc: true,
      ).toIso8601String().substring(0, 10),
  ];
}

DateTime _utc(String date) => DateTime.parse('${date}T00:00:00Z');
bool _weekend(String date) => _utc(date).weekday >= DateTime.saturday;
double _growth(String date) =>
    1 + (_utc(date).millisecondsSinceEpoch / _dayMs - 20000) / 1500;
num _round2(double v) => (v * 100).round() / 100;

const _products = [
  ('Trail runner', 'Outdoors', 128),
  ('Rain shell', 'Outdoors', 164),
  ('Camp stove', 'Outdoors', 89),
  ('Linen shirt', 'Apparel', 58),
  ('Wool sweater', 'Apparel', 96),
  ('Everyday tee', 'Apparel', 24),
  ('Ceramic mug set', 'Home', 36),
  ('Oak side table', 'Home', 210),
  ('Throw blanket', 'Home', 72),
  ('Wireless earbuds', 'Electronics', 149),
  ('Smart lamp', 'Electronics', 64),
  ('Portable speaker', 'Electronics', 119),
];

List<Map<String, Object?>> _orders(List<String> days) => [
  for (final date in days)
    ...() {
      final r = _rng('orders:$date');
      final count =
          ((18 + r() * 14) * (_weekend(date) ? 1.35 : 1) * _growth(date))
              .round();
      return [
        for (var i = 0; i < count; i++)
          () {
            final p = _pick(r, _products, [
              9,
              5,
              4,
              8,
              5,
              10,
              6,
              2,
              4,
              6,
              5,
              4,
            ]);
            final units = _pick(r, [1, 1, 1, 2, 2, 3, 4]);
            final channel = _pick(
              r,
              ['Web', 'Mobile', 'Retail'],
              [5, 3 * _growth(date), 2],
            );
            return <String, Object?>{
              'id': '${date.replaceAll('-', '')}-${i + 1}',
              'date': date,
              'region': _pick(
                r,
                ['North', 'South', 'East', 'West'],
                [3, 2, 3, 4],
              ),
              'channel': channel,
              'category': p.$2,
              'product': p.$1,
              'units': units,
              'amount': _round2(p.$3 * units * (0.85 + r() * 0.2)),
            };
          }(),
      ];
    }(),
];

const _teamBase = {
  'Billing': 9,
  'Technical': 22,
  'Accounts': 6,
  'Shipping': 14,
};
const _priorityFactor = {'low': 1.6, 'normal': 1.0, 'high': 0.6, 'urgent': 0.3};

List<Map<String, Object?>> _tickets(List<String> days) => [
  for (final (d, date) in days.indexed)
    ...() {
      final r = _rng('tickets:$date');
      final age = days.length - 1 - d;
      final count = (6 + r() * 10).round();
      return [
        for (var i = 0; i < count; i++)
          () {
            final team = _pick(
              r,
              ['Billing', 'Technical', 'Accounts', 'Shipping'],
              [3, 5, 2, 3],
            );
            final priority = _pick(
              r,
              ['low', 'normal', 'high', 'urgent'],
              [3, 6, 3, 1],
            );
            final base = _teamBase[team]! * _priorityFactor[priority]!;
            final hours = (base * (0.4 + r() * 1.6) * 10).round() / 10;
            final solved = age * 24 > hours * 1.5 || r() < 0.2;
            final status = solved ? 'solved' : (r() < 0.6 ? 'open' : 'pending');
            final csat = (5.4 - hours / 14 - r() * 1.8).round().clamp(1, 5);
            return <String, Object?>{
              'id':
                  'T-${date.replaceAll('-', '').substring(2)}${'${i + 1}'.padLeft(2, '0')}',
              'opened': date,
              'team': team,
              'priority': priority,
              'status': status,
              if (solved) 'hours': hours,
              if (solved && r() < 0.7) 'csat': csat,
            };
          }(),
      ];
    }(),
];

const _sources = {
  'Search': (1800, 0.021),
  'Social': (950, 0.012),
  'Email': (420, 0.045),
  'Direct': (700, 0.03),
  'Referral': (300, 0.035),
};

List<Map<String, Object?>> _traffic(List<String> days) => [
  for (final date in days)
    ...() {
      final r = _rng('traffic:$date');
      return [
        for (final MapEntry(key: source, value: (visits, rate))
            in _sources.entries)
          () {
            final v =
                (visits *
                        (_weekend(date) ? 0.75 : 1) *
                        _growth(date) *
                        (0.8 + r() * 0.4))
                    .round();
            return <String, Object?>{
              'date': date,
              'source': source,
              'visits': v,
              'signups': (v * rate * (0.7 + r() * 0.6)).round(),
            };
          }(),
      ];
    }(),
];
