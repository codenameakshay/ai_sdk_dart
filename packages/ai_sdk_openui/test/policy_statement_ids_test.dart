import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

void main() {
  test('state initializer parse errors identify the state statement', () {
    final report = intelligentUi.validate(
      r'$bad = Title()'
      '\nroot = Col([])',
    );
    final issue = report.issues.singleWhere(
      (i) => i.code == 'missing-required',
    );
    expect(issue.statementId, r'$bad');
  });
}
