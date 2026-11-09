import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

final class _Fr extends OpenUiLocalizations {
  const _Fr();

  @override
  String get start => 'Démarrer';

  @override
  String get fieldRequired => 'Champ obligatoire';

  @override
  String atLeastCharacters(String limit) => 'Au moins $limit caractères';
}

const _m8Literals = [
  'Loading data',
  'Copy code',
  'Tap to flip',
  'Previous',
  'Next',
  'Choose…',
  'Interactive view',
  'YouTube video',
  'Filter places',
  'All places',
  'Zoom in',
  'Zoom out',
  'About this map',
  'Show every place',
  'Start',
  'Pause',
  'Resume',
  'Reset',
  'Done',
  'Copied',
];

Directory _srcDir(String package) {
  final candidates = [
    Directory('../$package/lib/src'),
    Directory('packages/$package/lib/src'),
  ];
  return candidates.firstWhere((d) => d.existsSync());
}

void main() {
  testWidgets('English by default', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text("n=" + q.n)])\nq = Query("slow", {}, {n: 0})',
      tools: [
        OpenUiTool(name: 'slow', call: (_) => Completer<Object?>().future),
      ],
    );
    await tester.pump();
    expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
  });

  testWidgets('a registered delegate translates', (tester) async {
    final session = OpenUiSession(intelligentUi)
      ..update('root = Timer(60)', streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('fr'),
            delegates: [
              OpenUiLocalizationsDelegate({'fr': const _Fr()}),
            ],
            child: Scaffold(
              body: OpenUiScope(
                services: OpenUiServices(mapTiles: null),
                child: OpenUiView(
                  session: session,
                  builders: intelligentUiBuilders,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Démarrer'), findsOneWidget);
    expect(find.text('Start'), findsNothing);
  });

  testWidgets('form validation errors come from the registered delegate', (
    tester,
  ) async {
    OpenUiFormValidation? validation;
    OpenUiBuilder? lookup(String name) => name == 'Text'
        ? (context, node) {
            validation = node.formValidation;
            return const SizedBox.shrink();
          }
        : intelligentUiBuilders(name);
    final session = OpenUiSession(intelligentUi)
      ..update('root = Form([name])\nname = Text("a")', streaming: false);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('fr'),
            delegates: [
              OpenUiLocalizationsDelegate({'fr': const _Fr()}),
            ],
            child: OpenUiView(session: session, builders: lookup),
          ),
        ),
      ),
    );

    expect(
      validation!.validateField('name', '', [const ParsedRule('required')]),
      isFalse,
    );
    expect(validation!.getFieldError('name'), 'Champ obligatoire');

    validation!.registerField('nick', [
      const ParsedRule('minLength', 3),
    ], () => {'value': 'ab'});
    expect(validation!.validateForm(), isFalse);
    expect(validation!.getFieldError('nick'), 'Au moins 3 caractères');
  });

  test('default validation messages are English', () {
    final validation = OpenUiFormValidation();
    addTearDown(validation.dispose);
    validation.validateField('name', '', [const ParsedRule('required')]);
    expect(validation.getFieldError('name'), 'This field is required');
  });

  test('no hard-coded English left', () {
    final offenders = <String>[];
    for (final package in const [
      'open_intelligent_ui_core',
      'open_intelligent_ui_maps',
      'open_intelligent_ui_web',
      'open_intelligent_ui_chat',
    ]) {
      final files = _srcDir(package)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('localizations.dart'));
      for (final file in files) {
        final source = file.readAsStringSync();
        for (final literal in _m8Literals) {
          if (source.contains("'$literal'")) {
            offenders.add('${file.path}: \'$literal\'');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
