import '../../spec/library.dart';
import '../../spec/schema.dart';

ComponentDef chart() => ComponentDef(
  description:
      'Rows of data; x is the category key (a number key for scatter), series the value keys (default: every number key). percent values are like 45; currency is a code like "EUR".',
  props: {
    'type': S.oneOf(['bar', 'line', 'area', 'pie', 'donut', 'scatter']),
    'data': S.list(S.record(S.string(), S.union([S.string(), S.number()]))),
    'x': S.string().optional(),
    'series': S.list(S.string()).optional(),
    'format': S.oneOf(['number', 'currency', 'percent']).optional(),
    'currency': S.string().optional(),
    'stacked': S.boolean().optional(),
    'height': S.number().optional(),
  },
);
