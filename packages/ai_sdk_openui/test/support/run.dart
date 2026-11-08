import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/iui/actions.dart';
import 'package:ai_sdk_openui/src/iui/functions/colors.dart';
import 'package:ai_sdk_openui/src/iui/functions/data.dart';
import 'package:ai_sdk_openui/src/iui/functions/dates.dart';
import 'package:ai_sdk_openui/src/iui/functions/lists.dart';
import 'package:ai_sdk_openui/src/iui/functions/numbers.dart';
import 'package:ai_sdk_openui/src/iui/functions/text.dart';

/// A one-prop component, so any expression runs through the real parser and
/// evaluator with the library's functions and actions (the reference's
/// `__tests__/run.ts`).
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {
    'value': S.any(),
    'action': actionSchema.optional(),
  };
}

final OpenUiLibrary _library = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: [
    ...listFunctions,
    ...numberFunctions,
    ...textFunctions,
    ...colorFunctions,
    ...dateFunctions,
    ...dataFunctions,
  ],
  actions: [copyToClipboard],
);

final class RunResult {
  RunResult(this._session) : _root = _session.root;
  final OpenUiSession _session;
  final OpenUiElement? _root;

  Object? get value => _root?.props['value'];
  OpenUiAction? get action => _root?.props.action('action');

  /// Parser, runtime and query issues.
  List<String> get issues => _session.issues;

  /// The parser's messages: the reference's `parseErrors`.
  List<String> get parseErrors => [
    for (final e in _session.errors)
      if (e.source == OpenUiErrorSource.parser) e.message,
  ];

  /// Evaluation messages: the reference's `runtimeErrors`.
  List<String> get runtimeErrors => [
    for (final e in _session.errors)
      if (e.source == OpenUiErrorSource.runtime) e.message,
  ];

  /// The `action` prop as evaluated: a plan, or nested lists of plans from `@Each`.
  Object? get actions => _root?.props['action'];

  /// Runs a plan's steps as a click does; returns the state after.
  Future<Map<String, Object?>> click([
    OpenUiAction? plan,
    void Function(ActionEvent event)? emit,
  ]) async {
    await _session.run(plan ?? action, label: '', emit: emit ?? (_) {});
    return _session.state;
  }
}

/// Evaluates `root = Out(expr)` plus [extra] statements, with [state]
/// overriding `$variable` defaults.
RunResult run(
  String expr, [
  String extra = '',
  Map<String, Object?> state = const {},
]) {
  final session = OpenUiSession(_library, initialState: state)
    ..update('root = Out($expr)\n$extra', streaming: false);
  return RunResult(session);
}

/// The value of `@Name(args)`.
Object? value(String expr) => run(expr).value;
