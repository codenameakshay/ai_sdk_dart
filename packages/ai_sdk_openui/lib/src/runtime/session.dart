import 'dart:async';

import '../lang/ast.dart';
import '../lang/js.dart';
import '../lang/parser.dart';
import '../spec/bound.dart';
import '../spec/library.dart';
import 'errors.dart';
import 'evaluator.dart';
import 'host_actions.dart';
import 'locale.dart';
import 'queries.dart';
import 'response_bundle.dart';
import 'store.dart';

/// What a click, a submit or a library action asks the host to do. The
/// fields mirror lang-core's `ActionEvent`.
final class ActionEvent {
  const ActionEvent({
    required this.type,
    this.params = const {},
    this.humanFriendlyMessage = '',
    this.formState = const {},
    this.formName,
    this.results = const {},
  });

  /// `@ToAssistant`, a Button without an action, or a legacy action object.
  static const continueConversation = 'continue_conversation';

  /// `@OpenUrl`; the URL is in `params['url']`.
  static const openUrl = 'open_url';

  /// [continueConversation], [openUrl], or a library action name such as
  /// `CopyToClipboard`.
  final String type;
  final Map<String, Object?> params;

  /// The message a [continueConversation] event sends, as the user wrote it.
  final String humanFriendlyMessage;

  /// The enclosing Form's fields, or the whole state outside a Form.
  final Map<String, Object?> formState;
  final String? formName;

  /// The `ActionSuccess.data` of the handled actions that succeeded earlier
  /// in the same plan, by action name.
  final Map<String, Object?> results;
}

/// A prop's action: a step plan, or a legacy `{type, ...}` action object.
final class OpenUiAction {
  OpenUiAction._plan(ActionPlan this._plan) : _legacy = null;
  OpenUiAction._legacy(Map<String, Object?> this._legacy) : _plan = null;
  final ActionPlan? _plan;
  final Map<String, Object?>? _legacy;

  /// A plan with no steps (an invalid step evaluates to one).
  bool get isEmpty => _plan != null && _plan.steps.isEmpty;
}

/// A `$binding` prop: reading and writing it goes through [OpenUiSession.field].
final class OpenUiBinding {
  const OpenUiBinding._(this._assign);
  final ReactiveAssign _assign;

  /// The bound `$variable`.
  String get variable => _assign.target;
}

/// An evaluated component instance. Its props hold JSON values, nested
/// [OpenUiElement]s, [OpenUiAction]s and [OpenUiBinding]s; never syntax.
final class OpenUiElement {
  OpenUiElement._(this._node) : props = Props._(_node.props);
  final ElementNode _node;
  String get typeName => _node.typeName;
  String? get statementId => _node.statementId;

  /// Still being written: some of its props may not have streamed in yet.
  bool get isPartial => _node.partial;
  final Props props;
}

Object? _public(Object? v) => switch (v) {
  ElementNode() => OpenUiElement._(v),
  ActionPlan() => OpenUiAction._plan(v),
  ReactiveAssign() => OpenUiBinding._(v),
  List() => [for (final x in v) _public(x)],
  Map() => {for (final e in v.entries) '${e.key}': _public(e.value)},
  _ => v,
};

/// Lenient, typed reads of an element's props. A wrong type reads as null.
final class Props {
  Props._(this._raw);
  final Map<String, Object?> _raw;
  final Map<String, Object?> _cache = {};

  bool has(String name) => _raw.containsKey(name) && _raw[name] != null;

  Object? operator [](String name) =>
      _cache.putIfAbsent(name, () => _public(_raw[name]));

  String? string(String name) =>
      this[name] is String ? this[name] as String : null;

  /// A finite number.
  num? number(String name) {
    final v = this[name];
    return v is num && v.isFinite ? v : null;
  }

  bool? boolean(String name) => this[name] is bool ? this[name] as bool : null;

  List<Object?> list(String name) =>
      this[name] is List ? this[name] as List<Object?> : const [];

  /// The elements in a slot, with nested lists (from `@Each`) flattened.
  List<OpenUiElement> elements(String name) => [..._flatElements(this[name])];

  OpenUiAction? action(String name) {
    final v = this[name];
    if (v is OpenUiAction) return v;
    final raw = _raw[name];
    if (raw is Map && raw['steps'] is List) {
      return OpenUiAction._plan(ActionPlan(dataSteps(raw)));
    }
    if (v is Map) return OpenUiAction._legacy(v.cast());
    return null;
  }

  OpenUiBinding? binding(String name) =>
      this[name] is OpenUiBinding ? this[name] as OpenUiBinding : null;
}

Iterable<OpenUiElement> _flatElements(Object? v) sync* {
  if (v is OpenUiElement) {
    yield v;
  } else if (v is List) {
    for (final x in v) {
      yield* _flatElements(x);
    }
  }
}

/// A form field or `$binding` value with its setter.
final class FieldState {
  const FieldState._(this.value, this._set);
  final Object? value;
  final void Function(Object? value) _set;
  void set(Object? value) => _set(value);
}

typedef _Run = ({
  ActionPhase phase,
  int attempt,
  String? message,
  Object? data,
});
typedef _ActiveAction = ({String base, ActionSpec spec});
typedef _PlanRun = ({ActionPhase phase, int cursor, String? message});
typedef _ActivePlan = ({int cursor, ActionPlan plan});

