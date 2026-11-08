import '../../spec/library.dart';
import '../../spec/schema.dart';

ComponentDef htmlView() => ComponentDef(
  description:
      'Sandboxed HTML page with inline JS, for games and canvas. No network except script CDNs. Fits its content unless height is set.',
  props: {
    'html': S.string(),
    'height': S.number().optional(),
    'title': S.string().optional(),
  },
);
