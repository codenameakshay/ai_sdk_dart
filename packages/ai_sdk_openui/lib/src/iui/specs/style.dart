import '../../spec/schema.dart';

/// A child slot: any component, or a list of them (from `@Each`).
final Schema node = S.any().tag('Node');
final Schema children = S.list(node);

/// A theme token or a CSS color.
final Schema color = S.string().tag('Color');

/// A px number or a CSS length such as "50%".
final Schema length = S.union([S.number(), S.string()]).tag('Length');

final Schema radius = S
    .union([
      S.oneOf(['sm', 'md', 'lg', 'xl', 'full']),
      S.number(),
    ])
    .tag('Radius');

/// A choice: a string, or a value with a label.
final Schema option = S.union([
  S.string(),
  S.object({'value': S.string(), 'label': S.string()}),
]);
