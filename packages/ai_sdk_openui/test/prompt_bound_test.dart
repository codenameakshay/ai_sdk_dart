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

const _boundSection =
    '## Bound Data\n\n'
    'The host provides these read-only \$variables. Read them with dot and index access (`\$name.field`, `\$name[0]`). Never copy their values into literals, and never @Set, @Reset or bind them to an input.\n\n'
    '- \$order: {id: string, total: {minor: number, currency: string}} — The order being paid\n'
    '- \$orders: {id: string}[]';

final _sameRecords = [
  BoundRecord('order', {
    'id': 'o-1',
    'total': {'minor': 12345, 'currency': 'INR'},
  }, description: 'The order being paid'),
  BoundRecord(
    'orders',
    const [],
    schema: {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      },
    },
  ),
];

void main() {
  test('Bound Data lists each record with its type and description', () {
    final prompt = _lib.systemPrompt(PromptOptions(records: _sameRecords));
    expect(prompt, contains(_boundSection));
    expect(describeBoundRecords(_sameRecords), _boundSection);
  });

  test('Current State lists only seeded \$variables', () {
    final prompt = _lib.systemPrompt(
      const PromptOptions(
        state: {
          r'$tab': 'overview',
          r'$qty': 2,
          'contact': {
            'name': {'value': 'Ana'},
          },
        },
      ),
    );
    expect(
      prompt,
      contains(
        '## Current State\n\n'
        'These \$variables already hold values. Read them; do not declare them again:\n'
        '- \$tab = "overview"\n'
        '- \$qty = 2',
      ),
    );
    expect(prompt, isNot(contains('contact')));
  });

  test('records turn on the \$variable rules', () {
    final withRecord = _lib.systemPrompt(
      PromptOptions(records: [BoundRecord('order', 1)]),
    );
    expect(withRecord, contains('Declare mutable state with `\$varName'));
    expect(
      _lib.systemPrompt(),
      isNot(contains('Declare mutable state with `\$varName')),
    );
  });

  test('a bound-only prop prints \$bound<T> and its rule', () {
    expect(
      (_lib.toSpec()['components'] as Map)['Out']['signature'],
      r'Out(value: any, amount?: $bound<any>, action?: ActionExpression)',
    );
    expect(
      (_lib.toSpec()['actions'] as Map)['Pay']['signature'],
      r'Pay(orderId: $bound<string>)',
    );
    expect(
      _lib.systemPrompt(),
      contains(
        r'Props marked `$bound<type>` take only a path into a host $variable from Bound Data, such as `$name.field`. A literal or computed value there is rejected.',
      ),
    );
  });

  test('the JSON Schema marks bound-only props', () {
    expect(
      ((_lib.toJsonSchema()[r'$defs'] as Map)['Out']
          as Map)['properties']['amount'],
      {'x-openui-bound': true},
    );
    expect(
      (_lib.toJsonSchema()['actions']
          as Map)['Pay']['params']['properties']['orderId'],
      {'type': 'string', 'x-openui-bound': true},
    );
  });

  test('copies keep the bound-only flag', () {
    expect(S.string().boundOnly().optional().isBoundOnly, isTrue);
    expect(S.string().boundOnly().nullable().isBoundOnly, isTrue);
    expect(S.string().boundOnly().tag('X').isBoundOnly, isTrue);
    expect(S.string().isBoundOnly, isFalse);
  });

  test('a record name must be an identifier', () {
    expect(() => BoundRecord('a-b', 1), throwsArgumentError);
    expect(BoundRecord('order', 1).variable, r'$order');
  });
}