const _actionPlansStateKey = '__plans';

/// lang-core `unwrapFieldValue`: form fields store `{value, componentType}`.
Object? _unwrapField(Object? v) =>
    v is Map && v.containsKey('value') ? v['value'] : v;

/// One answer: streaming program text in, an evaluated element tree out.
///
/// Owns the streaming parser cache, the `$state` store, the Query manager
/// and the step executor. Call [update] with the full text on every chunk.
final class OpenUiSession {
  OpenUiSession(
    this.library, {
    List<OpenUiTool> tools = const [],
    Map<String, Object?> initialState = const {},
    this.onError,
    this.onStateUpdate,
    this.onParseResult,
    List<BoundRecord> records = const [],
    String? locale,
    this.actionScope = '',
    this.resolveAction,
  }) : locale = resolveLocale(locale),
       _tools = {for (final t in tools) t.name: t},
       _initialState = initialState,
       _bound = {for (final r in records) r.variable: Js.normalize(r.value)},
       _parser = StreamParser(
         library.compiled,
         rootName: library.rootName,
         boundNames: {for (final r in records) r.variable},
       ) {
    _restoreActions(initialState[actionStateKey]);
    _queries = QueryManager(_tools.isEmpty ? null : _callTool);
    _cancelStore = _store.listen(_onStoreChange);
    _cancelQueries = _queries.subscribe(_onChange);
    final schema = library.toJsonSchema();
    final fnSchemas =
        (schema['functions'] as Map?)?.cast<String, Map>() ?? const {};
    _context = EvaluationContext(
      getState: (name) => _bound.containsKey(name)
          ? _bound[name]
          : _unwrapField(_store.get(name)),
      resolveRef: (name) =>
          _queries.getMutationResult(name) ?? _queries.getResult(name),
      functions: {
        for (final f in library.functions)
          f.name: RuntimeFunction(
            params: (fnSchemas[f.name]!['params'] as Map).cast(),
            returns: (fnSchemas[f.name]!['returns'] as Map?)?.cast(),
            fn: f.fn,
            localized: f.localized,
          ),
      },
      actions: {
        for (final MapEntry(:key, :value)
            in ((schema['actions'] as Map?) ?? const {}).entries)
          '$key': ((value as Map)['params'] as Map).cast(),
      },
      locale: this.locale,
    );
  }

  final OpenUiLibrary library;

  /// The intl locale functions format in; null for the reference's en-US output.
  final String? locale;

  /// react-lang `onError`: the settled answer's errors, once per change.
  final void Function(List<OpenUiError> errors)? onError;

  /// react-lang `onStateUpdate`: the store after each user or action change.
  final void Function(Map<String, Object?> state)? onStateUpdate;

  /// react-lang `onParseResult`: the raw parse result, each time the
  /// program, its bundle error or the streaming flag changes.
  final void Function(ParseResult? result)? onParseResult;
  Map<String, OpenUiTool> _tools;
  final Map<String, Object?> _initialState;

  /// Prefixed to every handled action's idempotency key: chat adapters pass the message id.
  final String actionScope;

  /// Settles a run that a restore cut off mid-flight. It gets the run's
  /// name, params and original idempotency key; until it returns, the run
  /// is [ActionPhase.unknown] and cannot run again. Without it, such a run
  /// restores as failed and a retry sends the same key.
  final Future<ActionResult> Function(ActionInvocation invocation)?
  resolveAction;

  final Map<String, _Run> _actions = {};

  /// The name and params of each pending or unknown run, saved so a
  /// restore can ask [resolveAction] about it.
  final Map<String, ({String name, Map<String, Object?> params})> _calls = {};
  final Map<String, _PlanRun> _plans = {};
  final Set<String> _locallyRunActions = {};
  final Set<String> _locallyRunPlans = {};
  final Set<String> _runningActionNodes = {};
  final Set<String> _runningPlans = {};
  final Map<String, _ActiveAction> _activeActions = {};
  final Map<String, _ActivePlan> _activePlans = {};
  late final Map<String, ActionSpec> _handled = {
    for (final a in library.actions)
      if (a.handler != null) a.name: a,
  };

  /// Host-bound records by `$name`: read-only, never in [state].
  final Map<String, Object?> _bound;
  final StreamParser _parser;
  final Store _store = Store();
  late QueryManager _queries;
  late final EvaluationContext _context;
  late final void Function() _cancelStore;
  late void Function() _cancelQueries;
  final List<void Function()> _listeners = [];

  String? _text;
  bool _streaming = true;
  bool _blocked = true;
  ResponseBundle? _bundle;
  String? _scriptRevision;
  Set<String> _scriptNames = const {};
  ParseResult? _result;
  OpenUiError? _parseException;
  List<OpenUiError> _runtimeErrors = const [];
  List<OpenUiError> _renderErrors = [];
  bool _renderReportScheduled = false;
  (String, String?, bool)? _parseKey;
  String _lastErrorKey = '';
  String? _storeKey;
  String _restoredStateKey = '';
  OpenUiElement? _root;
  bool _dirty = true;
  bool _disposed = false;

