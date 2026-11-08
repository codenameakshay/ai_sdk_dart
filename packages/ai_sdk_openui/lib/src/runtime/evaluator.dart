import '../lang/ast.dart';
import 'builtins.dart';
import 'errors.dart';
import '../lang/js.dart';
import '../lang/parser.dart' show ParseResult, loopVarName;
import '../lang/validation.dart';

/// A two-way binding: writing `$value` runs [expr] and stores the result in
/// [target]. Bound inputs receive this instead of the state's value.
final class ReactiveAssign implements JsFields {
  const ReactiveAssign(this.target, this.expr);
  final String target;
  final Ast expr;

  @override
  Map<String, Object?> get jsFields => {
    '__reactive': 'assign',
    'target': target,
    'expr': expr,
  };
}

/// lang-core `ACTION_STEPS`: each built-in step's runtime step type.
const Map<String, String> actionSteps = {
  'Run': 'run',
  'ToAssistant': 'continue_conversation',
  'OpenUrl': 'open_url',
  'Set': 'set',
  'Reset': 'reset',
};

/// An evaluated action: the steps a click runs, in order.
final class ActionPlan implements JsFields {
  const ActionPlan(this.steps);
  final List<ActionStep> steps;
  static const empty = ActionPlan([]);

  @override
  Map<String, Object?> get jsFields => {'steps': steps};
}

/// A step of a plan; [jsFields] are lang-core's step object.
sealed class ActionStep implements JsFields {
  const ActionStep();
}

final class RunStep extends ActionStep {
  const RunStep(this.statementId, this.refType);
  final String statementId;
  final RuntimeRefType refType;

  @override
  Map<String, Object?> get jsFields => {
    'type': 'run',
    'statementId': statementId,
    'refType': refType.name,
  };
}

final class ToAssistantStep extends ActionStep {
  const ToAssistantStep(this.message, [this.context]);
  final String message;
  final Object? context;

  @override
  Map<String, Object?> get jsFields => {
    'type': 'continue_conversation',
    'message': message,
    'context': ?context,
  };
}

final class OpenUrlStep extends ActionStep {
  const OpenUrlStep(this.url);
  final String url;

  @override
  Map<String, Object?> get jsFields => {'type': 'open_url', 'url': url};
}

final class SetStep extends ActionStep {
  const SetStep(this.target, this.valueAst);
  final String target;
  final Ast valueAst;

  @override
  Map<String, Object?> get jsFields => {
    'type': 'set',
    'target': target,
    'valueAST': valueAst,
  };
}

final class ResetStep extends ActionStep {
  const ResetStep(this.targets);
  final List<String> targets;

  @override
  Map<String, Object?> get jsFields => {'type': 'reset', 'targets': targets};
}

/// A library action call such as `@CopyToClipboard(text)`. Only an
/// evaluated call creates one, so data cannot pose as a custom action.
final class CustomStep extends ActionStep {
  const CustomStep._(this.name, this.params);
  final String name;
  final Map<String, Object?> params;

  @override
  Map<String, Object?> get jsFields => {
    'type': 'custom_action',
    'name': name,
    'params': params,
  };
}

/// A library `@function` as the runtime calls it.
final class RuntimeFunction {
  const RuntimeFunction({required this.params, required this.fn, this.returns});
  final JsonSchema params;
  final JsonSchema? returns;
  final Object? Function(Map<String, Object?> args) fn;
}

/// What evaluation reads from: state, statement refs, library calls.
final class EvaluationContext {
  const EvaluationContext({
    required this.getState,
    required this.resolveRef,
    this.functions = const {},
    this.actions = const {},
    this.extraScope,
    this.reportError,
  });

  final Object? Function(String name) getState;
  final Object? Function(String name) resolveRef;
  final Map<String, RuntimeFunction> functions;

  /// Library action param schemas by name.
  final Map<String, JsonSchema> actions;
  final Map<String, Object?>? extraScope;
  final void Function(String message)? reportError;

  EvaluationContext copyWith({
    Object? Function(String name)? resolveRef,
    Map<String, Object?>? extraScope,
    void Function(String message)? reportError,
  }) => EvaluationContext(
    getState: getState,
    resolveRef: resolveRef ?? this.resolveRef,
    functions: functions,
    actions: actions,
    extraScope: extraScope ?? this.extraScope,
    reportError: reportError ?? this.reportError,
  );
}

