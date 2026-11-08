import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  testWidgets('root text takes the theme ink and font', (tester) async {
    await pumpProgram(
      tester,
      'root = Row(["plain"])',
      brightness: Brightness.dark,
    );

    final style = DefaultTextStyle.of(tester.element(find.text('plain'))).style;
    expect(style.color, OpenUiTheme.dark.ink);
    expect(style.fontFamily, OpenUiTheme.dark.fontFamily);
  });

  group('OpenUiFormValidation', () {
    test('validateField reports a failing required rule', () {
      final validation = OpenUiFormValidation();
      addTearDown(validation.dispose);

      final passed = validation.validateField('a', '', [
        const ParsedRule('required'),
      ]);

      expect(passed, isFalse);
      expect(validation.errors['a'], 'This field is required');
      expect(validation.getFieldError('a'), 'This field is required');
    });

    test('validateForm unwraps a component value before validating', () {
      final validation = OpenUiFormValidation();
      addTearDown(validation.dispose);
      validation.registerField(
        'name',
        parseRules(['minLength:3']),
        () => {'value': 'x', 'componentType': 'Input'},
      );

      final passed = validation.validateForm();

      expect(passed, isFalse);
      expect(validation.errors['name'], 'Must be at least 3 characters');
    });

    test(
      'validateForm unwraps a stored {value} field without a component type',
      () {
        final validation = OpenUiFormValidation();
        addTearDown(validation.dispose);
        validation.registerField(
          'name',
          parseRules(['minLength:3']),
          () => {'value': 'x'},
        );
        expect(validation.validateForm(), isFalse);
        expect(validation.errors['name'], 'Must be at least 3 characters');
      },
    );

    test(
      'clearFieldError notifies once and ignores a clear of a clean field',
      () {
        final validation = OpenUiFormValidation();
        addTearDown(validation.dispose);
        validation.validateField('a', '', [const ParsedRule('required')]);
        var notified = 0;
        validation.addListener(() => notified++);

        validation.clearFieldError('a');
        validation.clearFieldError('a');

        expect(notified, 1);
        expect(validation.getFieldError('a'), isNull);
      },
    );
  });

  testWidgets('node.formValidation is set inside Form and null outside', (
    tester,
  ) async {
    OpenUiFormValidation? inside;
    var outsideSeen = false;
    OpenUiFormValidation? outside;
    Widget probe(BuildContext context, OpenUiNode node) {
      if (node.element.statementId == 'outer') {
        outside = node.formValidation;
        outsideSeen = true;
      } else {
        inside = node.formValidation;
      }
      return const SizedBox.shrink();
    }

    OpenUiBuilder? lookup(String name) =>
        name == 'Text' ? probe : intelligentUiBuilders(name);
    final session = OpenUiSession(intelligentUi)
      ..update(
        'root = Col([outer, Form([inner])])\n'
        'outer = Text("a")\n'
        'inner = Text("b")',
        streaming: false,
      );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OpenUiView(session: session, builders: lookup),
      ),
    );

    expect(outsideSeen, isTrue);
    expect(outside, isNull);
    expect(inside, isNotNull);
  });
}
