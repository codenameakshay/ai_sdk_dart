import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

final class _Data implements ComponentSpec {
  const _Data();
  @override
  String get typeName => 'Data';
  @override
  String get description => 'Displays passive data without an action slot.';
  @override
  Map<String, Schema> get props => {'value': S.any()};
}

void main() {
  for (final (action, wire, payload, expectedParams) in [
    (
      'OpenUrl',
      ActionEvent.openUrl,
      'url: "https://example.com"',
      <String, Object?>{'url': 'https://example.com'},
    ),
    (
      'ToAssistant',
      ActionEvent.continueConversation,
      'message: "Help"',
      <String, Object?>{},
    ),
  ]) {
    final map = '{type: "$wire", $payload}';
    for (final (name, program) in [
      ('direct action', 'root = Col([Button("Go", $map)])'),
      ('Action step', 'root = Col([Button("Go", Action([$map]))])'),
      (
        'state initializer',
        '\$action = $map\n'
            r'root = Col([Button("Go", $action)])',
      ),
    ]) {
      test('legacy $action $name obeys its action allow list', () async {
        final session = OpenUiSession(intelligentUi)
          ..update(program, streaming: false);
        addTearDown(session.dispose);
        final events = <ActionEvent>[];
        await session.run(
          session.root!.props
              .elements('children')
              .single
              .props
              .action('action'),
          label: 'Go',
          emit: events.add,
        );
        expect(events.single.type, wire);
        expect(events.single.params, expectedParams);
        if (action == 'ToAssistant') {
          expect(
            events.single.humanFriendlyMessage,
            name == 'Action step' ? 'Help' : 'Go',
          );
        }
        final report = intelligentUi.validate(
          program,
          policy: const ValidationPolicy(allowedActions: {}),
        );
        expect(report.ok, isFalse);
        expect(
          report.issues.map((i) => i.code),
          contains('action-not-allowed'),
        );
      });

      test('legacy $action $name is accepted when explicitly allowed', () {
        final report = intelligentUi.validate(
          program,
          policy: ValidationPolicy(allowedActions: {action}),
        );
        expect(report.ok, isTrue);
        expect(report.issues, isEmpty);
      });
    }

    test('passive $action-shaped data is not treated as a call', () {
      final library = OpenUiLibrary(
        root: const _Data(),
        components: const [_Data()],
      );
      final report = library.validate(
        'root = Data($map)',
        policy: const ValidationPolicy(allowedActions: {}),
      );
      expect(report.ok, isTrue);
      expect(report.issues, isEmpty);
    });
  }
}