/// Whether a component's prop is a `$binding` (two-way) prop.
typedef IsReactiveProp = bool Function(String component, String prop);

/// lang-core `evaluate`. [reactive] is lang-core's schema context: present
/// when evaluating props for rendering.
Object? evaluate(Ast node, EvaluationContext ctx, [IsReactiveProp? reactive]) {
  switch (node) {
    case StrNode(:final value):
      return value;
    case NumNode(:final value):
      return value;
    case BoolNode(:final value):
      return value;
    case NullNode() || PlaceholderNode():
      return null;
    case ValueNode(:final value):
      return value;
    case StateRefNode(:final name):
      return ctx.extraScope?[name] ?? ctx.getState(name);
    case RefNode(:final name):
      return ctx.resolveRef(name);
    case RuntimeRefNode(:final name):
      return ctx.resolveRef(name);
    case ArrNode(:final elements):
      return [for (final e in elements) evaluate(e, ctx)];
    case ObjNode(:final entries):
      return Js.object([
        for (final (k, v) in entries) MapEntry(k, evaluate(v, ctx)),
      ]);
    case CompNode():
      return _evaluateCall(node, ctx, reactive);
    case BinOpNode(:final op, :final left, :final right):
      if (op == '&&') {
        final l = evaluate(left, ctx);
        return Js.truthy(l) ? evaluate(right, ctx) : l;
      }
      if (op == '||') {
        final l = evaluate(left, ctx);
        return Js.truthy(l) ? l : evaluate(right, ctx);
      }
      final l = evaluate(left, ctx);
      final r = evaluate(right, ctx);
      switch (op) {
        case '+':
          if (l is String || r is String) {
            return Js.string(l ?? '') + Js.string(r ?? '');
          }
          return Js.toNumber(l).toDouble() + Js.toNumber(r).toDouble();
        case '-':
          return Js.toNumber(l).toDouble() - Js.toNumber(r).toDouble();
        case '*':
          return Js.toNumber(l).toDouble() * Js.toNumber(r).toDouble();
        case '/':
          final d = Js.toNumber(r);
          return d == 0 ? 0 : Js.toNumber(l) / d;
        case '%':
          final d = Js.toNumber(r);
          return d == 0 ? 0 : Js.toNumber(l).toDouble().remainder(d.toDouble());
        case '==':
          return Js.looseEquals(l, r);
        case '!=':
          return !Js.looseEquals(l, r);
        case '>':
          return Js.toNumber(l) > Js.toNumber(r);
        case '<':
          return Js.toNumber(l) < Js.toNumber(r);
        case '>=':
          return Js.toNumber(l) >= Js.toNumber(r);
        case '<=':
          return Js.toNumber(l) <= Js.toNumber(r);
      }
      return null;
    case UnaryOpNode(:final op, :final operand):
      if (op == '!') return !Js.truthy(evaluate(operand, ctx));
      if (op == '-') return -Js.toNumber(evaluate(operand, ctx)).toDouble();
      return null;
    case TernaryNode(:final condition, :final then, :final otherwise):
      return Js.truthy(evaluate(condition, ctx))
          ? evaluate(then, ctx)
          : evaluate(otherwise, ctx);
    case MemberNode(:final object, :final field):
      final obj = evaluate(object, ctx);
      if (obj == null) return null;
      // A list plucks the field from every item.
      if (obj is List && field != 'length') {
        return [for (final item in obj) Js.property(item, field)];
      }
      return Js.property(obj, field);
    case IndexNode(:final object, :final index):
      final obj = evaluate(object, ctx);
      final idx = evaluate(index, ctx);
      if (obj == null || idx == null) return null;
      return Js.property(
        obj,
        obj is List ? Js.numberToString(Js.toNumber(idx)) : Js.string(idx),
      );
    case AssignNode(:final target, :final value):
      return ReactiveAssign(target, value);
  }
}

final Set<String> _stepNames = {
  ...builtinStepSpecs.map((s) => s.name),
  'Action',
};

