import 'js.dart';

/// The OpenUI Lang 1.0 syntax tree, mirroring lang-core's `ASTNode`.
sealed class Ast implements JsFields {
  const Ast();

  /// lang-core's object for this node, such as `{k: "Num", v: 1}`.
  @override
  Map<String, Object?> get jsFields => switch (this) {
    StrNode(:final value) => {'k': 'Str', 'v': value},
    NumNode(:final value) => {'k': 'Num', 'v': value},
    BoolNode(:final value) => {'k': 'Bool', 'v': value},
    NullNode() => {'k': 'Null'},
    ArrNode(:final elements) => {'k': 'Arr', 'els': elements},
    ObjNode(:final entries) => {
      'k': 'Obj',
      'entries': [
        for (final (k, v) in entries) <Object?>[k, v],
      ],
    },
    CompNode(:final name, :final args, :final mappedProps, :final isAtCall) => {
      'k': 'Comp',
      'name': name,
      'args': args,
      'mappedProps': ?mappedProps,
      if (isAtCall) 'fn': true,
    },
    RefNode(:final name) => {'k': 'Ref', 'n': name},
    StateRefNode(:final name) => {'k': 'StateRef', 'n': name},
    RuntimeRefNode(:final name, :final refType) => {
      'k': 'RuntimeRef',
      'n': name,
      'refType': refType.name,
    },
    BinOpNode(:final op, :final left, :final right) => {
      'k': 'BinOp',
      'op': op,
      'left': left,
      'right': right,
    },
    UnaryOpNode(:final op, :final operand) => {
      'k': 'UnaryOp',
      'op': op,
      'operand': operand,
    },
    TernaryNode(:final condition, :final then, :final otherwise) => {
      'k': 'Ternary',
      'cond': condition,
      'then': then,
      'else': otherwise,
    },
    MemberNode(:final object, :final field) => {
      'k': 'Member',
      'obj': object,
      'field': field,
    },
    IndexNode(:final object, :final index) => {
      'k': 'Index',
      'obj': object,
      'index': index,
    },
    AssignNode(:final target, :final value) => {
      'k': 'Assign',
      'target': target,
      'value': value,
    },
    PlaceholderNode(:final name) => {'k': 'Ph', 'n': name},
    // Port-only: a runtime value spliced into an @Each template.
    ValueNode(:final value) => {'k': 'Value', 'v': value},
  };
}

final class StrNode extends Ast {
  const StrNode(this.value);
  final String value;
}

final class NumNode extends Ast {
  const NumNode(this.value);
  final num value;
}

final class BoolNode extends Ast {
  const BoolNode(this.value);
  final bool value;
}

final class NullNode extends Ast {
  const NullNode();
}

final class ArrNode extends Ast {
  const ArrNode(this.elements);
  final List<Ast> elements;
}

final class ObjNode extends Ast {
  const ObjNode(this.entries);
  final List<(String, Ast)> entries;
}

/// A call: a component, a built-in or library `@function`, an action step,
/// `Action([...])`, `Query` or `Mutation`.
final class CompNode extends Ast {
  CompNode(this.name, this.args, {this.mappedProps, this.isAtCall = false});
  final String name;
  final List<Ast> args;

  /// Positional args named by the schema; filled during materialization.
  Map<String, Ast>? mappedProps;

  /// Written with a leading `@` and not a built-in.
  final bool isAtCall;

  CompNode copyWith({List<Ast>? args, Map<String, Ast>? mappedProps}) =>
      CompNode(
        name,
        args ?? this.args,
        mappedProps: mappedProps ?? this.mappedProps,
        isAtCall: isAtCall,
      );
}

/// A reference to another statement, or an `@Each` loop variable.
final class RefNode extends Ast {
  const RefNode(this.name);
  final String name;
}

final class StateRefNode extends Ast {
  const StateRefNode(this.name);
  final String name;
}

enum RuntimeRefType { query, mutation }

final class RuntimeRefNode extends Ast {
  const RuntimeRefNode(this.name, this.refType);
  final String name;
  final RuntimeRefType refType;
}

final class BinOpNode extends Ast {
  const BinOpNode(this.op, this.left, this.right);
  final String op;
  final Ast left;
  final Ast right;
}

final class UnaryOpNode extends Ast {
  const UnaryOpNode(this.op, this.operand);
  final String op;
  final Ast operand;
}

