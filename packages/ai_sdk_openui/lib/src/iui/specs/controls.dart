import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _choice = S.union([
  S.string(),
  S.object({
    'value': S.string(),
    'label': S.string(),
    'description': S.string().optional(),
  }),
]);

ComponentDef button() => ComponentDef(
  description: 'icon is a lucide name.',
  props: {
    'label': S.string(),
    'action': actionSchema.optional(),
    'variant': S.oneOf(['solid', 'outline', 'soft', 'ghost']).optional(),
    'color': S.oneOf(['primary', 'danger', 'success']).optional(),
    'size': S.oneOf(['sm', 'md', 'lg']).optional(),
    'icon': S.string().optional(),
    'disabled': S.boolean().optional(),
    'block': S.boolean().optional(),
  },
);

ComponentDef iconButton() => ComponentDef(
  description: 'Round icon-only button; label is read aloud.',
  props: {
    'icon': S.string(),
    'action': actionSchema.optional(),
    'label': S.string().optional(),
    'variant': S.oneOf(['outline', 'ghost', 'solid']).optional(),
  },
);

ComponentDef pressable() => ComponentDef(
  description: 'Makes any content clickable, such as a tile or a swatch.',
  props: {
    'children': children,
    'action': actionSchema.optional(),
    'selected': S.boolean().optional(),
    'padding': S.number().optional(),
    'background': color.optional(),
    'radius': radius.optional(),
  },
);

ComponentDef input() => ComponentDef(
  description: 'Text or number field; a number field stores numbers.',
  props: {
    'value': S.union([S.string(), S.number()]).reactive(),
    'label': S.string().optional(),
    'type': S.oneOf(['text', 'number']).optional(),
    'placeholder': S.string().optional(),
  },
);

ComponentDef textArea() => ComponentDef(
  props: {
    'value': S.string().reactive(),
    'label': S.string().optional(),
    'placeholder': S.string().optional(),
    'rows': S.number().optional(),
  },
);

ComponentDef select() => ComponentDef(
  description: 'Dropdown, for long option lists.',
  props: {
    'value': S.string().reactive(),
    'options': S.list(option),
    'label': S.string().optional(),
    'placeholder': S.string().optional(),
  },
);

ComponentDef segmentedControl() => ComponentDef(
  description: '2 to 4 short choices in a row.',
  props: {
    'value': S.string().reactive(),
    'options': S.list(option),
    'block': S.boolean().optional(),
  },
);

ComponentDef slider() => ComponentDef(
  description:
      'Shows label and value; unit like "%" or "\$" formats the value.',
  props: {
    'value': S.number().reactive(),
    'min': S.number(),
    'max': S.number(),
    'step': S.number().optional(),
    'label': S.string().optional(),
    'unit': S.string().optional(),
    'marks': S
        .list(S.object({'value': S.number(), 'label': S.string()}))
        .optional(),
  },
);

ComponentDef checkbox() => ComponentDef(
  description: 'lineThrough strikes the label when checked, for to-do lists.',
  props: {
    'checked': S.boolean().reactive(),
    'label': S.string(),
    'lineThrough': S.boolean().optional(),
  },
);

ComponentDef radioGroup() => ComponentDef(
  description:
      'pills for short choices; cards for choices that need a description line.',
  props: {
    'value': S.string().reactive(),
    'options': S.list(_choice),
    'label': S.string().optional(),
    'variant': S.oneOf(['list', 'pills', 'cards']).optional(),
  },
);

ComponentDef datePicker() => ComponentDef(
  description: 'Dates are "YYYY-MM-DD".',
  props: {
    'value': S.string().reactive(),
    'label': S.string().optional(),
    'min': S.string().optional(),
    'max': S.string().optional(),
  },
);

ComponentDef timer() => ComponentDef(
  description:
      'Countdown with start, pause and reset. It counts the bound seconds down to 0, so other statements can react, e.g. \$left == 0.',
  props: {'seconds': S.number().reactive(), 'label': S.string().optional()},
);
