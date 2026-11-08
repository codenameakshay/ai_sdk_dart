import 'dart:async';

import '../lang/ast.dart';
import '../lang/js.dart';
import '../lang/parser.dart';
import '../spec/library.dart';
import 'errors.dart';
import 'evaluator.dart';
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
  }) : _tools = {for (final t in tools) t.name: t},
       _initialState = initialState,
       _parser = StreamParser(library.compiled, rootName: library.rootName) {
    _queries = QueryManager(_tools.isEmpty ? null : _callTool);
    _cancelStore = _store.listen(_onStoreChange);
    _cancelQueries = _queries.subscribe(_onChange);
    final schema = library.toJsonSchema();
    final fnSchemas =
        (schema['functions'] as Map?)?.cast<String, Map>() ?? const {};
    _context = EvaluationContext(
      getState: (name) => _unwrapField(_store.get(name)),
      resolveRef: (name) =>
          _queries.getMutationResult(name) ?? _queries.getResult(name),
      functions: {
        for (final f in library.functions)
          f.name: RuntimeFunction(
            params: (fnSchemas[f.name]!['params'] as Map).cast(),
            returns: (fnSchemas[f.name]!['returns'] as Map?)?.cast(),
            fn: f.fn,
          ),
      },
      actions: {
        for (final MapEntry(:key, :value)
            in ((schema['actions'] as Map?) ?? const {}).entries)
          '$key': ((value as Map)['params'] as Map).cast(),
      },
    );
  }

  final OpenUiLibrary library;

  /// react-lang `onError`: the settled answer's errors, once per change.
  final void Function(List<OpenUiError> errors)? onError;

  /// react-lang `onStateUpdate`: the store after each user or action change.
  final void Function(Map<String, Object?> state)? onStateUpdate;
  final Map<String, OpenUiTool> _tools;
  final Map<String, Object?> _initialState;
  final StreamParser _parser;
  final Store _store = Store();
  late final QueryManager _queries;
  late final EvaluationContext _context;
  late final void Function() _cancelStore;
  late final void Function() _cancelQueries;
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
  String _lastErrorKey = '';
  String? _storeKey;
  OpenUiElement? _root;
  bool _dirty = true;
  bool _disposed = false;

  bool get _bundleBlocked => (_bundle?.isBundle ?? false) && _blocked;

  Future<Object?> _callTool(String name, Map<String, Object?> args) {
    final tool = _tools[name];
    if (tool == null) throw ToolNotFoundError(name, _tools.keys.toList());
    return tool.call(args);
  }

  /// Sets the full program text so far. The same text and flag is a no-op.
  void update(String text, {required bool streaming}) {
    if (_disposed || (text == _text && streaming == _streaming)) return;
    _text = text;
    _streaming = streaming;
    final bundle = parseResponseBundle(text, streaming: streaming);
    _bundle = bundle;
    _blocked = streaming || !bundle.complete || bundle.error != null;
    if (!_blocked) {
      _scriptRevision = bundle.scriptRevision;
      _scriptNames = bundle.scripts;
    }
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
    final declarations = result?.stateDeclarations ?? const {};
    final key = '${Js.stringify(declarations)}::${Js.stringify(_initialState)}';
    if (key != _storeKey) {
      _storeKey = key;
      final persisted = <String, Object?>{};
      _initializing = true;
      // initialState only fills keys the store lacks, so a re-parse never undoes user edits.
      for (final MapEntry(:key, :value) in _initialState.entries) {
        if (key.startsWith(r'$')) {
          if (!_store.has(key)) persisted[key] = value;
        } else if (!_store.has(key)) {
          _store.set(key, value);
        }
      }
      _store.initialize(declarations, persisted);
      _initializing = false;
    }
    _syncQueries();
    _onChange();
  }

  bool _initializing = false;

  /// Whether the answer may not run yet: it streams, or it is an incomplete or invalid Cloud bundle.
  bool get isStreaming => _blocked;

  /// Whether a Query is loading, or a bundle still streaming has Queries that will load.
  bool get isQueryLoading =>
      _queries.getSnapshot().loading.isNotEmpty ||
      (_streaming &&
          _bundleBlocked &&
          (_result?.queryStatements.length ?? 0) > 0);

  /// The `$state` and form fields, as JSON to persist and pass back as
  /// `initialState`.
  Map<String, Object?> get state => _store.snapshot;

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

  void _onStoreChange() {
    if (_initializing) {
      _dirty = true;
      return;
    }
    onStateUpdate?.call(_store.snapshot);
    _syncQueries();
    _onChange();
  }

  void _onChange() {
    _dirty = true;
    for (final l in [..._listeners]) {
      l();
    }
    _reportErrors();
  }

  void _reportErrors() {
    final onError = this.onError;
    if (onError == null) return;
    if (_streaming) {
      if (_lastErrorKey.isNotEmpty) {
        _lastErrorKey = '';
        onError(const []);
      }
      return;
    }
    final errors = this.errors;
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
    _queries.registerMutations({
      for (final m
          in result?.mutationStatements ?? const <MutationStatementInfo>[])
        m.statementId: Js.string(eval(m.toolAst) ?? ''),
    });
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
  /// value starts as [bound].
  FieldState field(
    String name,
    Object? bound, {
    String? formName,
    String? componentType,
  }) {
    final p = bound is OpenUiBinding ? bound._assign : null;
    if (p != null) {
      return FieldState._(_store.get(p.target), (value) {
        _store.set(
          p.target,
          evaluate(p.expr, _context.copyWith(extraScope: {r'$value': value})),
        );
      });
    }
    final raw = formName == null ? null : _store.get(formName);
    final hasValue = formName == null
        ? _store.has(name)
        : raw is Map && raw.containsKey(name);
    return FieldState._(
      hasValue ? _fieldValue(formName, name) : bound,
      (value) => _writeField(formName, name, componentType, value),
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
    _writeField(formName, name, componentType, defaultValue);
  }

  void _writeField(
    String? formName,
    String name,
    String? componentType,
    Object? value,
  ) {
    final wrapped = {'value': value, 'componentType': componentType};
    if (formName == null) {
      _store.set(name, wrapped);
    } else {
      final raw = _store.get(formName);
      _store.set(formName, {
        if (raw is Map) ...raw.cast<String, Object?>(),
        name: wrapped,
      });
    }
  }

  Object? _fieldValue(String? formName, String name) {
    if (formName == null) return _unwrapField(_store.get(name));
    final data = _store.get(formName);
    return data is Map ? _unwrapField(data[name]) : null;
  }

  Map<String, Object?> _formPayload(String? formName) {
    if (formName != null) {
      final raw = _store.get(formName);
      if (raw is Map) return {formName: raw};
    }
    return _store.snapshot;
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
  }) async {
    if (_disposed || _bundleBlocked) return;
    ActionEvent event(
      String type,
      Map<String, Object?> params, [
      String message = '',
    ]) => ActionEvent(
      type: type,
      params: params,
      humanFriendlyMessage: message,
      formState: _formPayload(formName),
      formName: formName,
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
    for (final step in plan.steps) {
      if (_disposed) return;
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
          emit(event(name, params));
        case SetStep(:final target, :final valueAst):
          _store.set(target, evaluate(valueAst, _context));
        case ResetStep(:final targets):
          final decls = _result?.stateDeclarations ?? const {};
          for (final t in targets) {
            _store.set(t, decls[t], pristine: true);
          }
      }
    }
  }

  /// Retries failed queries.
  void retryQueries() {
    if (_bundleBlocked) return;
    final failed = [for (final e in queryErrors) e.statementId!];
    if (failed.isNotEmpty) _queries.invalidate(failed);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelStore();
    _cancelQueries();
    _queries.dispose();
    _store.dispose();
    _listeners.clear();
  }
}
