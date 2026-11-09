import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  String get description => '';
}

final _copy = ActionSpec(
  'Copy',
  description: 'Copy text',
  params: {'text': S.string()},
);

final _library = OpenUiLibrary(
  root: _Spec('Col', {'children': S.list(S.any())}),
  components: [
    _Spec('Col', {'children': S.list(S.any())}),
    _Spec('Chip', {
      'label': S.string(),
      'action': Steps.toAssistant.optional(),
    }),
    _Spec('Editor', {
      'label': S.string(),
      'action': S
          .union([Steps.set, Steps.reset, _copy.ref])
          .nullable()
          .optional(),
    }),
    _Spec('Any', {'label': S.string(), 'action': actionSchema.optional()}),
  ],
  actions: [_copy],
);

List<(String, String?, String?)> _issues(String program) => [
  for (final i in _library.validate('\$a = 0\nroot = Col([$program])').issues)
    (i.code, i.component, i.path),
];

void main() {
  test('a step outside its slot is rejected', () {
    expect(_issues(r'Chip("x", @Set($a, 1))'), [
      ('type-mismatch', 'Chip', '/action'),
    ]);
    expect(
      _library
          .validate('\$a = 0\nroot = Col([Chip("x", @Set(\$a, 1))])')
          .issues
          .single
          .message,
      'field "/action" expects @ToAssistant but got @Set',
    );
    expect(_issues('Chip("x", @ToAssistant("go"))'), isEmpty);
  });

  test('Steps.set and Steps.reset admit those steps', () {
    expect(_issues(r'Editor("x", @Set($a, 1))'), isEmpty);
    expect(_issues(r'Editor("x", @Reset($a))'), isEmpty);
    expect(_issues('Editor("x", @Copy("t"))'), isEmpty);
    expect(_issues('Editor("x", null)'), isEmpty);
    expect(_issues('Editor("x", @OpenUrl("https://a.b"))'), [
      ('type-mismatch', 'Editor', '/action'),
    ]);
  });

  test('every step in Action([...]) and each ternary branch is checked', () {
    expect(_issues(r'Editor("x", Action([@Set($a, 1), @Reset($a)]))'), isEmpty);
    expect(_issues(r'Chip("x", Action([@ToAssistant("go"), @Reset($a)]))'), [
      ('type-mismatch', 'Chip', '/action'),
    ]);
    expect(_issues(r'Chip("x", $a > 0 ? @ToAssistant("go") : @Set($a, 1))'), [
      ('type-mismatch', 'Chip', '/action'),
    ]);
  });

  test('an unrestricted action slot takes any step', () {
    expect(
      _issues(r'Any("x", Action([@Set($a, 1), @OpenUrl("https://a.b")]))'),
      isEmpty,
    );
  });

  test('a session does not run a step outside its slot', () {
    final s = OpenUiSession(_library)
      ..update(
        '\$a = 0\nroot = Col([Chip("x", @Set(\$a, 1))])',
        streaming: false,
      );
    addTearDown(s.dispose);
    final chip = s.root!.props.elements('children').single;
    expect(chip.props.has('action'), isFalse);
  });

  test('the spec emits the set and reset step shapes', () {
    final defs = _library.toJsonSchema()[r'$defs'] as Map<String, Object?>;
    expect((defs['Set'] as Map)['properties'], {
      'type': {'type': 'string', 'const': 'set'},
      'target': {'type': 'string'},
    });
    expect((defs['Reset'] as Map)['properties'], {
      'type': {'type': 'string', 'const': 'reset'},
      'targets': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    });
  });
}
