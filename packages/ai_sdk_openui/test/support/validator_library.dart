import 'package:ai_sdk_openui/ai_sdk_openui.dart';

/// The library behind `conformance/validator-spec.json`: a bound-only prop at
/// the top level and nested, an action slot, a typed bound-only money prop,
/// a bound-only action param, and a restricted action slot (Chip).
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Shows a value, an amount and an action.';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'amount': S.any().boundOnly().optional(),
    'action': actionSchema.optional(),
    'payment': S.object({'amount': S.any().boundOnly()}).optional(),
    'money': S
        .object({'minor': S.number(), 'currency': S.string()})
        .boundOnly()
        .optional(),
    'choice': S.union([S.string().boundOnly(), S.number()]).optional(),
  };
}

/// A component whose action slot takes only `@ToAssistant` and `@Set`.
final class _Chip implements ComponentSpec {
  const _Chip();
  @override
  String get typeName => 'Chip';
  @override
  String get description => 'A chip with a restricted action.';
  @override
  Map<String, Schema> get props => {
    'label': S.string(),
    'action': S.union([Steps.toAssistant, Steps.set]).optional(),
  };
}

final validatorLibrary = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out(), _Chip()],
  actions: [
    ActionSpec(
      'Pay',
      description: 'Pays an order.',
      params: {'orderId': S.string().boundOnly()},
    ),
  ],
  id: 'validator-conformance',
);
