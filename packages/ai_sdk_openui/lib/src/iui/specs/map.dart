import '../../spec/library.dart';
import '../../spec/schema.dart';

ComponentDef map() => ComponentDef(
  description:
      'Street map fitted to its markers. route draws the road path in marker order; selected holds the clicked marker\'s label.',
  props: {
    'markers': S.list(S.ref('MapMarker')),
    'route': S.boolean().optional(),
    'selected': S.string().optional().reactive(),
    'height': S.number().optional(),
  },
);

ComponentDef mapMarker() => ComponentDef(
  description:
      'A place on a Map; icon is one emoji, else the pin shows its number.',
  props: {
    'label': S.string(),
    'lat': S.number(),
    'lng': S.number(),
    'category': S.string().optional(),
    'icon': S.string().optional(),
  },
);
