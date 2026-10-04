import 'dart:collection';

import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:test/test.dart';

void main() {
  test('maxNodes bounds traversal before a wide value is fully enumerated', () {
    const maxNodes = 8;
    final wide = _CountingList(2048);
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: const {'type': 'object'},
      fromJson: (json) => json,
      maxNodes: maxNodes,
    );

    expect(schema.validator!.validate({'items': wide}), isNotEmpty);
    expect(
      wide.readCount,
      lessThanOrEqualTo(maxNodes),
      reason:
          'the node budget should stop traversal before visiting every '
          'sibling in the oversized list',
    );
  });

  test('maxNodes bounds key traversal through an oversized map', () {
    const maxNodes = 8;
    final wide = _CountingMap(2048);
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: const {'type': 'object'},
      fromJson: (json) => json,
      maxNodes: maxNodes,
    );

    expect(schema.validator!.validate(wide), isNotEmpty);
    expect(
      wide.keyReadCount,
      lessThanOrEqualTo(maxNodes + 1),
      reason: 'key validation should stop at the node budget',
    );
  });

  test('accepts a value whose node count exactly reaches maxNodes', () {
    final schema = validatedJsonSchema<Map<String, dynamic>>(
      schema: const {'type': 'object'},
      fromJson: (json) => json,
      maxNodes: 8,
    );

    expect(
      schema.validator!.validate({
        'a': 1,
        'b': 2,
        'c': 3,
        'd': 4,
        'e': 5,
        'f': 6,
        'g': 7,
      }),
      isEmpty,
    );
  });
}

class _CountingList extends ListBase<Object?> {
  _CountingList(this.length);

  @override
  final int length;

  var readCount = 0;

  @override
  Object? operator [](int index) {
    readCount++;
    return index;
  }

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('read-only test input');
  }

  @override
  set length(int value) {
    throw UnsupportedError('read-only test input');
  }
}

class _CountingMap extends MapBase<String, dynamic> {
  _CountingMap(int size) : _keys = List.generate(size, (i) => 'key-$i');

  final List<String> _keys;
  var keyReadCount = 0;

  @override
  Iterable<String> get keys sync* {
    for (final key in _keys) {
      keyReadCount++;
      yield key;
    }
  }

  @override
  dynamic operator [](Object? key) => 0;

  @override
  void operator []=(String key, dynamic value) =>
      throw UnsupportedError('read-only test input');

  @override
  void clear() => throw UnsupportedError('read-only test input');

  @override
  dynamic remove(Object? key) => throw UnsupportedError('read-only test input');
}