final class TernaryNode extends Ast {
  const TernaryNode(this.condition, this.then, this.otherwise);
  final Ast condition;
  final Ast then;
  final Ast otherwise;
}

final class MemberNode extends Ast {
  const MemberNode(this.object, this.field);
  final Ast object;
  final String field;
}

final class IndexNode extends Ast {
  const IndexNode(this.object, this.index);
  final Ast object;
  final Ast index;
}

final class AssignNode extends Ast {
  const AssignNode(this.target, this.value);
  final String target;
  final Ast value;
}

/// A placeholder for a reference that did not resolve (yet).
final class PlaceholderNode extends Ast {
  const PlaceholderNode(this.name);
  final String name;
}

/// A runtime value spliced into an `@Each` template that has no literal form (a component, an action, a
/// binding); it evaluates to itself.
final class ValueNode extends Ast {
  const ValueNode(this.value);
  final Object? value;
}

bool isRuntimeExpr(Ast node) => switch (node) {
  StateRefNode() ||
  RuntimeRefNode() ||
  BinOpNode() ||
  UnaryOpNode() ||
  TernaryNode() ||
  MemberNode() ||
  IndexNode() ||
  AssignNode() => true,
  _ => false,
};

void walkAst(Ast node, void Function(Ast node) visit) {
  visit(node);
  switch (node) {
    case CompNode():
      for (final a in node.args) {
        walkAst(a, visit);
      }
      for (final a in node.mappedProps?.values ?? const <Ast>[]) {
        walkAst(a, visit);
      }
    case ArrNode():
      for (final e in node.elements) {
        walkAst(e, visit);
      }
    case ObjNode():
      for (final (_, v) in node.entries) {
        walkAst(v, visit);
      }
    case BinOpNode():
      walkAst(node.left, visit);
      walkAst(node.right, visit);
    case UnaryOpNode():
      walkAst(node.operand, visit);
    case TernaryNode():
      walkAst(node.condition, visit);
      walkAst(node.then, visit);
      walkAst(node.otherwise, visit);
    case MemberNode():
      walkAst(node.object, visit);
    case IndexNode():
      walkAst(node.object, visit);
      walkAst(node.index, visit);
    case AssignNode():
      walkAst(node.value, visit);
    default:
  }
}

Ast literalAst(Object? value) => switch (value) {
  null => const NullNode(),
  String() => StrNode(value),
  num() => NumNode(value),
  bool() => BoolNode(value),
  List() => ArrNode([for (final v in value) literalAst(v)]),
  Map() => ObjNode([
    for (final MapEntry(:key, value: v) in value.entries)
      ('$key', literalAst(v)),
  ]),
  _ => ValueNode(value),
};

/// The literal value of a node, or `(found: false)` when it is not a literal.
({bool found, Object? value}) literalValue(Ast node) {
  switch (node) {
    case StrNode(:final value):
      return (found: true, value: value);
    case NumNode(:final value):
      return (found: true, value: value);
    case BoolNode(:final value):
      return (found: true, value: value);
    case NullNode():
      return (found: true, value: null);
    case ArrNode(:final elements):
      final out = <Object?>[];
      for (final e in elements) {
        final lit = literalValue(e);
        if (!lit.found) return (found: false, value: null);
        out.add(lit.value);
      }
      return (found: true, value: out);
    case ObjNode(:final entries):
      final out = <MapEntry<String, Object?>>[];
      for (final (k, e) in entries) {
        final lit = literalValue(e);
        if (!lit.found) return (found: false, value: null);
        out.add(MapEntry(k, lit.value));
      }
      return (found: true, value: Js.object(out));
    default:
      return (found: false, value: null);
  }
}

/// A component instance after materialization or evaluation.
final class ElementNode implements JsFields {
  ElementNode({
    required this.typeName,
    required this.props,
    required this.partial,
    required this.hasDynamicProps,
    this.statementId,
  });

  final String typeName;
  final Map<String, Object?> props;
  final bool partial;
  final bool hasDynamicProps;
  String? statementId;

  /// lang-core's `ElementNode` object.
  @override
  Map<String, Object?> get jsFields => {
    'type': 'element',
    'typeName': typeName,
    'props': props,
    'partial': partial,
    'hasDynamicProps': hasDynamicProps,
    'statementId': ?statementId,
  };

  ElementNode withProps(Map<String, Object?> props) => ElementNode(
    typeName: typeName,
    props: props,
    partial: partial,
    hasDynamicProps: hasDynamicProps,
    statementId: statementId,
  );
}
