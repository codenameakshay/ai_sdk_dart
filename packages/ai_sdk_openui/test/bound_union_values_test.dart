import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Value implements ComponentSpec {
  const _Value(this.schema);
  final Schema schema;
  @override
  String get typeName => 'Value';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {'value': schema.optional()};
}

void main() {
  for (final entry in [
    (S.string(), '"forged"'),
    (S.number(), '12'),
    (S.boolean(), 'true'),
    (S.list(S.string()), '["forged"]'),
    (S.object({'id': S.string()}), '{id: "forged"}'),
  ]) {
    final schema = S.union([entry.$1.boundOnly()]).nullable();
    final value = _Value(schema);
    final library = OpenUiLibrary(root: value, components: [value]);
    for (final expression in [
      entry.$2,
      'true ? ${entry.$2} : null',
      r'$input',
    ]) {
      test('a bound-only union rejects $expression for ${entry.$2}', () {
        final session = OpenUiSession(library);
        addTearDown(session.dispose);
        final program = 'root = Value($expression)';
        expect(
          library.validate(program).issues.map((e) => e.code),
          contains('bound-only'),
        );
        session.update(program, streaming: false);
        expect(
          session.errors.map((e) => e.code),
          contains(OpenUiErrorCode.boundOnly),
        );
        expect(session.root!.props.has('value'), isFalse);
      });
    }
  }

  test('an unbound union branch and a host path remain usable', () {
    final value = _Value(S.union([S.string().boundOnly(), S.number()]));
    final library = OpenUiLibrary(root: value, components: [value]);
    final session = OpenUiSession(
      library,
      records: [BoundRecord('id', 'host')],
    );
    addTearDown(session.dispose);
    for (final entry in [('12', 12), (r'$id', 'host'), ('null', null)]) {
      session.update('root = Value(${entry.$1})', streaming: false);
      expect(session.errors, isEmpty);
      expect(session.root!.props['value'], entry.$2);
    }
  });

  test('overlapping union alternatives retain bound-only constraints', () {
    final value = _Value(S.union([S.string().boundOnly(), S.string()]));
    final library = OpenUiLibrary(root: value, components: [value]);
    expect(
      library.validate('root = Value("forged")').issues.map((e) => e.code),
      ['bound-only'],
    );
  });

  test('function and action union arguments reject model literals', () async {
    final schema = S.union([S.string().boundOnly(), S.number()]);
    final value = _Value(S.any());
    final received = <Object?>[];
    final library = OpenUiLibrary(
      root: value,
      components: [value],
      functions: [
        FunctionSpec(
          'Secure',
          description: '',
          params: {'id': schema},
          fn: (args) {
            received.add(args['id']);
            return args['id'];
          },
        ),
      ],
      actions: [
        ActionSpec('Pay', description: '', params: {'id': schema}),
      ],
    );
    final session = OpenUiSession(library);
    addTearDown(session.dispose);
    session.update('root = Value(@Secure("forged"))', streaming: false);
    expect(received, isEmpty);
    expect(
      session.errors.map((e) => e.code),
      contains(OpenUiErrorCode.boundOnly),
    );
    session.update('root = Value(@Pay("forged"))', streaming: false);
    final events = <ActionEvent>[];
    await session.run(
      session.root!.props.action('value'),
      label: '',
      emit: events.add,
    );
    expect(events, isEmpty);
    expect(
      session.errors.map((e) => e.code),
      contains(OpenUiErrorCode.boundOnly),
    );
  });
}
