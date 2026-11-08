import '../spec/extend.dart';
import '../spec/library.dart';
import 'actions.dart';
import 'components.dart';
import 'demo_tools.dart';
import 'functions/colors.dart';
import 'functions/data.dart';
import 'functions/dates.dart';
import 'functions/lists.dart';
import 'functions/numbers.dart';
import 'functions/text.dart';
import 'prompt_options.dart';

/// The Open Intelligent UI library: about 55 components the model arranges
/// itself, 59 `@functions`, and `@CopyToClipboard`. Root is `Col`.
final OpenUiLibrary intelligentUi = OpenUiLibrary(
  root: IuiComponent.col,
  components: IuiComponent.values,
  groups: [
    ComponentGroup(
      'Layout',
      const [
        IuiComponent.col,
        IuiComponent.row,
        IuiComponent.box,
        IuiComponent.grid,
        IuiComponent.card,
        IuiComponent.carousel,
        IuiComponent.popover,
        IuiComponent.divider,
        IuiComponent.spacer,
      ],
      notes: const [
        '- gap and padding count 4px steps. Length is px or a CSS length like "50%". Radius is "sm", "md", "lg", "xl", "full" or px.',
        '- Color is "ink", "muted", "faint", "surface", "info", "success", "warning", "danger", "purple", "pink", "chart1" to "chart6", or a CSS color. As a background, status colors are soft tints.',
      ],
    ),
    const ComponentGroup('Text', [
      IuiComponent.title,
      IuiComponent.text,
      IuiComponent.caption,
      IuiComponent.label,
      IuiComponent.badge,
      IuiComponent.link,
      IuiComponent.list,
      IuiComponent.listItem,
      IuiComponent.markdown,
      IuiComponent.quote,
      IuiComponent.code,
      IuiComponent.math,
    ]),
    const ComponentGroup(
      'Inputs',
      [
        IuiComponent.button,
        IuiComponent.iconButton,
        IuiComponent.pressable,
        IuiComponent.input,
        IuiComponent.textArea,
        IuiComponent.select,
        IuiComponent.segmentedControl,
        IuiComponent.slider,
        IuiComponent.checkbox,
        IuiComponent.radioGroup,
        IuiComponent.datePicker,
        IuiComponent.timer,
        IuiComponent.form,
      ],
      notes: [
        "- An input's first argument is its value, usually a \$variable that other statements read.",
        '- Every input either changes something shown on the page, or sits in a Form whose submit Button sends a short first-person @ToAssistant ("Help me choose a bike"); the form values go with it. No dead inputs.',
      ],
    ),
    const ComponentGroup('Media and data', [
      IuiComponent.searchImage,
      IuiComponent.image,
      IuiComponent.icon,
      IuiComponent.table,
      IuiComponent.chart,
      IuiComponent.map,
      IuiComponent.mapMarker,
      IuiComponent.youTube,
    ]),
    const ComponentGroup('Play', [
      IuiComponent.flashcard,
      IuiComponent.celebration,
    ]),
    const ComponentGroup('Drawing', [
      IuiComponent.svg,
      IuiComponent.g,
      IuiComponent.circle,
      IuiComponent.ellipse,
      IuiComponent.rect,
      IuiComponent.line,
      IuiComponent.path,
      IuiComponent.polyline,
      IuiComponent.polygon,
      IuiComponent.svgText,
      IuiComponent.htmlView,
    ]),
  ],
  functions: [
    ...listFunctions,
    ...numberFunctions,
    ...textFunctions,
    ...colorFunctions,
    ...dateFunctions,
    ...dataFunctions,
  ],
  actions: [copyToClipboard],
);

/// The chat prompt: no tools, `$variables` and functions.
const PromptOptions chatPrompt = PromptOptions(
  bindings: true,
  additionalRules: chatRules,
  examples: chatExamples,
);

/// Components a renderer may leave out: they need a map, a web view or a TeX renderer.
const Set<IuiComponent> optionalIuiComponents = {
  IuiComponent.math,
  IuiComponent.map,
  IuiComponent.mapMarker,
  IuiComponent.youTube,
  IuiComponent.htmlView,
};

/// [intelligentUi] without [omit]. Map and MapMarker go together. With nothing to
/// omit this is [intelligentUi] itself.
OpenUiLibrary intelligentUiWithout(Set<IuiComponent> omit) {
  final drop = {...omit};
  if (drop.contains(IuiComponent.map) ||
      drop.contains(IuiComponent.mapMarker)) {
    drop
      ..add(IuiComponent.map)
      ..add(IuiComponent.mapMarker);
  }
  if (drop.isEmpty) return intelligentUi;
  return intelligentUi.extend(
    LibraryExtension(
      removeComponents: [
        for (final c in IuiComponent.values)
          if (drop.contains(c)) c.typeName,
      ],
    ),
  );
}

const _medium = 'Pick the medium that shows the idea: ';

List<String> _rulesFor(OpenUiLibrary library, List<String> rules) => [
  for (final r in rules)
    if (!r.startsWith(_medium))
      r
    else
      '$_medium${r.substring(_medium.length, r.length - 1).split('; ').where((c) => library.components.containsKey(c.split(' ').first)).join('; ')}.',
];

/// [chatPrompt] for [library]: the "Pick the medium" rule names only components
/// [library] has. For [intelligentUi] this is [chatPrompt] itself.
PromptOptions chatPromptFor(OpenUiLibrary library) =>
    identical(library, intelligentUi)
    ? chatPrompt
    : PromptOptions(
        bindings: true,
        additionalRules: _rulesFor(library, chatRules),
        examples: chatExamples,
      );

/// The dashboard prompt over [tools] (the demo data tools by default). Rules are
/// filtered as in [chatPromptFor].
PromptOptions dashboardPrompt({
  List<OpenUiTool>? tools,
  OpenUiLibrary? library,
}) => PromptOptions(
  bindings: true,
  tools: tools ?? demoTools(),
  additionalRules: [
    ..._rulesFor(library ?? intelligentUi, chatRules),
    ...dashboardRules,
  ],
  examples: chatExamples,
  toolExamples: dashboardExamples,
);