  bool get _bundleBlocked => (_bundle?.isBundle ?? false) && _blocked;

  Future<Object?> _callTool(String name, Map<String, Object?> args) {
    final tool = _tools[name];
    if (tool == null) throw ToolNotFoundError(name, _tools.keys.toList());
    return tool.call(args);
  }

  /// Sets the full program text and any restored state. Identical text,
  /// streaming flag, and restored state is a no-op.
  void update(
    String text, {
    required bool streaming,
    Map<String, Object?>? restoredState,
  }) {
    final restoredStateKey = Js.stringify(restoredState ?? const {});
    if (_disposed ||
        (text == _text &&
            streaming == _streaming &&
            restoredStateKey == _restoredStateKey)) {
      return;
    }
    _text = text;
    _streaming = streaming;
    _restoredStateKey = restoredStateKey;
    final bundle = parseResponseBundle(text, streaming: streaming);
    _bundle = bundle;
    _blocked = streaming || !bundle.complete || bundle.error != null;
    if (!_blocked) {
      _scriptRevision = bundle.scriptRevision;
      _scriptNames = bundle.scripts;
    }
    final parseKey = (bundle.program, bundle.error, streaming);
    if (parseKey != _parseKey) {
      _parseKey = parseKey;
      _parseException = bundle.error == null
          ? null
          : OpenUiError(
              source: OpenUiErrorSource.parser,
              code: OpenUiErrorCode.parseFailed,
              message: bundle.error!,
            );
      ParseResult? result;
      if (bundle.program.isNotEmpty) {
        try {
          result = _parser.set(bundle.program, complete: !streaming);
        } catch (e) {
          // coverage:ignore-start
          _parseException = OpenUiError(
            source: OpenUiErrorSource.parser,
            code: OpenUiErrorCode.parseException,
            message: 'Parser crashed: ${errorMessage(e)}',
            hint: 'The response may contain syntax the parser cannot handle',
          );
          // coverage:ignore-end
        }
      }
      _result = result;
      onParseResult?.call(result);
      if (_disposed) return;
    }
    final declarations = {...?_result?.stateDeclarations}
      ..removeWhere((k, _) => _bound.containsKey(k));
    final key =
        '${Js.stringify(declarations)}::${Js.stringify(_initialState)}::$restoredStateKey';
    if (key != _storeKey) {
      _initializing = true;
      try {
        final persisted = <String, Object?>{};
        // initialState only fills keys the store lacks, so a re-parse never undoes user edits.
        for (final MapEntry(:key, value: raw) in _initialState.entries) {
          if (key == actionStateKey || _bound.containsKey(key)) continue;
          final value = Js.normalize(raw);
          if (!_store.has(key)) persisted[key] = value;
        }
        _store.initialize(declarations, persisted);
        _store.restoreUntouched(_restorableState(restoredState));
        _restoreActions(restoredState?[actionStateKey]);
      } finally {
        _initializing = false;
      }
      _storeKey = key;
    }
    _syncQueries();
    _onChange();
  }

  bool _initializing = false;
  bool _settingDefaultValue = false;

  Map<String, Object?> _restorableState(Map<String, Object?>? state) {
    if (state == null) return const {};
    return {
      for (final MapEntry(:key, :value) in state.entries)
        if (key != actionStateKey && !_bound.containsKey(key))
          key: Js.normalize(value),
    };
  }

  void _restoreActions(Object? saved) {
    if (saved is! Map) return;
    for (final MapEntry(:key, :value) in saved.entries) {
      if (_locallyRunActions.contains('$key') ||
          value is! Map ||
          value['attempt'] is! num) {
        continue;
      }
      final phase = ActionPhase.values.asNameMap()[value['phase']];
      if (phase == null || phase == ActionPhase.idle) continue;
      final cut = phase == ActionPhase.pending || phase == ActionPhase.unknown;
      final unknown = cut && resolveAction != null;
      final resolving = _actions['$key']?.phase == ActionPhase.unknown;
      _actions['$key'] = (
        phase: unknown
            ? ActionPhase.unknown
            : cut
            ? ActionPhase.failed
            : phase,
        attempt: (value['attempt'] as num).toInt(),
        message: cut || value['message'] is! String
            ? null
            : value['message'] as String,
        data: phase == ActionPhase.done
            ? Js.normalize(value['data'], json: true)
            : null,
      );
      if (unknown && !resolving) {
        _calls['$key'] = (
          name: value['name'] is String ? value['name'] as String : '',
          params: value['params'] is Map
              ? (Js.normalize(value['params'], json: true)! as Map)
                    .cast<String, Object?>()
              : const {},
        );
        _resolve('$key');
      }
    }
    final savedPlans = saved[_actionPlansStateKey];
    if (savedPlans is! Map) return;
    for (final MapEntry(:key, :value) in savedPlans.entries) {
      if (_locallyRunPlans.contains('$key') ||
          value is! Map ||
          value['cursor'] is! num) {
        continue;
      }
      final phase = ActionPhase.values.asNameMap()[value['phase']];
      if (phase == null || phase == ActionPhase.idle) continue;
      final cut = phase == ActionPhase.pending || phase == ActionPhase.unknown;
      _plans['$key'] = (
        phase: cut
            ? resolveAction == null
                  ? ActionPhase.failed
                  : ActionPhase.unknown
            : phase,
        cursor: (value['cursor'] as num).toInt(),
        message: cut || value['message'] is! String
            ? null
            : value['message'] as String,
      );
    }
  }

