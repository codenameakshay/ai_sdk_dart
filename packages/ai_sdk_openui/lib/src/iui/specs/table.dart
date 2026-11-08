import '../../spec/library.dart';
import '../../spec/schema.dart';

ComponentDef table() => ComponentDef(
  description:
      'Each row lists its cells in column order; a cell may be a component. Number columns align right.',
  props: {'columns': S.list(S.string()), 'rows': S.list(S.list(S.any()))},
);
