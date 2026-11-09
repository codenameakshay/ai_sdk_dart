import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/components.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

/// Pumps [program] through core's own [OpenUiView] and builders, with no
/// umbrella package in the import graph.
Future<void> _pump(
  WidgetTester tester,
  String program, {
  OpenUiServices? scope,
  OpenUiServices fallback = const OpenUiServices(),
}) async {
  final session = OpenUiSession(intelligentUi)
    ..update(program, streaming: false);
  addTearDown(session.dispose);
  Widget child = OpenUiView(
    session: session,
    builders: openUiCoreBuilders,
    fallbackServices: fallback,
  );
  if (scope != null) child = OpenUiScope(services: scope, child: child);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The left padding of the Badge drawn with [text].
double _badgeLeftPadding(WidgetTester tester, String text) {
  final boxes = tester
      .widgetList<Container>(
        find.ancestor(of: find.text(text), matching: find.byType(Container)),
      )
      .where(
        (c) =>
            c.padding != null &&
            c.decoration is BoxDecoration &&
            (c.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(999),
      )
      .toList();
  expect(boxes, hasLength(1), reason: text);
  return boxes.single.padding!.resolve(TextDirection.ltr).left;
}

void main() {
  test('core builders leave out the optional components', () {
    expect(openUiCoreBuilders('Map'), isNull);
    expect(openUiCoreBuilders('Card'), isNotNull);
    final lean = intelligentUiFor(openUiCoreBuilders);
    expect(lean.components.containsKey('Card'), isTrue);
    for (final name in const [
      'Math',
      'Map',
      'MapMarker',
      'YouTube',
      'HtmlView',
    ]) {
      expect(lean.components.containsKey(name), isFalse, reason: name);
    }
  });

  test('composeBuilders: a later layer wins, then the base', () {
    Widget lower(BuildContext context, OpenUiNode node) => const SizedBox();
    Widget upper(BuildContext context, OpenUiNode node) => const SizedBox();
    Widget text(BuildContext context, OpenUiNode node) => const SizedBox();
    final lookup = composeBuilders([
      {'Card': lower},
      {'Card': upper},
    ], base: (name) => name == 'Text' ? text : null);
    expect(lookup('Card'), same(upper));
    expect(lookup('Text'), same(text));
    expect(lookup('Map'), isNull);
  });

  test('the core pubspec has no heavy dependency', () {
    final pubspec = File('$_core/pubspec.yaml').readAsLinesSync();
    final start = pubspec.indexOf('dependencies:');
    expect(start, greaterThanOrEqualTo(0));
    final deps = <String>{};
    for (var i = start + 1; i < pubspec.length; i++) {
      final line = pubspec[i];
      if (line.isNotEmpty && !line.startsWith(' ')) break;
      final match = RegExp(r'^  ([a-z_]+):').firstMatch(line);
      if (match != null) deps.add(match[1]!);
    }
    expect(deps, containsAll(['flutter', 'ai_sdk_openui', 'intl']));
    expect(
      deps.intersection({
        'flutter_map',
        'latlong2',
        'flutter_math_fork',
        'webview_flutter',
        'http',
        'url_launcher',
        'web',
        'ai_sdk_dart',
        'ai_sdk_flutter_ui',
      }),
      isEmpty,
    );
    expect(pubspec.join('\n'), isNot(contains('fonts:')));
    final barrel = File(
      '$_core/lib/open_intelligent_ui_core.dart',
    ).readAsStringSync();
    expect(barrel.toLowerCase(), isNot(contains('lucide')));
  });

  test('lucide data is reachable only through lucide.dart', () {
    final importers = <String>[];
    final lib = Directory('$_core/lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity.readAsLinesSync().where(
        (line) => !line.trimLeft().startsWith('//'),
      );
      final imports = RegExp(
        r'''^\s*(import|export)\s+['"][^'"]*lucide_icons\.dart['"]''',
      );
      if (code.any(imports.hasMatch)) importers.add(entity.path);
    }
    expect(importers, ['$_core/lib/src/components/lucide_resolver.dart']);
  });

  testWidgets('core draws built-in glyphs and nothing for other names', (
    tester,
  ) async {
    await _pump(tester, 'root = Col([Icon("check"), Icon("map-pin")])');
    expect(find.byType(OutlineGlyph), findsOneWidget);

    await _pump(
      tester,
      'root = Col([Badge("x", null, "check"), Badge("y", null, "map-pin")])',
    );
    expect(_badgeLeftPadding(tester, 'x'), 8);
    expect(_badgeLeftPadding(tester, 'y'), 10);
  });

  testWidgets('a resolver gets kebab-case names and wins over built-ins', (
    tester,
  ) async {
    await _pump(
      tester,
      'root = Col([Icon("MapPin"), Icon("check")])',
      scope: OpenUiServices(
        icons: (name, size, color, width) => Text('R:$name'),
      ),
    );
    expect(find.text('R:map-pin'), findsOneWidget);
    expect(find.text('R:check'), findsOneWidget);
  });

  testWidgets('fallbackServices fill what the scope leaves unset', (
    tester,
  ) async {
    const program = 'root = Col([Link("Docs", "https://a.b")])';

    final fallbackOpened = <Uri>[];
    await _pump(
      tester,
      program,
      scope: OpenUiServices(copyText: (text) async {}),
      fallback: OpenUiServices(
        openUrl: (url) async {
          fallbackOpened.add(url);
        },
      ),
    );
    await tester.tap(find.textContaining('Docs'));
    await tester.pump();
    expect(fallbackOpened, [Uri.parse('https://a.b')]);

    final scopeOpened = <Uri>[];
    final fallbackAfterScope = <Uri>[];
    await _pump(
      tester,
      program,
      scope: OpenUiServices(
        openUrl: (url) async {
          scopeOpened.add(url);
        },
      ),
      fallback: OpenUiServices(
        openUrl: (url) async {
          fallbackAfterScope.add(url);
        },
      ),
    );
    await tester.tap(find.textContaining('Docs'));
    await tester.pump();
    expect(scopeOpened, [Uri.parse('https://a.b')]);
    expect(fallbackAfterScope, isEmpty);
  });

  testWidgets('OpenUiScope travels into routes', (tester) async {
    final services = OpenUiServices(copyText: (text) async {});
    late CapturedThemes captured;
    await tester.pumpWidget(
      MaterialApp(
        home: OpenUiScope(
          services: services,
          child: Builder(
            builder: (context) {
              captured = InheritedTheme.capture(from: context, to: null);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    OpenUiServices? seen;
    await tester.pumpWidget(
      captured.wrap(
        Builder(
          builder: (context) {
            seen = OpenUiScope.servicesOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, same(services));
  });

  test('the default font family is unchanged', () {
    expect(OpenUiTheme.light.fontFamily, 'packages/open_intelligent_ui/Inter');
  });
}

/// The core package directory: `flutter test` runs from this package or, in
/// `make test`, from the repo root.
final String _core = [
  '../open_intelligent_ui_core',
  'packages/open_intelligent_ui_core',
].firstWhere((path) => Directory(path).existsSync());