  /// Whether the answer may not run yet: it streams, or it is an incomplete or invalid Cloud bundle.
  bool get isStreaming => _blocked;

  /// Whether a Query is loading, or a bundle still streaming has Queries that will load.
  bool get isQueryLoading =>
      _queries.getSnapshot().loading.isNotEmpty ||
      (_streaming &&
          _bundleBlocked &&
          (_result?.queryStatements.length ?? 0) > 0);

  /// Whether the last [update] said the model is still writing: react-lang's
  /// `isStreaming` prop. [isStreaming] also stays true for an unfinished or
  /// invalid OpenUI Cloud bundle. True before the first update.
  bool get isGenerating => _streaming;

  /// The OpenUI Cloud metadata of the response, such as its `name`.
  ResponseMetadata get metadata =>
      _bundle?.metadata ?? const ResponseMetadata();

  /// The `$state` and form fields, as JSON to persist and pass back as
  /// `initialState`.
  Map<String, Object?> get state => _actions.isEmpty && _plans.isEmpty
      ? _store.snapshot
      : Map.unmodifiable({
          ..._store.snapshot,
          actionStateKey: {
            for (final MapEntry(:key, value: r) in _actions.entries)
              key: {
                'phase': r.phase.name,
                'attempt': r.attempt,
                'message': ?r.message,
                'data': ?r.data,
                if (r.phase == ActionPhase.pending ||
                    r.phase == ActionPhase.unknown) ...{
                  'name': ?_calls[key]?.name,
                  'params': ?_calls[key]?.params,
                },
              },
            if (_plans.isNotEmpty)
              _actionPlansStateKey: {
                for (final MapEntry(:key, value: r) in _plans.entries)
                  key: {
                    'phase': r.phase.name,
                    'cursor': r.cursor,
                    'message': ?r.message,
                  },
              },
          },
        });

  /// lang-core `OpenUIError`s of the settled answer: parse, validation, runtime and tool errors. Empty while streaming.
  List<OpenUiError> get errors {
    if (_streaming) return const [];
    _evaluateIfDirty();
    final result = _result;
    return [
      ?_parseException,
      if ((_bundle?.program ?? '').isNotEmpty &&
          (result?.meta.statementCount ?? 0) == 0 &&
          _parseException == null)
        OpenUiError(
          source: OpenUiErrorSource.parser,
          code: OpenUiErrorCode.parseFailed,
          message: 'Response could not be parsed as valid openui-lang',
          hint:
              'The entire response must be valid openui-lang code starting with root = ${library.rootName}(...)',
        ),
      ...enrichErrors(
        result?.meta.errors ?? const [],
        library.toJsonSchema(),
        library.components.keys.toList(),
      ),
      ..._runtimeErrors,
      ..._renderErrors,
      ..._queries.getSnapshot().errors,
    ];
  }

  /// The errors from failed Queries: what a retry button acts on.
  List<OpenUiError> get queryErrors => [
    for (final e in _queries.getSnapshot().errors)
      if (e.source == OpenUiErrorSource.query) e,
  ];

  /// The messages of [errors].
  List<String> get issues => [for (final e in errors) e.message];

  /// The evaluated root, or null before a component has streamed in.
  OpenUiElement? get root {
    _evaluateIfDirty();
    return _root;
  }

  /// Calls [listener] synchronously after every change; returns a cancel.
  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// react-lang's error boundary: [component]'s builder threw [error]. It is
  /// reported through [onError], with the answer's other errors, once the
  /// current synchronous work (a Flutter frame) ends; dropped while the model
  /// writes.
  void reportRenderError(String component, Object error) {
    if (_disposed || _streaming) return;
    _renderErrors.add(
      OpenUiError(
        source: OpenUiErrorSource.runtime,
        code: OpenUiErrorCode.renderError,
        component: component,
        message: 'Component $component render failed: ${errorMessage(error)}',
      ),
    );
    if (_renderReportScheduled) return;
    _renderReportScheduled = true;
    scheduleMicrotask(() {
      _renderReportScheduled = false;
      if (!_disposed) _reportErrors();
    });
  }

  void _onStoreChange() {
    if (_initializing) {
      _dirty = true;
      return;
    }
    if (!_settingDefaultValue) onStateUpdate?.call(state);
    _syncQueries();
    _onChange();
  }

  void _onChange() {
    if (_disposed) return;
    _dirty = true;
    for (final l in [..._listeners]) {
      l();
      if (_disposed) return;
    }
    _reportErrors();
  }

  void _reportErrors() {
    final onError = this.onError;
    if (onError == null) {
      _renderErrors = [];
      return;
    }
    if (_streaming) {
      _renderErrors = [];
      if (_lastErrorKey.isNotEmpty) {
        _lastErrorKey = '';
        onError(const []);
      }
      return;
    }
    final errors = this.errors;
    _renderErrors = [];
    final key = Js.stringify([for (final e in errors) e.toJson()]);
    if (key == _lastErrorKey) return;
    _lastErrorKey = key;
    onError(errors);
  }