Object? _evaluateCall(
  CompNode node,
  EvaluationContext ctx,
  IsReactiveProp? reactive,
) {
  final builtin = builtinFunctions[node.name];
  if (builtin != null) return builtin.fn(_evaluateArgs(node, ctx));
  if (node.name == 'Each') return _evaluateEach(node.args, ctx, reactive);
  if (_stepNames.contains(node.name)) return _evaluateActionCall(node, ctx);
  final fn = ctx.functions[node.name];
  if (fn != null) return _callFunction(node.name, fn, node, ctx);
  final action = ctx.actions[node.name];
  if (action != null) {
    final args = _callArgs(node, ctx, action);
    if (_missesRequired(args, action)) return ActionPlan.empty;
    final params = _checkValue(args, action, node.name, '', ctx, strict: true);
    if (identical(params, invalid)) return ActionPlan.empty;
    return ActionPlan([CustomStep._(node.name, (params as Map).cast())]);
  }
  final mapped = node.mappedProps;
  if (mapped == null) return null;
  final props = <String, Object?>{};
  for (final MapEntry(key: prop, :value) in mapped.entries) {
    if (value is StateRefNode && (reactive?.call(node.name, prop) ?? false)) {
      props[prop] = ReactiveAssign(value.name, const StateRefNode(r'$value'));
    } else if (value is StateRefNode) {
      props[prop] = reactive != null ? ctx.getState(value.name) : value;
    } else {
      props[prop] = evaluate(value, ctx, reactive);
    }
  }
  final element = ElementNode(
    typeName: node.name,
    props: props,
    partial: false,
    hasDynamicProps: true,
  );
  if (reactive != null) {
    for (final MapEntry(:key, :value) in props.entries.toList()) {
      if (value is ElementNode) {
        props[key] = evaluateElement(value, ctx, reactive);
      } else if (value is List) {
        props[key] = [
          for (final item in value)
            item is ElementNode ? evaluateElement(item, ctx, reactive) : item,
        ];
      }
    }
  }
  return element;
}

/// Built-in functions' and steps' param names, in order.
final Map<String, List<String>> _builtinParams = {
  for (final f in builtinFunctionSpecs) f.name: f.params.keys.toList(),
  for (final s in builtinStepSpecs) s.name: s.params.keys.toList(),
};

/// A call's args by name. The parser names them in mappedProps; an AST
/// from parseExpression alone is named here, by [params] or the built-in's.
Map<String, Object?> _evaluateArgs(
  CompNode node,
  EvaluationContext ctx, [
  List<String>? params,
]) {
  final names = params ?? _builtinParams[node.name] ?? const [];
  final named =
      node.mappedProps ??
      {
        for (var i = 0; i < names.length && i < node.args.length; i++)
          names[i]: node.args[i],
      };
  return {
    for (final MapEntry(:key, :value) in named.entries)
      key: evaluate(value, ctx),
  };
}

/// A library call's args; an explicit null for an optional param is dropped
/// so its default applies.
Map<String, Object?> _callArgs(
  CompNode node,
  EvaluationContext ctx,
  JsonSchema params,
) {
  final required = (params['required'] as List?) ?? const [];
  final names = ((params['properties'] as Map?) ?? const {}).keys;
  final args = _evaluateArgs(node, ctx, [for (final n in names) '$n']);
  args.removeWhere((key, value) => value == null && !required.contains(key));
  return args;
}

Object? _checkValue(
  Object? value,
  JsonSchema schema,
  String name,
  String path,
  EvaluationContext ctx, {
  bool strict = false,
}) {
  final vctx = ValidationContext();
  final checked = validateSchemaValue(value, schema, name, path, vctx);
  for (final e in vctx.errors) {
    ctx.reportError?.call('@$name: ${e.message}');
  }
  return strict && vctx.errors.isNotEmpty ? invalid : checked;
}

bool _missesRequired(Map<String, Object?> args, JsonSchema params) {
  final required = (params['required'] as List?) ?? const [];
  final props = (params['properties'] as Map?) ?? const {};
  return required.any(
    (key) => args[key] == null && identical(schemaDefault(props[key]), absent),
  );
}

Object? _callFunction(
  String name,
  RuntimeFunction def,
  CompNode node,
  EvaluationContext ctx,
) {
  final raw = _callArgs(node, ctx, def.params);
  if (_missesRequired(raw, def.params)) return null;
  final args = _checkValue(raw, def.params, name, '', ctx);
  if (identical(args, invalid)) return null;
  Object? result;
  try {
    result = def.fn((args as Map).cast());
  } catch (e) {
    ctx.reportError?.call('@$name threw: ${errorMessage(e)}');
    return null;
  }
  final returns = def.returns;
  if (returns == null) return result;
  final checked = _checkValue(result, returns, name, '/returns', ctx);
  return identical(checked, invalid) ? null : checked;
}

