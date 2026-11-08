/// A Zod-shaped schema DSL. One schema node yields both the JSON Schema the
/// parser validates against and the type annotation the prompt prints.
sealed class Schema {
  const Schema({
    this.isOptional = false,
    this.isReactive = false,
    this.tagName,
    this.isNullable = false,
  });

  final bool isOptional;

  /// Zod `.nullable()`: also accepts null; the prompt marks it optional.
  final bool isNullable;

  /// A `$binding` prop: the prompt prints `$binding<T>`, and a `$variable`
  /// passed here binds two ways instead of passing its value.
  final bool isReactive;

  /// The prompt-only type name (`Color`, `Node`, `Length`), like `tagSchemaId`.
  final String? tagName;

  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  });

  Schema optional() => _copy(isOptional: true);
  Schema nullable() => _copy(isNullable: true);
  Schema reactive() => _copy(isReactive: true);
  Schema tag(String name) => _copy(tagName: name);
}

abstract final class S {
  static Schema string() => const _Prim('string');
  static Schema number() => const _Prim('number');
  static Schema boolean() => const _Prim('boolean');
  static Schema any() => const _Any();
  static Schema literal(String value) => _Literal(value);
  static Schema oneOf(List<String> values) => _Enum(values);
  static Schema list(Schema item) => _List(item);
  static Schema union(List<Schema> options) => _Union(options);
  static Schema object(Map<String, Schema> shape) => _Object(shape);
  static Schema record(Schema key, Schema value) => _Record(key, value);

  /// A reference to a component, emitted as `$ref` into `$defs`.
  static Schema ref(String component) => _Ref(component);
}

final class _Prim extends Schema {
  const _Prim(
    this.type, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final String type;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Prim(
    type,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Any extends Schema {
  const _Any({
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Any(
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Literal extends Schema {
  const _Literal(
    this.value, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final String value;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Literal(
    value,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Enum extends Schema {
  const _Enum(
    this.values, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final List<String> values;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Enum(
    values,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _List extends Schema {
  const _List(
    this.item, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final Schema item;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _List(
    item,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Union extends Schema {
  const _Union(
    this.options, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final List<Schema> options;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Union(
    options,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Object extends Schema {
  const _Object(
    this.shape, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final Map<String, Schema> shape;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Object(
    shape,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Record extends Schema {
  const _Record(
    this.key,
    this.value, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final Schema key;
  final Schema value;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Record(
    key,
    value,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

final class _Ref extends Schema {
  const _Ref(
    this.name, {
    super.isOptional,
    super.isReactive,
    super.tagName,
    super.isNullable,
  });
  final String name;
  @override
  Schema _copy({
    bool? isOptional,
    bool? isReactive,
    String? tagName,
    bool? isNullable,
  }) => _Ref(
    name,
    isOptional: isOptional ?? this.isOptional,
    isReactive: isReactive ?? this.isReactive,
    tagName: tagName ?? this.tagName,
    isNullable: isNullable ?? this.isNullable,
  );
}

/// Emits Zod v4 `toJSONSchema` output. [defs] collects referenced
/// definitions in first-seen order; [resolveRef] supplies a ref's body.
final class JsonSchemaEmitter {
  JsonSchemaEmitter(this.resolveRef);
  final Map<String, Object?> Function(String name) resolveRef;
  final Map<String, Object?> defs = {};

  Map<String, Object?> emit(Schema s) {
    final body = _emit(s);
    if (!s.isNullable) return body;
    if (body.length == 1 && body['type'] is String) {
      return {
        'type': [body['type'], 'null'],
      };
    }
    return {
      'anyOf': [
        body,
        {'type': 'null'},
      ],
    };
  }

  Map<String, Object?> _emit(Schema s) => switch (s) {
    _Prim(:final type) => {'type': type},
    _Any() => {},
    _Literal(:final value) => {'type': 'string', 'const': value},
    _Enum(:final values) => {'type': 'string', 'enum': values},
    _List(:final item) => {'type': 'array', 'items': emit(item)},
    _Union(:final options) => _union(options),
    _Object(:final shape) => emitObject(shape),
    _Record(:final key, :final value) => {
      'type': 'object',
      'propertyNames': emit(key),
      'additionalProperties': emit(value),
    },
    _Ref(:final name) => _ref(name),
  };

  Map<String, Object?> emitObject(Map<String, Schema> shape) {
    final required = [
      for (final MapEntry(:key, :value) in shape.entries)
        if (!value.isOptional) key,
    ];
    return {
      'type': 'object',
      'properties': {
        for (final MapEntry(:key, :value) in shape.entries) key: emit(value),
      },
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
    };
  }

  Map<String, Object?> _union(List<Schema> options) {
    final emitted = options.map(emit).toList();
    final plain = emitted.every((e) => e.length == 1 && e['type'] is String);
    if (plain) {
      return {
        'type': [for (final e in emitted) e['type']],
      };
    }
    return {'anyOf': emitted};
  }

  Map<String, Object?> _ref(String name) {
    if (!defs.containsKey(name)) {
      defs[name] = null;
      defs[name] = resolveRef(name);
    }
    return {r'$ref': '#/\$defs/$name'};
  }
}

/// lang-core `resolveTypeAnnotation`: the type a prompt signature prints.
String typeAnnotation(Schema s) {
  final base = _baseType(s);
  return s.isReactive ? '\$binding<$base>' : base;
}

String _baseType(Schema s) {
  if (s.tagName != null) return s.tagName!;
  return switch (s) {
    _Ref(:final name) => name,
    _Union(:final options) => options.map(typeAnnotation).join(' | '),
    _List(:final item) =>
      item is _Union && item.tagName == null
          ? '(${typeAnnotation(item)})[]'
          : '${typeAnnotation(item)}[]',
    _Prim(:final type) => type,
    _Any() => 'any',
    _Record(:final key, :final value) =>
      'Record<${typeAnnotation(key)}, ${typeAnnotation(value)}>',
    _Enum(:final values) => values.map((v) => '"$v"').join(' | '),
    _Literal(:final value) => '"$value"',
    _Object(:final shape) =>
      '{${shape.entries.map((e) => '${e.key}${e.value.isOptional || e.value.isNullable ? '?' : ''}: ${typeAnnotation(e.value)}').join(', ')}}',
  };
}

/// `Name(a: T, b?: U)`, plus ` → R` when a return type is given.
String signature(String name, Map<String, Schema> params, [Schema? returns]) {
  final fields = params.entries
      .map(
        (e) =>
            '${e.key}${e.value.isOptional || e.value.isNullable ? '?' : ''}: ${typeAnnotation(e.value)}',
      )
      .join(', ');
  final sig = '$name($fields)';
  return returns == null ? sig : '$sig → ${typeAnnotation(returns)}';
}
