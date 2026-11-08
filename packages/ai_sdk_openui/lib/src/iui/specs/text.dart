import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _richText = S.union([S.string(), children]);

ComponentDef title() => ComponentDef(
  description:
      'Heading; md for a card title, lg for a section, 2xl for a big number.',
  props: {
    'text': S.string(),
    'size': S.oneOf(['sm', 'md', 'lg', 'xl', '2xl', '3xl']).optional(),
    'color': color.optional(),
  },
);

ComponentDef text() => ComponentDef(
  description:
      'Paragraph; supports **bold**, *italic*, `code` and [links](https://…). text may be a list mixing strings and inline components: [Icon("clock", "sm"), " 25 min · ", Badge("Easy")].',
  props: {
    'text': _richText,
    'size': S.oneOf(['xs', 'sm', 'md', 'lg']).optional(),
    'color': color.optional(),
    'weight': S.oneOf(['normal', 'medium', 'semibold']).optional(),
    'italic': S.boolean().optional(),
    'lineThrough': S.boolean().optional(),
    'tabularNums': S.boolean().optional(),
    'maxLines': S.number().optional(),
  },
);

ComponentDef caption() => ComponentDef(
  description: 'Small secondary text.',
  props: {'text': S.string(), 'color': color.optional()},
);

ComponentDef label() => ComponentDef(
  description: 'Field or group label.',
  props: {'text': S.string()},
);

ComponentDef badge() => ComponentDef(
  description: 'Pill tag; icon is an optional leading lucide name.',
  props: {
    'text': S.string(),
    'color': S.oneOf([
      'neutral',
      'info',
      'success',
      'warning',
      'danger',
      'purple',
      'pink',
    ]).optional(),
    'icon': S.string().optional(),
  },
);

ComponentDef link() => ComponentDef(
  description: 'Opens an http(s) URL in a new tab.',
  props: {'text': S.string(), 'url': S.string()},
);

ComponentDef list() => ComponentDef(
  description: 'timeline joins the markers with a line.',
  props: {
    'items': S.list(S.union([S.string(), S.ref('ListItem')])),
    'marker': S.oneOf(['bullet', 'number', 'none']).optional(),
    'timeline': S.boolean().optional(),
  },
);

ComponentDef listItem() => ComponentDef(
  description: 'marker replaces the bullet or number, e.g. a time or an emoji.',
  props: {
    'title': S.string(),
    'description': S.string().optional(),
    'marker': S.string().optional(),
    'children': children.optional(),
  },
);

ComponentDef markdown() => ComponentDef(
  description: 'Prose with headings, lists, quotes, code and tables.',
  props: {'text': S.string()},
);
