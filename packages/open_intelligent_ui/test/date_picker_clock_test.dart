import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  testWidgets('DatePicker opens on Impure\'s today', (tester) async {
    Impure.now = () => DateTime.utc(2030, 5, 17, 12);
    Impure.useUtc();
    addTearDown(Impure.reset);

    await pumpProgram(tester, 'root = DatePicker("")');
    await tester.tap(find.bySemanticsLabel('Date'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.initialDate, DateTime(2030, 5, 17));
  });

  testWidgets('DatePicker opens on its session\'s today in its zone', (
    tester,
  ) async {
    final session = OpenUiSession(
      intelligentUi,
      clock: () => DateTime.utc(2030, 5, 17, 20),
      timeZone: OpenUiTimeZone.fixed(const Duration(hours: 5, minutes: 30)),
    )..update('root = DatePicker("")', streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OpenUiView(session: session, builders: intelligentUiBuilders),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Date'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.initialDate, DateTime(2030, 5, 18));
  });
}
