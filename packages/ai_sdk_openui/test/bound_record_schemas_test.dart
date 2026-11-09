import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/validator_library.dart';

const _order = <String, Object?>{
  'type': 'object',
  'properties': {
    'id': {'type': 'string'},
    'total': {
      'type': 'object',
      'properties': {
        'minor': {'type': 'integer'},
        'currency': {'type': 'string'},
      },
    },
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'price': {'type': 'number'},
        },
      },
    },
    'tags': {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
  },
  'additionalProperties': false,
};

const _schemas = {r'$order': _order};

List<(String, String?)> _issues(String program, {bool schemas = true}) => [
  for (final i
      in validatorLibrary
          .validate(
            program,
            bound: {r'$order'},
            boundSchemas: schemas ? _schemas : const {},
          )
          .issues)
    (i.code, i.path),
];

void main() {
  test('a bound path the record schema lacks is rejected', () {
    expect(_issues(r'root = Out(1, $order.nope)', schemas: false), isEmpty);
    expect(_issues(r'root = Out(1, $order.nope)'), [
      ('unknown-bound-path', '/amount'),
    ]);
    expect(_issues(r'root = Out($order.total.nope)'), [
      ('unknown-bound-path', '/value'),
    ]);
    expect(_issues(r'root = Out(1, null, null, {amount: $order.nope})'), [
      ('unknown-bound-path', '/payment/amount'),
    ]);
    expect(_issues(r'root = Out([1, $order.id.nope])'), [
      ('unknown-bound-path', '/value/1'),
    ]);
    expect(_issues(r'root = Out(1, $order.items.first)'), [
      ('unknown-bound-path', '/amount'),
    ]);
  });

  test('a bound value whose type does not fit the prop is rejected', () {
    expect(_issues(r'root = Out(1, null, null, null, $order.id)'), [
      ('type-mismatch', '/money'),
    ]);
    expect(_issues(r'root = Out(1, null, null, null, $order.total)'), isEmpty);
  });

  test('a computed index into a record is not a bound path', () {
    const program =
        r'$k = "id"'
        '\n'
        r'root = Out(1, $order[$k])';
    expect(_issues(program, schemas: false), [('bound-only', '/amount')]);

    final session = OpenUiSession(
      validatorLibrary,
      records: [
        BoundRecord('order', {
          'id': 'o-1',
          'total': {'minor': 500, 'currency': 'INR'},
        }),
      ],
    )..update(program, streaming: false);
    addTearDown(session.dispose);
    expect(session.root!.props.has('amount'), isFalse);
  });

  test('paths the schema has pass', () {
    for (final program in [
      r'root = Out($order.id, $order.total, null, {amount: $order.total}, $order.total)',
      r'root = Out(@Each($order.items, "it", Out(it.price, it.price)))',
      r'root = Out($order.items[0].price, $order.items.length)',
      r'root = Out($order["id"], $order.id.length)',
      r'root = Out($order.tags.any, $order.items[$order.id])',
      r'root = Out(1, $other.anything)',
    ]) {
      expect(
        validatorLibrary
            .validate(
              program,
              bound: {r'$order', r'$other'},
              boundSchemas: _schemas,
            )
            .issues,
        isEmpty,
        reason: program,
      );
    }
  });

  test('a loop item reads the schema of the list items', () {
    expect(_issues(r'root = Out(@Each($order.items, "it", Out(1, it.nope)))'), [
      ('unknown-bound-path', '/amount'),
    ]);
    expect(_issues(r'root = Out(@Each($order.nope, "it", Out(1, it.price)))'), [
      ('unknown-bound-path', '/amount'),
    ]);
  });

  test('union types in a record schema join their options', () {
    const schemas = {
      r'$order': {
        'type': 'object',
        'properties': {
          'maybe': {
            'anyOf': [
              {'type': 'string'},
              {'type': 'null'},
            ],
          },
          'loose': {
            'oneOf': [
              {'type': 'string'},
              <String, Object?>{},
            ],
          },
        },
      },
    };
    List<String> codes(String path) => [
      for (final i
          in validatorLibrary
              .validate(
                'root = Out(1, null, null, null, $path)',
                boundSchemas: schemas,
              )
              .issues)
        i.code,
    ];
    expect(codes(r'$order.maybe'), ['type-mismatch']);
    expect(codes(r'$order.loose'), isEmpty);
  });

  test('the message names the missing path', () {
    String message(String path) => validatorLibrary
        .validate('root = Out(1, $path)', boundSchemas: _schemas)
        .issues
        .single
        .message;
    expect(message(r'$order.items[0].nope'), contains(r'$order.items[0].nope'));
    expect(
      message(r'$order.items[$order.id].nope'),
      contains(r'$order.items[$order.id].nope'),
    );
    final loop = validatorLibrary
        .validate(
          r'root = Out(@Each($order.items, "it", Out(1, it.nope)))',
          boundSchemas: _schemas,
        )
        .issues
        .single;
    expect(loop.message, contains('reads it.nope,'));
  });

  test('a query @Each without a loop name still checks its body', () {
    final report = validatorLibrary.validate(
      'q = Query("t", {a: @Each(\$order.items, 1, 2)})\nroot = Out(q)',
      boundSchemas: _schemas,
    );
    expect(report.issues.where((i) => i.isWarning == false), isEmpty);
  });

  test('schema names count as bound names', () {
    final report = validatorLibrary.validate(
      r'root = Out(1, $order.total)',
      boundSchemas: _schemas,
    );
    expect(report.ok, isTrue);
    expect(
      validatorLibrary
          .parse(r'root = Out(1, $order.nope)', boundSchemas: _schemas)
          .errors,
      [contains(r'$order.nope')],
    );
  });
}
