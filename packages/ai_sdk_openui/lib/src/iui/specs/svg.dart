import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'style.dart';

final _paint = <String, Schema>{
  'fill': color.optional(),
  'stroke': color.optional(),
  'strokeWidth': S.number().optional(),
  'opacity': S.number().optional(),
};

ComponentDef svg() => ComponentDef(
  description:
      'A drawing for steps, parts, mechanisms, diagrams and layouts. Scales to its width; its shapes take expressions, so state can move them.',
  props: {
    'children': children,
    'viewBox': S.string(),
    'width': length.optional(),
    'height': length.optional(),
  },
);

ComponentDef circle() => ComponentDef(
  props: {'cx': S.number(), 'cy': S.number(), 'r': S.number(), ..._paint},
);

ComponentDef ellipse() => ComponentDef(
  props: {
    'cx': S.number(),
    'cy': S.number(),
    'rx': S.number(),
    'ry': S.number(),
    ..._paint,
  },
);

ComponentDef rect() => ComponentDef(
  props: {
    'x': S.number(),
    'y': S.number(),
    'width': S.number(),
    'height': S.number(),
    ..._paint,
    'rx': S.number().optional(),
  },
);

ComponentDef line() => ComponentDef(
  props: {
    'x1': S.number(),
    'y1': S.number(),
    'x2': S.number(),
    'y2': S.number(),
    'stroke': color.optional(),
    'strokeWidth': S.number().optional(),
    'opacity': S.number().optional(),
  },
);

ComponentDef path() => ComponentDef(props: {'d': S.string(), ..._paint});

ComponentDef polyline() => ComponentDef(
  description: 'points like "0,0 10,5 20,0".',
  props: {
    'points': S.string(),
    'stroke': color.optional(),
    'strokeWidth': S.number().optional(),
    'fill': color.optional(),
    'opacity': S.number().optional(),
  },
);

ComponentDef polygon() =>
    ComponentDef(props: {'points': S.string(), ..._paint});

ComponentDef g() => ComponentDef(
  description: 'Group; transform like "rotate(30 50 50)" or "translate(10 0)".',
  props: {
    'children': children,
    'transform': S.string().optional(),
    'opacity': S.number().optional(),
  },
);

ComponentDef svgText() => ComponentDef(
  props: {
    'text': S.string(),
    'x': S.number(),
    'y': S.number(),
    'size': S.number().optional(),
    'fill': color.optional(),
    'anchor': S.oneOf(['start', 'middle', 'end']).optional(),
    'weight': S.oneOf(['normal', 'medium', 'semibold']).optional(),
  },
);