  void _syncQueries() {
    if (_blocked || _disposed) return;
    final result = _result;
    final snapshot = _store.snapshot;
    Object? eval(Ast? node) => node == null ? null : evaluate(node, _context);
    QueryNode queryNode(QueryStatementInfo q) {
      final toolName = Js.string(eval(q.toolAst) ?? '');
      final deps = <String, Object?>{
        for (final d in q.deps ?? const <String>[]) d: snapshot[d],
        if (_scriptNames.contains(toolName))
          '__openuiScriptRevision': _scriptRevision,
      };
      return QueryNode(
        statementId: q.statementId,
        toolName: toolName,
        args: eval(q.argsAst),
        defaults: eval(q.defaultsAst),
        refreshInterval: eval(q.refreshAst),
        deps: deps.isEmpty ? null : deps,
        complete: q.complete,
      );
    }

    _queries.evaluateQueries([
      for (final q in result?.queryStatements ?? const <QueryStatementInfo>[])
        queryNode(q),
    ]);
    _queries.registerMutations([
      for (final m
          in result?.mutationStatements ?? const <MutationStatementInfo>[])
        MutationNode(
          statementId: m.statementId,
          toolName: Js.string(eval(m.toolAst) ?? ''),
        ),
    ]);
  }

  void _evaluateIfDirty() {
    if (!_dirty) return;
    _dirty = false;
    final errors = <OpenUiError>[];
    _runtimeErrors = errors;
    final result = _result;
    if (result == null ||
        (result.root == null && result.rootExpression == null)) {
      _root = null;
      return;
    }
    try {
      final node = evaluateRoot(result, _context, library.isReactive, errors);
      _root = node == null ? null : OpenUiElement._(node);
    } catch (e) {
      // coverage:ignore-start
      errors.add(
        OpenUiError(
          source: OpenUiErrorSource.runtime,
          code: OpenUiErrorCode.runtimeError,
          message: 'Prop evaluation failed: ${errorMessage(e)}',
        ),
      );
      _root = null;
      // coverage:ignore-end
    }
  }

  /// A field's value and setter: a `$binding` writes its `$variable`;
  /// anything else is a form field named [name] (inside [formName]), whose
  /// value starts as [bound]. Like react-lang's `useStateField`, the stored
  /// wrapper is `{value}`.
  FieldState field(String name, Object? bound, {String? formName}) {
    final p = bound is OpenUiBinding ? bound._assign : null;
    if (p != null) {
      return FieldState._(
        _bound.containsKey(p.target) ? _bound[p.target] : _store.get(p.target),
        (value) {
          if (_bound.containsKey(p.target)) return;
          _store.set(
            p.target,
            evaluate(p.expr, _context.copyWith(extraScope: {r'$value': value})),
          );
        },
      );
    }
    final raw = formName == null ? null : _store.get(formName);
    final hasValue = formName == null
        ? _store.has(name)
        : raw is Map && raw.containsKey(name);
    return FieldState._(
      hasValue ? fieldValue(name, formName: formName) : bound,
      (value) => _writeField(formName, name, null, value),
    );
  }

  /// react-lang `useSetDefaultValue`: stores [defaultValue] for a field that has no value yet, once the answer has settled.
  void setDefaultValue(
    String name,
    Object? defaultValue, {
    String? formName,
    String? componentType,
  }) {
    if (_disposed || isStreaming || defaultValue == null) return;
    final raw = formName == null ? null : _store.get(formName);
    final hasValue = formName == null
        ? _store.has(name)
        : raw is Map && raw.containsKey(name);
    if (hasValue) return;
    _settingDefaultValue = true;
    try {
      _writeField(formName, name, componentType, defaultValue, local: false);
    } finally {
      _settingDefaultValue = false;
    }
  }

  void _writeField(
    String? formName,
    String name,
    String? componentType,
    Object? value, {
    bool local = true,
  }) {
    if (_bound.containsKey(formName ?? name)) return;
    final wrapped = {'value': value, 'componentType': ?componentType};
    if (formName == null) {
      _store.set(name, wrapped, local: local);
    } else {
      final raw = _store.get(formName);
      _store.set(
        formName,
        Js.object([
          if (raw is Map) ...raw.cast<String, Object?>().entries,
          MapEntry(name, wrapped),
        ]),
        local: local,
      );
    }
  }

  /// react-lang `getFieldValue`: field [name] of form [formName], or the
  /// top-level field [name] without one.
  Object? fieldValue(String name, {String? formName}) {
    if (formName == null) return _unwrapField(_store.get(name));
    final data = _store.get(formName);
    return data is Map ? _unwrapField(data[name]) : null;
  }

  Map<String, Object?> _formPayload(String? formName) {
    if (formName != null) {
      final raw = _store.get(formName);
      if (raw is Map) return {formName: Js.normalize(raw, json: true)};
    }
    return _store.snapshot;
  }

  String _planKey(ActionPlan plan) {
    final steps = [
      for (final step in plan.steps)
        {
          'step': step.jsFields,
          if (step case RunStep(:final statementId, :final refType))
            'statement': switch (refType) {
              RuntimeRefType.mutation =>
                _result?.mutationStatements
                    .where((s) => s.statementId == statementId)
                    .firstOrNull,
              _ =>
                _result?.queryStatements
                    .where((s) => s.statementId == statementId)
                    .firstOrNull,
            }?.jsFields,
        },
    ];
    return actionBaseKey(actionScope, '__plan', {'steps': steps});
  }

