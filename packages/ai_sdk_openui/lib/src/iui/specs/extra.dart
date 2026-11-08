import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _slot = S.union([S.string(), children]);

ComponentDef carousel() => ComponentDef(
  description:
      'Horizontal row that scrolls and snaps, each child an item itemWidth px wide (default 240): photos, cards, options, days.',
  props: {
    'children': children,
    'itemWidth': S.number().optional(),
    'gap': S.number().optional(),
  },
);

ComponentDef popover() => ComponentDef(
  description:
      'Shows content in a small panel when the trigger is clicked: a definition, a source, details behind an Icon("info", "sm").',
  props: {'trigger': _slot, 'content': _slot},
);

ComponentDef quote() => ComponentDef(
  description:
      'A quotation or a callout with a side rule; cite names the source.',
  props: {'text': S.string(), 'cite': S.string().optional()},
);

ComponentDef code() => ComponentDef(
  description: 'Code block with a copy button.',
  props: {'code': S.string(), 'language': S.string().optional()},
);

ComponentDef math() => ComponentDef(
  description:
      'LaTeX formula, e.g. Math("E = mc^2"); inline true to sit in a Text list.',
  props: {'tex': S.string(), 'inline': S.boolean().optional()},
);

ComponentDef youTube() => ComponentDef(
  description:
      'Embedded YouTube video by id or URL. Only a video you know exists.',
  props: {'video': S.string(), 'title': S.string().optional()},
);

ComponentDef flashcard() => ComponentDef(
  description:
      'Card that flips between front and back when tapped. Put several in a Carousel or Grid.',
  props: {'front': _slot, 'back': _slot, 'hint': S.string().optional()},
);

ComponentDef celebration() => ComponentDef(
  description:
      'Bursts confetti when its condition turns true, e.g. Celebration(\$score == 5) at the end of a quiz.',
  props: {'when': S.boolean()},
);
