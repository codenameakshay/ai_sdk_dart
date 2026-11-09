import 'package:ai_sdk_openui/ai_sdk_openui.dart'
    show LibraryExtension, OpenUiLibrary, OpenUiLibraryExtend;
import 'package:ai_sdk_openui/intelligent_ui.dart';

import '../view.dart';
import 'chart.dart';
import 'code.dart';
import 'controls.dart';
import 'extra.dart';
import 'layout.dart';
import 'markdown.dart';
import 'media.dart';
import 'play.dart';
import 'svg.dart';
import 'table.dart';
import 'text.dart';
import 'timer.dart';

final Map<String, IuiComponent> _byName = {
  for (final c in IuiComponent.values) c.typeName: c,
};

/// The core builders: every IuiComponent except optionalIuiComponents.
OpenUiBuilder? openUiCoreBuilders(String typeName) =>
    switch (_byName[typeName]) {
      null => null,
      final c => builderFor(c),
    };

/// [base] with [layers] on top; a later layer wins.
OpenUiBuilderLookup composeBuilders(
  Iterable<Map<String, OpenUiBuilder>> layers, {
  OpenUiBuilderLookup base = openUiCoreBuilders,
}) {
  final merged = <String, OpenUiBuilder>{for (final l in layers) ...l};
  return (typeName) => merged[typeName] ?? base(typeName);
}

/// [library] (default [intelligentUi]) with the [IuiComponent]s [builders]
/// can't build omitted; Map and MapMarker go together. With nothing to omit
/// this is [library] itself.
///
/// [builders] must build [library]'s root and every component it has that is
/// not an [IuiComponent], such as one a host added; otherwise this throws an
/// [ArgumentError].
OpenUiLibrary intelligentUiFor(
  OpenUiBuilderLookup builders, {
  OpenUiLibrary? library,
}) {
  final base = library ?? intelligentUi;
  if (builders(base.rootName) == null) {
    throw ArgumentError.value(
      builders,
      'builders',
      'must build the required ${base.rootName} root component',
    );
  }
  final unbuildable = [
    for (final name in base.components.keys)
      if (!_byName.containsKey(name) && builders(name) == null) name,
  ];
  if (unbuildable.isNotEmpty) {
    throw ArgumentError.value(
      builders,
      'builders',
      'has no builder for ${unbuildable.join(', ')}',
    );
  }
  final omit = {
    for (final c in IuiComponent.values)
      if (builders(c.typeName) == null) c,
  };
  if (omit.contains(IuiComponent.map) ||
      omit.contains(IuiComponent.mapMarker)) {
    omit.addAll([IuiComponent.map, IuiComponent.mapMarker]);
  }
  final remove = [
    for (final c in IuiComponent.values)
      if (omit.contains(c) && base.components.containsKey(c.typeName))
        c.typeName,
  ];
  return remove.isEmpty
      ? base
      : base.extend(LibraryExtension(removeComponents: remove));
}

OpenUiBuilder? builderFor(IuiComponent component) => switch (component) {
  IuiComponent.col => buildCol,
  IuiComponent.row => buildRow,
  IuiComponent.box => buildBox,
  IuiComponent.grid => buildGrid,
  IuiComponent.card => buildCard,
  IuiComponent.carousel => buildCarousel,
  IuiComponent.popover => buildPopover,
  IuiComponent.divider => buildDivider,
  IuiComponent.spacer => buildSpacer,
  IuiComponent.title => buildTitle,
  IuiComponent.text => buildText,
  IuiComponent.caption => buildCaption,
  IuiComponent.label => buildLabel,
  IuiComponent.badge => buildBadge,
  IuiComponent.link => buildLink,
  IuiComponent.list => buildList,
  IuiComponent.listItem => buildListItem,
  IuiComponent.markdown => buildMarkdown,
  IuiComponent.quote => buildQuote,
  IuiComponent.code => buildCode,
  IuiComponent.button => buildButton,
  IuiComponent.iconButton => buildIconButton,
  IuiComponent.pressable => buildPressable,
  IuiComponent.input => buildInput,
  IuiComponent.textArea => buildTextArea,
  IuiComponent.select => buildSelect,
  IuiComponent.segmentedControl => buildSegmentedControl,
  IuiComponent.slider => buildSlider,
  IuiComponent.checkbox => buildCheckbox,
  IuiComponent.radioGroup => buildRadioGroup,
  IuiComponent.datePicker => buildDatePicker,
  IuiComponent.timer => buildTimer,
  IuiComponent.form => buildForm,
  IuiComponent.searchImage => buildSearchImage,
  IuiComponent.image => buildImage,
  IuiComponent.icon => buildIcon,
  IuiComponent.table => buildTable,
  IuiComponent.chart => buildChart,
  IuiComponent.flashcard => buildFlashcard,
  IuiComponent.celebration => buildCelebration,
  IuiComponent.svg => buildSvg,
  IuiComponent.circle => buildCircle,
  IuiComponent.ellipse => buildEllipse,
  IuiComponent.rect => buildRect,
  IuiComponent.line => buildLine,
  IuiComponent.path => buildPath,
  IuiComponent.polyline => buildPolyline,
  IuiComponent.polygon => buildPolygon,
  IuiComponent.g => buildG,
  IuiComponent.svgText => buildSvgText,
  IuiComponent.math ||
  IuiComponent.map ||
  IuiComponent.mapMarker ||
  IuiComponent.youTube ||
  IuiComponent.htmlView => null,
};
