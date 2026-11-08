import 'package:ai_sdk_openui/ai_sdk_openui.dart';

final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'amount': S.any().boundOnly().optional(),
    'action': actionSchema.optional(),
    'input': S.any().reactive().optional(),
  };
}

OpenUiLibrary boundLibrary({
  List<FunctionSpec> functions = const [],
  List<ActionSpec> actions = const [],
}) => OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: functions,
  actions: actions,
);

FunctionSpec secureFunction(List<Object?> received, {bool optional = false}) =>
    FunctionSpec(
      'Secure',
      description: '',
      params: {
        'id': optional
            ? S.string().boundOnly().optional()
            : S.string().boundOnly(),
      },
      fn: (args) {
        received.add(args['id']);
        return args['id'];
      },
    );
