import 'package:ai_sdk_openui/intelligent_ui.dart';

import '../view.dart';
import 'chart.dart';
import 'code_math.dart';
import 'controls.dart';
import 'extra.dart';
import 'html_view.dart';
import 'layout.dart';
import 'map.dart';
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

/// The Open Intelligent UI builders, one per [IuiComponent]. The switch is
/// exhaustive, so a component without a builder does not compile.
OpenUiBuilder? intelligentUiBuilders(String typeName) =>
    switch (_byName[typeName]) {
      null => null,
      final c => builderFor(c),
    };

OpenUiBuilder builderFor(IuiComponent component) => switch (component) {
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
  IuiComponent.math => buildMath,
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
  IuiComponent.map => buildMap,
  IuiComponent.mapMarker => buildMapMarker,
  IuiComponent.youTube => buildYouTube,
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
  IuiComponent.htmlView => buildHtmlView,
};