  void _writePlan(String key, _PlanRun plan) {
    _locallyRunPlans.add(key);
    _plans[key] = plan;
    _notifyStateChange();
  }

  void _notifyStateChange() {
    onStateUpdate?.call(state);
    _onChange();
  }

  bool _completedPlanIsDisabled(ActionPlan plan) {
    for (final step in plan.steps) {
      if (step case CustomStep(:final name)) {
        final spec = _handled[name];
        if (spec == null || !spec.disableAfterSuccess) continue;
        if (_actions[_stepBase(step)]?.phase == ActionPhase.done) return true;
      }
    }
    return false;
  }

  String _stepBase(CustomStep step) => actionBaseKey(
    actionScope,
    step.name,
    Js.normalize(step.params, json: true)! as Map<String, Object?>,
  );

  bool _isHandled(ActionStep step) =>
      step is CustomStep && _handled.containsKey(step.name);

  /// The data of the handled steps before [index] that succeeded.
  Map<String, Object?> _resultsBefore(List<ActionStep> steps, int index) => {
    for (final step in steps.take(index))
      if (_isHandled(step))
        if (_actions[_stepBase(step as CustomStep)] case final r?
            when r.phase == ActionPhase.done && r.data != null)
          step.name: r.data,
  };

  /// The saved state of [plan]; an unknown plan follows its cut-off step
  /// once [resolveAction] has settled that step.
  _PlanRun? _planState(ActionPlan plan, String key) {
    final saved = _plans[key];
    if (saved == null || saved.phase != ActionPhase.unknown) return saved;
    final step = saved.cursor < plan.steps.length
        ? plan.steps[saved.cursor]
        : null;
    final run = step != null && _isHandled(step)
        ? _actions[_stepBase(step as CustomStep)]
        : null;
    final next = saved.cursor + 1;
    return switch (run?.phase) {
      ActionPhase.unknown => saved,
      ActionPhase.done => (
        phase: next == plan.steps.length
            ? ActionPhase.done
            : ActionPhase.failed,
        cursor: next,
        message: null,
      ),
      _ => (
        phase: ActionPhase.failed,
        cursor: saved.cursor,
        message: run?.message,
      ),
    };
  }

  _Run _settled(ActionResult result, int attempt) => switch (result) {
    ActionFailure(:final message) => (
      phase: ActionPhase.failed,
      attempt: attempt,
      message: message,
      data: null,
    ),
    ActionSuccess(:final data) => (
      phase: ActionPhase.done,
      attempt: attempt,
      message: null,
      data: Js.normalize(data, json: true),
    ),
  };

  Future<void> _resolve(String base) async {
    final call = _calls[base]!;
    final attempt = _actions[base]!.attempt;
    ActionResult result;
    try {
      result = await resolveAction!(
        ActionInvocation(
          name: call.name,
          params: call.params,
          idempotencyKey: '$base-$attempt',
          attempt: attempt,
        ),
      );
    } catch (e) {
      result = ActionFailure(errorMessage(e));
    }
    if (_disposed || _actions[base]?.phase != ActionPhase.unknown) return;
    _setRun(base, _settled(result, attempt));
  }

