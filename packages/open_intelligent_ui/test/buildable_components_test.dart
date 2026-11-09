import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

void main() {
  test('intelligentUiFor requires a builder for the library root', () {
    expect(() => intelligentUiFor((_) => null), throwsArgumentError);
  });

  test(
    'intelligentUiFor returns intelligentUi when every component can build',
    () {
      Widget builder(BuildContext context, OpenUiNode node) => const SizedBox();

      expect(
        identical(intelligentUiFor((_) => builder), intelligentUi),
        isTrue,
      );
    },
  );

  test('core builder lookup advertises exactly its buildable components', () {
    final library = intelligentUiFor(openUiCoreBuilders);
    final buildableNames = IuiComponent.values
        .where((component) => openUiCoreBuilders(component.typeName) != null)
        .map((component) => component.typeName)
        .toSet();

    expect(library.components.keys, buildableNames);
  });

  test('Map and MapMarker are omitted together', () {
    OpenUiBuilder? onlyMap(String typeName) =>
        typeName == intelligentUi.rootName || typeName == 'Map'
        ? _builder
        : null;
    OpenUiBuilder? onlyMapMarker(String typeName) =>
        typeName == intelligentUi.rootName || typeName == 'MapMarker'
        ? _builder
        : null;

    for (final lookup in [onlyMap, onlyMapMarker]) {
      final library = intelligentUiFor(lookup);
      expect(library.components.containsKey('Map'), isFalse);
      expect(library.components.containsKey('MapMarker'), isFalse);
    }
  });

  test('intelligentUiFor advertises only components its lookup can build', () {
    OpenUiBuilder? onlyText(String typeName) =>
        typeName == intelligentUi.rootName || typeName == 'Text'
        ? openUiCoreBuilders(typeName)
        : null;

    final library = intelligentUiFor(onlyText);

    expect(library.components.keys, {intelligentUi.rootName, 'Text'});
  });
}

Widget _builder(BuildContext context, OpenUiNode node) => const SizedBox();
