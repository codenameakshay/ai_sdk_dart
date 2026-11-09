import 'package:ai_sdk_openui/ai_sdk_openui.dart';

/// The library behind `conformance/validator-spec.json`: a bound-only prop at
/// the top level and nested, an action slot, a typed bound-only money prop,
/// and a bound-only action param.
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
  };
}

final validatorLibrary = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  actions: [
    ActionSpec(
      'Pay',
      description: 'Pays an order.',
      params: {'orderId': S.string().boundOnly()},
    ),
  ],
  id: 'validator-conformance',
);
