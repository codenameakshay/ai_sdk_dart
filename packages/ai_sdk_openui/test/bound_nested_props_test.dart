import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/bound_test_library.dart';

final class _PayCard implements ComponentSpec {
  const _PayCard();
  @override
  String get typeName => 'PayCard';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'label': S.string(),
    'payment': S.object({'amount': S.any().boundOnly()}).optional(),
    'ids': S.list(S.string().boundOnly()).optional(),
  };
}

final _lib = boundLibrary().extend(
  const LibraryExtension(addComponents: [ComponentAddition(_PayCard())]),
);

final _order = BoundRecord('order', {
  'id': 'o-1',
  'total': {'minor': 500, 'currency': 'INR'},
  'ids': ['a', 'b'],
});

OpenUiSession _open(String program) {
  final s = OpenUiSession(_lib, records: [_order])
    ..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

List<(String?, String?)> _boundIssues(ValidationReport r) => [
  for (final i in r.issues)
    if (i.code == 'bound-only') (i.component, i.path),
];

void main() {
  const literal =
      'root = PayCard("x", {amount: {minor: 1, currency: "INR"}}, ["evil"])';

  test('literals nested in bound-only fields and items are rejected', () {
    final report = _lib.validate(literal, bound: {r'$order'});
    expect(report.ok, isFalse);
    expect(_boundIssues(report), [
      ('PayCard', '/payment/amount'),
      ('PayCard', '/ids/0'),
    ]);
  });

  test('the session hands neither nested literal to the component', () {
    final s = _open(literal);
    final props = s.root!.props;
    expect(props.has('payment'), isFalse);
    expect(props.has('ids'), isFalse);
    expect(props['label'], 'x');
  });

  test('a nested field fed from a bound path passes', () {
    const program = r'root = PayCard("x", {amount: $order.total}, $order.ids)';
    expect(_lib.validate(program, bound: {r'$order'}).ok, isTrue);
    final s = _open(program);
    expect(s.errors, isEmpty);
    expect(s.root!.props['payment'], {
      'amount': {'minor': 500, 'currency': 'INR'},
    });
    expect(s.root!.props['ids'], ['a', 'b']);
  });

  test('bound items inside a list literal pass', () {
    const program = r'root = PayCard("x", null, [$order.id, $order.ids[1]])';
    expect(_lib.validate(program, bound: {r'$order'}).ok, isTrue);
    expect(_open(program).root!.props['ids'], ['o-1', 'b']);
  });

  test('a computed container around bound-only fields is rejected', () {
    final report = _lib.validate(
      r'$p = {amount: {minor: 1}}'
      '\n'
      r'root = PayCard("x", $p)',
      bound: {r'$order'},
    );
    expect(_boundIssues(report), [('PayCard', '/payment')]);
  });

  test('nested literals inside an @Each body are rejected', () {
    final report = _lib.validate(
      r'root = Out(@Each($order.ids, "i", PayCard(i, {amount: 5})))',
      bound: {r'$order'},
    );
    expect(_boundIssues(report), [('PayCard', '/payment/amount')]);
  });

  test('nullable objects, records and lists in expressions are checked', () {
    final pay = ActionSpec(
      'Pay',
      description: '',
      params: {
        'payment': S.object({'amount': S.any().boundOnly()}).nullable(),
        'byId': S.record(S.string(), S.any().boundOnly()).optional(),
        'ids': S.list(S.string().boundOnly()).optional(),
      },
    );
    final lib = boundLibrary(actions: [pay]);
    List<(String?, String?)> issues(String args) => _boundIssues(
      lib.validate(
        'root = Out(@Each(\$order.ids, "i", Out(i, null, @Pay($args))))',
        bound: {r'$order'},
      ),
    );

    expect(issues(r'{amount: $order.total}, {a: $order.id}, [i]'), isEmpty);
    expect(issues('{amount: 1}, {a: 2}, ["x"]'), [
      ('Pay', '/payment/amount'),
      ('Pay', '/byId/a'),
      ('Pay', '/ids/0'),
    ]);
    // A list where an object belongs cannot be checked field by field.
    expect(issues('[1]'), [('Pay', '/payment')]);
    // A scalar has no bound-only field to fill.
    expect(issues('"x"'), isEmpty);
  });

  test('nested literals in a bound-only action param are rejected', () {
    final pay = ActionSpec(
      'Pay',
      description: '',
      params: {
        'order': S.object({'id': S.string().boundOnly()}),
      },
    );
    final lib = boundLibrary(actions: [pay]);
    final report = lib.validate(
      'root = Out(1, null, @Pay({id: "o-9"}))',
      bound: {r'$order'},
    );
    expect(_boundIssues(report), [('Pay', '/order/id')]);
    expect(
      lib
          .validate(
            r'root = Out(1, null, @Pay({id: $order.id}))',
            bound: {r'$order'},
          )
          .ok,
      isTrue,
    );
  });
}
