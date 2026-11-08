import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _fit = S.oneOf(['cover', 'contain']);

ComponentDef searchImage() => ComponentDef(
  description:
      'A real photo the app finds for query; it needs no URL and no tool. Name the exact thing in 2 to 4 words: "Belém Tower Lisbon", "iPhone 17", "pastel de nata". Use one for every place, dish, product or thing with a look.',
  props: {
    'query': S.string(),
    'aspectRatio': S.number().optional(),
    'radius': radius.optional(),
    'fit': _fit.optional(),
  },
);

ComponentDef image() => ComponentDef(
  description:
      'Photo from a URL the user or a tool gave; if it fails, a photo is found for alt.',
  props: {
    'src': S.string(),
    'alt': S.string(),
    'aspectRatio': S.number().optional(),
    'radius': radius.optional(),
    'fit': _fit.optional(),
  },
);

ComponentDef icon() => ComponentDef(
  description: 'Lucide icon by name, e.g. "map-pin".',
  props: {
    'name': S.string(),
    'size': S.oneOf(['sm', 'md', 'lg', 'xl']).optional(),
    'color': color.optional(),
  },
);