  /// Runs a click. A plan runs its steps in order: `@Set` evaluates at click
  /// time, a failed Mutation stops the plan, host steps go to [emit]. With
  /// no action, the [label] goes to the assistant (a Button without an
  /// action). Plain text runs while it streams; an OpenUI Cloud bundle
  /// does not run until it is complete and valid.
  Future<void> run(
    OpenUiAction? action, {
    required String label,
    String? formName,
    required void Function(ActionEvent event) emit,
    bool confirmed = false,
    String nodeId = '',
  }) async {
    if (_disposed || _bundleBlocked) return;
    var results = const <String, Object?>{};
    ActionEvent event(
      String type,
      Map<String, Object?> params, [
      String message = '',
    ]) => ActionEvent(
      type: type,
      params: Js.normalize(params, json: true)! as Map<String, Object?>,
      humanFriendlyMessage: message,
      formState: _formPayload(formName),
      formName: formName,
      results: results,
    );
    final legacy = action?._legacy;
    if (legacy != null) {
      final type = Js.truthy(legacy['type'])
          ? Js.string(legacy['type'])
          : ActionEvent.continueConversation;
      if (library.actions.any((a) => a.name == type)) return;
      emit(
        event(type, {
          if (legacy['params'] is Map)
            ...(legacy['params'] as Map).cast<String, Object?>(),
          if (Js.truthy(legacy['url'])) 'url': legacy['url'],
          if (Js.truthy(legacy['context'])) 'context': legacy['context'],
        }, label),
      );
      return;
    }
    final plan = action?._plan;
    if (plan == null) {
      emit(event(ActionEvent.continueConversation, const {}, label));
      return;
    }
    if (!confirmed &&
        plan.steps.any(
          (s) => s is CustomStep && _handled[s.name]?.confirm != null,
        )) {
      return;
    }
    final guarded = plan.steps.any(_isHandled);
    // A write the host is still checking never runs again meanwhile.
    if (plan.steps.any(
      (s) =>
          _isHandled(s) &&
          _actions[_stepBase(s as CustomStep)]?.phase == ActionPhase.unknown,
    )) {
      return;
    }
    final planKey = guarded ? _planKey(plan) : null;
    final savedPlan = planKey == null ? null : _planState(plan, planKey);
    if (savedPlan?.phase == ActionPhase.done &&
        _completedPlanIsDisabled(plan)) {
      return;
    }
    final start = savedPlan?.phase == ActionPhase.done
        ? 0
        : savedPlan?.cursor ?? 0;
    // Another node may run the same plan (same key): it waits for this run.
    if (guarded &&
        (_runningPlans.contains(planKey) || !_runningActionNodes.add(nodeId))) {
      return;
    }
    if (guarded) _runningPlans.add(planKey!);
    try {
      if (guarded) {
        _activePlans[nodeId] = (cursor: start, plan: plan);
        _writePlan(planKey!, (
          phase: ActionPhase.pending,
          cursor: start,
          message: null,
        ));
      }
      for (var index = start; index < plan.steps.length; index++) {
        if (_disposed) return;
        final step = plan.steps[index];
        results = _resultsBefore(plan.steps, index);
        if (guarded) {
          _activePlans[nodeId] = (cursor: index, plan: plan);
        }
        switch (step) {
          case RunStep(:final statementId, :final refType):
            if (refType == RuntimeRefType.mutation) {
              final m = _result?.mutationStatements
                  .where((m) => m.statementId == statementId)
                  .firstOrNull;
              final args = m?.argsAst == null
                  ? null
                  : evaluate(m!.argsAst!, _context);
              if (!await _queries.fireMutation(
                statementId,
                args is Map ? args.cast() : const {},
              )) {
                if (guarded && !_disposed) {
                  _writePlan(planKey!, (
                    phase: ActionPhase.failed,
                    cursor: index,
                    message: _queries
                        .getSnapshot()
                        .errors
                        .where(
                          (error) =>
                              error.source == OpenUiErrorSource.mutation &&
                              error.statementId == statementId,
                        )
                        .firstOrNull
                        ?.message,
                  ));
                }
                return;
              }
            } else {
              _queries.invalidate([statementId]);
            }
          case ToAssistantStep(:final message, :final context):
            emit(
              event(ActionEvent.continueConversation, {
                'context': ?context,
              }, message),
            );
          case OpenUrlStep(:final url):
            emit(event(ActionEvent.openUrl, {'url': url}));
          case CustomStep(:final name, :final params):
            final spec = _handled[name];
            if (spec == null) {
              emit(event(name, params));
            } else if (!await _runHandled(
              spec,
              Js.normalize(params, json: true)! as Map<String, Object?>,
              formName,
              nodeId,
              results: results,
              planKey: guarded ? planKey : null,
              cursor: index,
              nextCursor: index + 1,
              done: index + 1 == plan.steps.length,
            )) {
              if (guarded &&
                  !_disposed &&
                  _plans[planKey!]?.phase == ActionPhase.pending) {
                _writePlan(planKey, (
                  phase: ActionPhase.done,
                  cursor: index,
                  message: null,
                ));
              }
              return;
            }
          case SetStep(:final target, :final valueAst):
            if (!_bound.containsKey(target)) {
              _store.set(target, evaluate(valueAst, _context));
            }
          case ResetStep(:final targets):
            final decls = _result?.stateDeclarations ?? const {};
            for (final t in targets) {
              if (_disposed) return;
              if (_bound.containsKey(t)) continue;
              _store.set(t, decls[t], pristine: true);
            }
        }
        final isHandledCustom = switch (step) {
          CustomStep(:final name) when _handled.containsKey(name) => true,
          _ => false,
        };
        if (guarded && !isHandledCustom) {
          final next = index + 1;
          _writePlan(planKey!, (
            phase: next == plan.steps.length
                ? ActionPhase.done
                : ActionPhase.pending,
            cursor: next,
            message: null,
          ));
        }
      }
    } finally {
      if (guarded) {
        _runningActionNodes.remove(nodeId);
        _runningPlans.remove(planKey);
        _activeActions.remove(nodeId);
        _activePlans.remove(nodeId);
        _onChange();
      }
    }
  }

  void _setRun(String base, _Run run, {String? planKey, _PlanRun? planRun}) {
    _locallyRunActions.add(base);
    _actions[base] = run;
    if (planKey != null && planRun != null) {
      _locallyRunPlans.add(planKey);
      _plans[planKey] = planRun;
    }
    _notifyStateChange();
  }

  int _nextAttempt(_Run? r) => r == null
      ? 1
      : r.phase == ActionPhase.done
      ? r.attempt + 1
      : r.attempt;

