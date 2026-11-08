import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _BoundActionOut implements ComponentSpec {
  const _BoundActionOut(this.action);
  final Schema action;
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {'action': action.boundOnly().optional()};
}

void main() {
  final cases = [
    (
      name: 'ActionExpression',
      schema: actionSchema,
      expression: '@Pay("forged")',
      value: <String, Object?>{'type': 'open_url', 'url': 'https://host.test'},
    ),
    (
      name: 'action ref',
      schema: S.actionRef('Pay', {'id': S.string()}),
      expression: '@Pay("forged")',
      value: <String, Object?>{
        'type': 'Pay',
        'params': {'id': 'host'},
      },
    ),
    (
      name: 'built-in step ref',
      schema: Steps.openUrl,
      expression: '{type: "open_url", url: "https://forged.test"}',
      value: <String, Object?>{'type': 'open_url', 'url': 'https://host.test'},
    ),
  ];
  for (final c in cases) {
    test('bound-only sibling survives inlining ${c.name}', () async {
      final out = _BoundActionOut(c.schema);
      final library = OpenUiLibrary(
        root: out,
        components: [out],
        actions: [
          ActionSpec('Pay', description: '', params: {'id': S.string()}),
        ],
      );
      final s = OpenUiSession(
        library,
        records: [BoundRecord('action', c.value)],
      );
      addTearDown(s.dispose);
      final invalid = 'root = Out(${c.expression})';
      expect(library.parse(invalid, bound: {r'$action'}).errors, hasLength(1));
      s.update(invalid, streaming: false);
      expect(s.errors.single.code, OpenUiErrorCode.boundOnly);
      expect(s.root!.props.has('action'), isFalse);
      const valid = r'root = Out($action)';
      expect(library.parse(valid, bound: {r'$action'}).errors, isEmpty);
      s.update(valid, streaming: false);
      expect(s.errors, isEmpty);
      expect(s.root!.props['action'], c.value);
    });
  }
}
