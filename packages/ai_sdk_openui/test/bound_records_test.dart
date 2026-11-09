import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'amount': S.any().boundOnly().optional(),
    'action': actionSchema.optional(),
  };
}

final _pay = ActionSpec(
  'Pay',
  description: 'Pays an order',
  params: {'orderId': S.string().boundOnly()},
);
final _lib = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  actions: [_pay],
);

final _order = BoundRecord('order', {
  'id': 'o-1',
  'total': {'minor': 12345, 'currency': 'INR'},
});
final _items = BoundRecord('items', [
  {'price': 5},
  {'price': 7},
]);

OpenUiSession _open(String program, [List<BoundRecord> records = const []]) {
  final s = OpenUiSession(_lib, records: [_order, _items, ...records])
    ..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

List<OpenUiError> _bound(OpenUiSession s) => [
  for (final e in s.errors)
    if (e.code == OpenUiErrorCode.boundOnly) e,
];

void main() {
  test('a bound record reads as a \$variable', () {
    final s = _open(r'root = Out($order.total.minor)');
    expect(s.root!.props['value'], 12345);
    expect(s.errors, isEmpty);
  });

  test('a literal in a bound-only prop is rejected and dropped', () {
    final s = _open('root = Out(1, {minor: 1, currency: "INR"})');
    final errors = _bound(s);
    expect(errors, hasLength(1));
    expect(errors.single.component, 'Out');
    expect(errors.single.statementId, 'root');
    expect(
      errors.single.message,
      r'field "/amount" accepts only a path into a host-bound $variable, such as $order.total',
    );
    expect(s.root!.props.has('amount'), isFalse);
  });

  test('a path into a record passes', () {
    final s = _open(r'root = Out(1, $order.total)');
    expect(s.errors, isEmpty);
    expect(s.root!.props['amount'], {'minor': 12345, 'currency': 'INR'});
  });

  test('a \$variable the program declares is not a record', () {
    final s = _open(
      r'$fake = {minor: 1}'
      '\n'
      r'root = Out(1, $fake)',
    );
    expect(_bound(s), hasLength(1));
  });

  test('a computed value is rejected', () {
    final s = _open(r'root = Out(1, $order.total.minor + 1)');
    expect(_bound(s), hasLength(1));
  });

  test('an index into a record is a path', () {
    final s = _open(r'root = Out(1, $items[1].price)');
    expect(s.errors, isEmpty);
    expect(s.root!.props['amount'], 7);
  });

  test('an @Each item over a record is a path', () {
    final s = _open(r'root = Out(@Each($items, "it", Out(1, it.price)))');
    expect(s.errors, isEmpty);
    expect(
      [for (final e in s.root!.props.elements('value')) e.props['amount']],
      [5, 7],
    );
  });

  test('an @Each item over a literal list is not a path', () {
    final s = _open('root = Out(@Each([{p: 1}], "it", Out(1, it.p)))');
    final errors = _bound(s);
    expect(errors, hasLength(1));
    expect(errors.single.component, 'Out');
  });

  test('an inner loop does not inherit an outer bound loop variable', () {
    final s = _open(
      r'root = Out(@Each($items, "it", @Each([{price: 9}], "it", Out(1, it.price))))',
    );
    expect(_bound(s), hasLength(1));
  });

  test('@Set and @Reset never write a record', () async {
    final s = _open(
      r'root = Out($order.id, null, Action([@Set($order, "x"), @Reset($order)]))',
    );
    await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
    expect(s.root!.props['value'], 'o-1');
    expect(s.state.containsKey(r'$order'), isFalse);
  });

  test('records are not saved in state', () {
    final s = _open(r'root = Out($order.id)');
    expect(s.state, isEmpty);
  });

  test('a bound-only action param takes a path', () {
    var s = _open('root = Out(1, null, @Pay("o-1"))');
    final errors = _bound(s);
    expect(errors, hasLength(1));
    expect(errors.single.component, 'Pay');
    expect(s.root!.props.action('action')!.isEmpty, isTrue);

    s = _open(r'root = Out(1, null, @Pay($order.id))');
    expect(s.errors, isEmpty);
    expect(s.root!.props.action('action')!.isEmpty, isFalse);
  });

  test('library.parse checks the bound names it is given', () {
    expect(
      _lib.parse(r'root = Out(1, $order.total)', bound: {r'$order'}).errors,
      isEmpty,
    );
    expect(
      _lib.parse(r'root = Out(1, $order.total)').errors.single,
      contains('accepts only a path'),
    );
  });
}