  Future<bool> _runHandled(
    ActionSpec spec,
    Map<String, Object?> params,
    String? formName,
    String nodeId, {
    Map<String, Object?> results = const {},
    String? planKey,
    int cursor = 0,
    int nextCursor = 0,
    bool done = false,
  }) async {
    final base = actionBaseKey(actionScope, spec.name, params);
    final last = _actions[base];
    if (last?.phase == ActionPhase.pending) return false;
    if (last?.phase == ActionPhase.done && spec.disableAfterSuccess) {
      return false;
    }
    final attempt = _nextAttempt(last);
    _activeActions[nodeId] = (base: base, spec: spec);
    _calls[base] = (name: spec.name, params: params);
    _setRun(
      base,
      (phase: ActionPhase.pending, attempt: attempt, message: null, data: null),
      planKey: planKey,
      planRun: planKey == null
          ? null
          : (phase: ActionPhase.pending, cursor: cursor, message: null),
    );
    ActionResult result;
    try {
      result = await spec.handler!(
        ActionInvocation(
          name: spec.name,
          params: params,
          idempotencyKey: '$base-$attempt',
          attempt: attempt,
          formState: _formPayload(formName),
          formName: formName,
          results: results,
        ),
      );
    } catch (e) {
      result = ActionFailure(errorMessage(e));
    }
    if (_disposed) return false;
    final success = result is ActionSuccess;
    _setRun(
      base,
      _settled(result, attempt),
      planKey: planKey,
      planRun: planKey == null
          ? null
          : (
              phase: success
                  ? done
                        ? ActionPhase.done
                        : ActionPhase.pending
                  : ActionPhase.failed,
              cursor: success ? nextCursor : cursor,
              message: switch (result) {
                ActionFailure(:final message) => message,
                ActionSuccess() => null,
              },
            ),
    );
    return success;
  }

  /// The current/next handled step at the plan cursor, or the first handled
  /// step after completion; the enclosing plan's phase takes precedence.
  /// Null when [action] has no handled steps.
  /// [ActionStatus.confirm] is the first confirm of any handled step.
  ActionStatus? actionStatus(OpenUiAction? action, {String nodeId = ''}) {
    final plan = action?._plan;
    final steps = plan?.steps ?? const <ActionStep>[];
    final handled = [
      for (final s in steps)
        if (s is CustomStep && _handled.containsKey(s.name)) s,
    ];
    if (handled.isEmpty) return null;
    final activePlan = _activePlans[nodeId];
    final planState = activePlan == null
        ? _planState(plan!, _planKey(plan))
        : (
            phase: ActionPhase.pending,
            cursor: activePlan.cursor,
            message: null,
          );
    final activeSteps = activePlan?.plan.steps ?? steps;
    final cursor = planState?.cursor ?? 0;
    final statusStep =
        _handledStepAtOrAfter(activeSteps, cursor) ??
        _handledStepAtOrAfter(activeSteps, 0)!;
    var spec = _handled[statusStep.name]!;
    final isActiveHandledStep =
        activePlan != null &&
        cursor < activeSteps.length &&
        activeSteps[cursor] is CustomStep &&
        _handled.containsKey((activeSteps[cursor] as CustomStep).name);
    final active = isActiveHandledStep ? _activeActions[nodeId] : null;
    if (active != null) {
      spec = active.spec;
    }
    final base = active?.base ?? _stepBase(statusStep);
    final r = _actions[base];
    final phase = planState?.phase ?? r?.phase ?? ActionPhase.idle;
    final disableAfterSuccess =
        phase == ActionPhase.done && _completedPlanIsDisabled(plan!);
    return ActionStatus(
      phase: phase,
      idempotencyKey: '$base-${_nextAttempt(r)}',
      message: planState?.message ?? r?.message,
      confirm: [
        for (final s in handled) ?_handled[s.name]!.confirm,
      ].firstOrNull,
      disabled:
          phase == ActionPhase.pending ||
          phase == ActionPhase.unknown ||
          disableAfterSuccess ||
          (planState == null &&
              phase == ActionPhase.done &&
              spec.disableAfterSuccess),
    );
  }

  CustomStep? _handledStepAtOrAfter(List<ActionStep> steps, int start) {
    for (var i = start; i < steps.length; i++) {
      final step = steps[i];
      if (step is CustomStep && _handled.containsKey(step.name)) return step;
    }
    return null;
  }

  /// react-lang `retryQueries`: refetches the failed Queries, or every Query
  /// when none failed.
  void retryQueries() {
    if (_bundleBlocked) return;
    _queries.invalidate([for (final e in queryErrors) e.statementId!]);
  }

  /// react-lang's `toolProvider` prop: Queries and Mutations call [tools]
  /// from now on. Going from no tools to some, or back, starts a new Query
  /// manager, as react-lang does, so every Query fetches again.
  void setTools(List<OpenUiTool> tools) {
    if (_disposed) return;
    final had = _tools.isNotEmpty;
    _tools = {for (final t in tools) t.name: t};
    if (had == _tools.isNotEmpty) return;
    _cancelQueries();
    _queries.dispose();
    _queries = QueryManager(_tools.isEmpty ? null : _callTool);
    _cancelQueries = _queries.subscribe(_onChange);
    _syncQueries();
    _onChange();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _runningActionNodes.clear();
    _runningPlans.clear();
    _activeActions.clear();
    _activePlans.clear();
    _locallyRunActions.clear();
    _locallyRunPlans.clear();
    _cancelStore();
    _cancelQueries();
    _queries.dispose();
    _store.dispose();
    _listeners.clear();
  }
}