/// `Action([...])` flattens plans; a stray `{type: ...}` map from data becomes
/// a built-in step when it has a known legacy shape, and is dropped otherwise.
ActionPlan _flatten(List<Object?> values) => ActionPlan([
  for (final v in values)
    if (v is ActionPlan) ...v.steps else ?_legacyStep(v),
]);

ActionStep? _legacyStep(Object? v) {
  if (v is! Map) return null;
  return switch (v['type']) {
    'open_url' when v['url'] is String => OpenUrlStep(v['url'] as String),
    'continue_conversation' => ToAssistantStep(
      Js.string(v['message'] ?? ''),
      v['context'],
    ),
    _ => null,
  };
}

ActionPlan _evaluateActionCall(CompNode node, EvaluationContext ctx) {
  final args = node.args;
  switch (node.name) {
    case 'Action':
      final list = args.isNotEmpty ? evaluate(args[0], ctx) : const [];
      return _flatten(list is List ? list : const []);
    case 'ToAssistant':
      final a = _evaluateArgs(node, ctx);
      return ActionPlan([
        ToAssistantStep(Js.string(a['message'] ?? ''), a['context']),
      ]);
    case 'OpenUrl':
      final a = _evaluateArgs(node, ctx);
      return ActionPlan([OpenUrlStep(Js.string(a['url'] ?? ''))]);
    case 'Run':
      final ref = args.isNotEmpty ? args[0] : null;
      return ref is RuntimeRefNode
          ? ActionPlan([RunStep(ref.name, ref.refType)])
          : ActionPlan.empty;
    case 'Set':
      return args.length >= 2 && args[0] is StateRefNode
          ? ActionPlan([SetStep((args[0] as StateRefNode).name, args[1])])
          : ActionPlan.empty;
    case 'Reset':
      final targets = [
        for (final a in args)
          if (a is StateRefNode) a.name,
      ];
      return targets.isEmpty
          ? ActionPlan.empty
          : ActionPlan([ResetStep(targets)]);
  }
  return ActionPlan.empty;
}

/// Replaces `Ref(varName)` with the loop item's literal, so deferred steps
/// (like `@Set` inside an `@Each` template) capture the value.
Ast substituteRef(Ast node, String varName, Object? value) {
  Ast sub(Ast a) => substituteRef(a, varName, value);
  switch (node) {
    case RefNode(:final name):
      return name == varName ? literalAst(value) : node;
    case MemberNode(:final object, :final field):
      final subObj = sub(object);
      if (subObj is ObjNode) {
        for (final (k, v) in subObj.entries) {
          if (k == field) return v;
        }
      }
      return MemberNode(subObj, field);
    case IndexNode(:final object, :final index):
      return IndexNode(sub(object), sub(index));
    case BinOpNode(:final op, :final left, :final right):
      return BinOpNode(op, sub(left), sub(right));
    case UnaryOpNode(:final op, :final operand):
      return UnaryOpNode(op, sub(operand));
    case TernaryNode(:final condition, :final then, :final otherwise):
      return TernaryNode(sub(condition), sub(then), sub(otherwise));
    case ArrNode(:final elements):
      return ArrNode(elements.map(sub).toList());
    case ObjNode(:final entries):
      return ObjNode([for (final (k, v) in entries) (k, sub(v))]);
    case CompNode(:final args, :final mappedProps):
      return node.copyWith(
        args: args.map(sub).toList(),
        mappedProps: mappedProps?.map((k, v) => MapEntry(k, sub(v))),
      );
    case AssignNode(:final target, :final value):
      return AssignNode(target, sub(value));
    default:
      return node;
  }
}

List<Object?> _evaluateEach(
  List<Ast> args,
  EvaluationContext ctx,
  IsReactiveProp? reactive,
) {
  if (args.length < 3) return const [];
  final list = evaluate(args[0], ctx);
  if (list is! List) return const [];
  final varName = loopVarName(args[1]);
  if (varName == null) return const [];
  return [
    for (final item in list)
      () {
        final childCtx = ctx.copyWith(
          resolveRef: (ref) => ref == varName ? item : ctx.resolveRef(ref),
        );
        final result = evaluate(
          substituteRef(args[2], varName, item),
          childCtx,
          reactive,
        );
        return reactive != null && result is ElementNode
            ? evaluateElement(result, childCtx, reactive)
            : result;
      }(),
  ];
}

