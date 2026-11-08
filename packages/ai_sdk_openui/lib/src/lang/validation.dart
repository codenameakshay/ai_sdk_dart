import 'dart:convert';

import 'ast.dart';
import 'js.dart';

typedef JsonSchema = Map<String, Object?>;

/// Marks a value that failed validation with no default to fall back on.
const Object invalid = _Sentinel('invalid');

/// Marks a missing value (JavaScript `undefined`), distinct from `null`.
const Object absent = _Sentinel('absent');

final class _Sentinel {
  const _Sentinel(this.name);
  final String name;
  @override
  String toString() => name;
}

enum ValidationCode {
  missingRequired('missing-required'),
  nullRequired('null-required'),
  unknownComponent('unknown-component'),
  inlineReserved('inline-reserved'),
  excessArgs('excess-args'),
  typeMismatch('type-mismatch'),
  unknownFunction('unknown-function'),
  noRoot('no-root');

  const ValidationCode(this.wire);
  final String wire;
}

final class ValidationError {
  const ValidationError({
    required this.code,
    required this.component,
    required this.path,
    required this.message,
    this.statementId,
    this.isWarning = false,
  });

  final ValidationCode code;
  final String component;
  final String path;
  final String message;
  final String? statementId;
  final bool isWarning;

  @override
  String toString() => message;
}

/// One positional parameter compiled from a JSON Schema `properties` entry.
final class ParamDef {
  const ParamDef({
    required this.name,
    required this.required,
    required this.schema,
    this.defaultValue = absent,
  });
  final String name;
  final bool required;
  final Object? schema;

  /// The schema `default`, or [absent].
  final Object? defaultValue;
}

/// The mutable state validation and materialization report into.
class ValidationContext {
  ValidationContext({this.partial = false, this.componentNames});
  final List<ValidationError> errors = [];
  final bool partial;
  final Set<String>? componentNames;
  String? currentStatementId;
}

String _jsonValue(Object? v) => v is num ? Js.numberToString(v) : jsonEncode(v);

String _jsType(Object? value) => value is List ? 'array' : Js.typeOf(value);

String? _refName(Map s) {
  final ref = s[r'$ref'];
  return ref is String ? ref.split('/').last : null;
}

bool _isComposite(Map s) =>
    s.containsKey(r'$ref') ||
    s.containsKey('anyOf') ||
    s.containsKey('oneOf') ||
    s.containsKey('allOf');

({List<Object?>? enumValues, String? expectedType}) _scalarInfo(Map s) {
  final e = s['enum'];
  if (e is List) return (enumValues: e, expectedType: null);
  if (s.containsKey('const')) {
    return (enumValues: [s['const']], expectedType: null);
  }
  return (
    enumValues: null,
    expectedType: switch (s['type']) {
      'string' => 'string',
      'number' || 'integer' => 'number',
      'boolean' => 'boolean',
      _ => null,
    },
  );
}

Object? schemaDefault(Object? property) =>
    property is Map && property.containsKey('default')
    ? property['default']
    : absent;

String? _typeFromSchema(Object? property) {
  if (property is! Map) return null;
  final ref = _refName(property);
  if (ref != null) return ref;
  final leaf = _scalarInfo(property);
  if (leaf.enumValues != null) {
    return leaf.enumValues!.map(_jsonValue).join('|');
  }
  if (leaf.expectedType != null) return leaf.expectedType;
  final t = property['type'];
  return t is String ? t : null;
}

/// `Header(title*: string, variant: "a"|"b")`, `*` marking required params.
String buildParamsSignature(String component, List<ParamDef> params) {
  final parts = params.map((p) {
    final type = _typeFromSchema(p.schema);
    final marked = p.required ? '${p.name}*' : p.name;
    return type != null ? '$marked: $type' : marked;
  });
  return '$component(${parts.join(', ')})';
}

sealed class Issue {
  const Issue(this.code);
  final ValidationCode code;
}

final class TypeMismatch extends Issue {
  const TypeMismatch(this.expected, this.actual)
    : super(ValidationCode.typeMismatch);
  final String expected;
  final String actual;
}

