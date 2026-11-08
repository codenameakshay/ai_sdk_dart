import '../spec/library.dart';
import '../spec/schema.dart';
import 'specs/chart.dart' as chart_specs;
import 'specs/controls.dart' as controls_specs;
import 'specs/extra.dart' as extra_specs;
import 'specs/html_view.dart' as html_view_specs;
import 'specs/layout.dart' as layout_specs;
import 'specs/map.dart' as map_specs;
import 'specs/media.dart' as media_specs;
import 'specs/svg.dart' as svg_specs;
import 'specs/table.dart' as table_specs;
import 'specs/text.dart' as text_specs;

/// The Open Intelligent UI components, in the reference library's order.
/// Builders switch over this enum, so a component without one does not
/// compile.
enum IuiComponent implements ComponentSpec {
  col('Col', layout_specs.col),
  row('Row', layout_specs.row),
  box('Box', layout_specs.box),
  grid('Grid', layout_specs.grid),
  card('Card', layout_specs.card),
  carousel('Carousel', extra_specs.carousel),
  popover('Popover', extra_specs.popover),
  divider('Divider', layout_specs.divider),
  spacer('Spacer', layout_specs.spacer),
  title('Title', text_specs.title),
  text('Text', text_specs.text),
  caption('Caption', text_specs.caption),
  label('Label', text_specs.label),
  badge('Badge', text_specs.badge),
  link('Link', text_specs.link),
  list('List', text_specs.list),
  listItem('ListItem', text_specs.listItem),
  markdown('Markdown', text_specs.markdown),
  quote('Quote', extra_specs.quote),
  code('Code', extra_specs.code),
  math('Math', extra_specs.math),
  button('Button', controls_specs.button),
  iconButton('IconButton', controls_specs.iconButton),
  pressable('Pressable', controls_specs.pressable),
  input('Input', controls_specs.input),
  textArea('TextArea', controls_specs.textArea),
  select('Select', controls_specs.select),
  segmentedControl('SegmentedControl', controls_specs.segmentedControl),
  slider('Slider', controls_specs.slider),
  checkbox('Checkbox', controls_specs.checkbox),
  radioGroup('RadioGroup', controls_specs.radioGroup),
  datePicker('DatePicker', controls_specs.datePicker),
  timer('Timer', controls_specs.timer),
  form('Form', layout_specs.form),
  searchImage('SearchImage', media_specs.searchImage),
  image('Image', media_specs.image),
  icon('Icon', media_specs.icon),
  table('Table', table_specs.table),
  chart('Chart', chart_specs.chart),
  map('Map', map_specs.map),
  mapMarker('MapMarker', map_specs.mapMarker),
  youTube('YouTube', extra_specs.youTube),
  flashcard('Flashcard', extra_specs.flashcard),
  celebration('Celebration', extra_specs.celebration),
  svg('Svg', svg_specs.svg),
  circle('Circle', svg_specs.circle),
  ellipse('Ellipse', svg_specs.ellipse),
  rect('Rect', svg_specs.rect),
  line('Line', svg_specs.line),
  path('Path', svg_specs.path),
  polyline('Polyline', svg_specs.polyline),
  polygon('Polygon', svg_specs.polygon),
  g('G', svg_specs.g),
  svgText('SvgText', svg_specs.svgText),
  htmlView('HtmlView', html_view_specs.htmlView);

  const IuiComponent(this.typeName, this._define);

  @override
  final String typeName;
  final ComponentDef Function() _define;

  static final Map<IuiComponent, ComponentDef> _defs = {};
  ComponentDef get _def => _defs.putIfAbsent(this, _define);

  @override
  String get description => _def.description;

  @override
  Map<String, Schema> get props => _def.props;
}