/// lang-core `evaluateElementProps`: evaluates each prop, reporting a failure to [errors] instead of throwing.
ElementNode evaluateElementProps(
  ElementNode el,
  EvaluationContext ctx,
  IsReactiveProp reactive,
  List<OpenUiError> errors,
) {
  if (!el.hasDynamicProps) return el;
  var key = '';
  void report(String message) => errors.add(
    OpenUiError(
      source: OpenUiErrorSource.runtime,
      code: OpenUiErrorCode.runtimeError,
      component: el.typeName,
      statementId: el.statementId,
      message: 'Evaluating prop "$key" on ${el.typeName} failed: $message',
      hint: 'Check the expression used for prop "$key"',
    ),
  );
  final propCtx = ctx.copyWith(reportError: report);
  final out = <String, Object?>{};
  for (final MapEntry(key: prop, :value) in el.props.entries) {
    key = prop;
    try {
      out[prop] = evaluateProp(
        value,
        propCtx,
        reactive,
        reactive(el.typeName, prop),
        recurseElement: (child) =>
            evaluateElementProps(child, propCtx, reactive, errors),
      );
    } catch (e) {
      // lang-core keeps the raw value; Dart props never hold syntax, so it reads as null.
      out[prop] = null;
      report(errorMessage(e));
    }
  }
  return el.withProps(out);
}

/// lang-core `evaluateRoot`: the root element, or the component a runtime entry picks; null if none.
ElementNode? evaluateRoot(
  ParseResult result,
  EvaluationContext ctx,
  IsReactiveProp reactive,
  List<OpenUiError> errors,
) {
  final root = result.root;
  if (root != null) return evaluateElementProps(root, ctx, reactive, errors);
  final expression = result.rootExpression;
  if (expression == null) return null;
  final value = evaluate(expression, ctx, reactive);
  if (value is ElementNode) {
    return evaluateElementProps(value, ctx, reactive, errors);
  }
  errors.add(
    const OpenUiError(
      source: OpenUiErrorSource.runtime,
      code: OpenUiErrorCode.noRoot,
      statementId: 'root',
      message: 'root does not evaluate to a component',
    ),
  );
  return null;
}

/// lang-core `stripReactiveAssign`: a binding read as its current state value.
Object? stripReactiveAssign(Object? value, EvaluationContext ctx) =>
    value is ReactiveAssign ? ctx.getState(value.target) : value;

/// lang-core `evaluateElementInline` / `evaluateElementProps`: resolves every
/// prop of an element for rendering.
ElementNode evaluateElement(
  ElementNode el,
  EvaluationContext ctx,
  IsReactiveProp reactive,
) {
  if (!el.hasDynamicProps) return el;
  return el.withProps({
    for (final MapEntry(:key, :value) in el.props.entries)
      key: evaluateProp(value, ctx, reactive, reactive(el.typeName, key)),
  });
}

/// lang-core `evaluatePropCore`.
Object? evaluateProp(
  Object? value,
  EvaluationContext ctx,
  IsReactiveProp reactive,
  bool isReactive, {
  ElementNode Function(ElementNode el)? recurseElement,
}) {
  final recurse =
      recurseElement ?? (ElementNode el) => evaluateElement(el, ctx, reactive);
  if (value == null ||
      value is String && !isReactive ||
      value is num ||
      value is bool) {
    return value;
  }
  if (value is String) return value;
  if (value is Ast) {
    if (value is StateRefNode && isReactive) {
      return ReactiveAssign(value.name, const StateRefNode(r'$value'));
    }
    final result = evaluate(value, ctx, reactive);
    if (result is ElementNode) return recurse(result);
    if (result is List) {
      return [
        for (final item in result) item is ElementNode ? recurse(item) : item,
      ];
    }
    if (result is ReactiveAssign && !isReactive) {
      return ctx.getState(result.target);
    }
    return result;
  }
  if (value is List) {
    return [
      for (final v in value)
        evaluateProp(
          v,
          ctx,
          reactive,
          isReactive,
          recurseElement: recurseElement,
        ),
    ];
  }
  if (value is ElementNode) return recurse(value);
  if (value is ActionPlan || value is ReactiveAssign) return value;
  if (value is Map) {
    if (!value.values.any(
      (v) => v != null && v is! String && v is! num && v is! bool,
    )) {
      return value;
    }
    return <String, Object?>{
      for (final MapEntry(:key, value: v) in value.entries)
        '$key': evaluateProp(
          v,
          ctx,
          reactive,
          isReactive,
          recurseElement: recurseElement,
        ),
    };
  }
  return value;
}