final class Missing extends Issue {
  const Missing({required bool present, this.signature})
    : super(
        present ? ValidationCode.nullRequired : ValidationCode.missingRequired,
      );
  final String? signature;
}

final class UnknownComponent extends Issue {
  const UnknownComponent(this.available)
    : super(ValidationCode.unknownComponent);
  final List<String>? available;
}

final class InlineReserved extends Issue {
  const InlineReserved() : super(ValidationCode.inlineReserved);
}

final class ExcessArgs extends Issue {
  const ExcessArgs(this.declared, this.got) : super(ValidationCode.excessArgs);
  final int declared;
  final int got;
}

final class UnknownFunction extends Issue {
  const UnknownFunction() : super(ValidationCode.unknownFunction);
}

enum NoRootReason { missing, notComponent, fallback }

final class NoRoot extends Issue {
  const NoRoot(this.reason) : super(ValidationCode.noRoot);
  final NoRootReason reason;
}

String _message(String component, String path, Issue issue) => switch (issue) {
  TypeMismatch(:final expected, :final actual) =>
    'field "$path" expects $expected but got $actual',
  Missing(:final code, :final signature) =>
    '${code == ValidationCode.nullRequired ? 'required field "$path" cannot be null' : 'missing required field "$path"'}'
        '${signature != null ? ' — signature: $signature' : ''}',
  UnknownComponent(:final available) =>
    'Unknown component "$component" — not found in catalog or builtins'
        '${available != null && available.isNotEmpty ? '. Available components: ${available.join(', ')}' : ''}',
  InlineReserved() =>
    '$component() must be declared as a top-level statement, not used inline as a value',
  ExcessArgs(:final declared, :final got) =>
    '$component takes $declared arg(s), got $got (${got - declared} excess dropped)',
  UnknownFunction() =>
    'Unknown function "@$component": not a built-in or action step. The call evaluates to null',
  NoRoot(:final reason) => switch (reason) {
    NoRootReason.notComponent => 'root does not evaluate to a component',
    NoRootReason.fallback =>
      'No root statement. Rendering the first statement that calls the root component $component',
    NoRootReason.missing =>
      component.isNotEmpty
          ? 'No root statement, and no statement calls the root component $component'
          : 'No root statement',
  },
};

void pushIssue(
  ValidationContext ctx,
  String component,
  String path,
  Issue issue,
) {
  ctx.errors.add(
    ValidationError(
      code: issue.code,
      component: component,
      path: path,
      message: _message(component, path, issue),
      statementId: ctx.currentStatementId,
      isWarning: issue is NoRoot && issue.reason == NoRootReason.fallback,
    ),
  );
}

Object? resolveInvalidValue(bool required, Object? defaultValue) {
  if (!identical(defaultValue, absent)) return defaultValue;
  return required ? invalid : absent;
}

bool _validateElementPosition(
  ElementNode element,
  Map s,
  String component,
  String path,
  ValidationContext ctx,
) {
  if (_isComposite(s)) return false;
  final type = s['type'];
  if (type is String || s['enum'] is List || s.containsKey('const')) {
    pushIssue(
      ctx,
      component,
      path,
      TypeMismatch(
        type is String ? type : 'a literal value',
        'component "${element.typeName}"',
      ),
    );
    return true;
  }
  return false;
}

List<String?> _slotRefNames(Map s) {
  final options = s['anyOf'] ?? s['oneOf'];
  return [
    for (final o in options is List ? options : [s])
      o is Map ? _refName(o) : null,
  ];
}

bool _isOnlyComponentSlot(Map s, ValidationContext ctx) {
  final names = _slotRefNames(s);
  return names.isNotEmpty &&
      names.every(
        (n) => n != null && (ctx.componentNames?.contains(n) ?? false),
      );
}

