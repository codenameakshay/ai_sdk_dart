import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _align = S.oneOf(['start', 'center', 'end', 'stretch']);
final _justify = S.oneOf(['start', 'center', 'end', 'between']);

ComponentDef box() => ComponentDef(
  description:
      'Flex container, a column by default. radius also clips the content.',
  props: {
    'children': children.optional(),
    'direction': S.oneOf(['row', 'col']).optional(),
    'gap': S.number().optional(),
    'padding': S.number().optional(),
    'background': color.optional(),
    'radius': radius.optional(),
    'border': S.boolean().optional(),
    'width': length.optional(),
    'height': length.optional(),
    'flex': S.number().optional(),
    'align': _align.optional(),
    'justify': _justify.optional(),
    'wrap': S.boolean().optional(),
  },
);

ComponentDef row() => ComponentDef(
  description: 'Horizontal layout; items are vertically centered.',
  props: {
    'children': children,
    'gap': S.number().optional(),
    'align': _align.optional(),
    'justify': _justify.optional(),
    'wrap': S.boolean().optional(),
  },
);

ComponentDef col() => ComponentDef(
  description: 'Vertical layout. Without gap it spaces blocks like an article.',
  props: {
    'children': children,
    'gap': S.number().optional(),
    'align': _align.optional(),
  },
);

ComponentDef grid() => ComponentDef(
  description:
      'Equal columns (default 2). With minChildWidth (px), columns drop on narrow screens.',
  props: {
    'children': children,
    'columns': S.number().optional(),
    'minChildWidth': S.number().optional(),
    'gap': S.number().optional(),
  },
);

ComponentDef card() => ComponentDef(
  description: 'Panel with a border; soft is a filled panel for summaries.',
  props: {
    'children': children,
    'variant': S.oneOf(['outline', 'soft']).optional(),
    'padding': S.number().optional(),
    'gap': S.number().optional(),
  },
);

ComponentDef divider() => const ComponentDef(props: {});

ComponentDef spacer() => const ComponentDef(
  description: 'Fills the free space in a Row.',
  props: {},
);

ComponentDef form() => ComponentDef(
  description: 'Groups fields; their values go with any @ToAssistant inside.',
  props: {'children': children},
);