Object? _validateObject(
  Object? value,
  Map s,
  String component,
  String path,
  ValidationContext ctx,
) {
  if (value is! Map<String, Object?>) {
    pushIssue(ctx, component, path, TypeMismatch('object', _jsType(value)));
    return invalid;
  }
  Map<String, Object?>? out;
  final props = s['properties'] is Map ? s['properties'] as Map : const {};
  final required = s['required'] is List ? s['required'] as List : const [];
  var isInvalid = false;
  if (!ctx.partial) {
    for (final key in required.cast<String>()) {
      final present = value.containsKey(key);
      if (!present || value[key] == null) {
        final fallback = schemaDefault(props[key]);
        if (!identical(fallback, absent)) {
          (out ??= {...value})[key] = fallback;
          continue;
        }
        pushIssue(ctx, component, '$path/$key', Missing(present: present));
        isInvalid = true;
      }
    }
  }
  for (final key in props.keys.cast<String>()) {
    if (!value.containsKey(key)) continue;
    final sub = props[key];
    var next = validateSchemaValue(
      value[key],
      sub,
      component,
      '$path/$key',
      ctx,
    );
    if (identical(next, invalid)) {
      next = resolveInvalidValue(required.contains(key), schemaDefault(sub));
      if (identical(next, invalid)) {
        isInvalid = true;
        continue;
      }
    }
    if (identical(next, value[key])) continue;
    out ??= {...value};
    if (identical(next, absent)) {
      out.remove(key);
    } else {
      out[key] = next;
    }
  }
  return isInvalid ? invalid : (out == null ? value : Js.ordered(out));
}

Object? _validateArray(
  Object? value,
  Map s,
  String component,
  String path,
  ValidationContext ctx,
) {
  if (value is! List<Object?>) {
    pushIssue(ctx, component, path, TypeMismatch('array', _jsType(value)));
    return invalid;
  }
  final items = s['items'];
  if (items is! Map) return value;
  List<Object?>? out;
  for (var i = 0; i < value.length; i++) {
    final next = validateSchemaValue(
      value[i],
      items,
      component,
      '$path/$i',
      ctx,
    );
    if (!identical(next, value[i]) && out == null) out = value.sublist(0, i);
    if (out != null && !identical(next, invalid)) out.add(next);
  }
  return out ?? value;
}

bool _validateLeaf(
  Object? value,
  Map s,
  String component,
  String path,
  ValidationContext ctx,
) {
  final leaf = _scalarInfo(s);
  if (leaf.expectedType == null && leaf.enumValues == null) return false;
  if (leaf.enumValues != null && ctx.partial) return false;
  final actual = Js.typeOf(value);
  TypeMismatch? mismatch;
  if (leaf.enumValues != null) {
    if (const ['string', 'number', 'boolean'].contains(actual) &&
        !leaf.enumValues!.any((e) => Js.strictEquals(e, value))) {
      mismatch = TypeMismatch(
        'one of [${leaf.enumValues!.map(_jsonValue).join(', ')}]',
        _jsonValue(value),
      );
    }
  } else if (leaf.expectedType != actual) {
    mismatch = TypeMismatch(leaf.expectedType!, _jsType(value));
  }
  if (mismatch == null) return false;
  pushIssue(ctx, component, path, mismatch);
  return true;
}

/// lang-core `validateSchemaValue`: checks a materialized value against a
/// JSON Schema fragment. Returns the value, a cleaned copy, or [invalid].
Object? validateSchemaValue(
  Object? value,
  Object? schema,
  String component,
  String path,
  ValidationContext ctx,
) {
  if (schema is! Map) return value;
  if (value == null) return value;
  if (value is Ast) return value;
  if (value is ElementNode) {
    return _validateElementPosition(value, schema, component, path, ctx)
        ? invalid
        : value;
  }
  if (_isComposite(schema)) {
    if (!_isOnlyComponentSlot(schema, ctx)) return value;
    pushIssue(
      ctx,
      component,
      path,
      TypeMismatch(
        _slotRefNames(schema).join(' | '),
        value is List
            ? 'array'
            : value is Map
            ? 'plain object'
            : Js.typeOf(value),
      ),
    );
    return invalid;
  }
  return switch (schema['type']) {
    'object' => _validateObject(value, schema, component, path, ctx),
    'array' => _validateArray(value, schema, component, path, ctx),
    _ => _validateLeaf(value, schema, component, path, ctx) ? invalid : value,
  };
}
