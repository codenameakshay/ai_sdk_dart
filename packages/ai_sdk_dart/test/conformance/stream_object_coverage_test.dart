import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  final schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );
  final snapshots = textDeltaStream;

  for (final fixture
      in <({String name, String text, Map<String, dynamic> value})>[
        (
          name: 'adds a new key',
          text: '{"a":1,"b":2}',
          value: {'a': 1, 'b': 2},
        ),
        (name: 'removes a key', text: '{"a":1}', value: {'a': 1}),
        (name: 'replaces a scalar', text: '{"a":2}', value: {'a': 2}),
        (
          name: 'diffs nested lists',
          text: '{"xs":[1,9,3]}',
          value: {
            'xs': [1, 9, 3],
          },
        ),
        (
          name: 'diffs nested maps',
          text: '{"o":{"a":1,"b":2}}',
          value: {
            'o': {'a': 1, 'b': 2},
          },
        ),
      ]) {
    test('streamObject patch diffing ${fixture.name}', () async {
      final result = await streamObject(
        model: snapshots([fixture.text]),
        schema: schema,
        prompt: 'json',
      );
      final patches = await result.patchStream.toList();
      expect(patches, hasLength(1));
      expect(patches.single.single.path, isEmpty);
      expect(await result.object, fixture.value);
    });
  }

  test('identical complete output yields one immutable root patch', () async {
    final result = await streamObject(
      model: snapshots(['{"a":1,"list":[1,2],"obj":{"x":1}}']),
      schema: schema,
      prompt: 'json',
    );
    final patches = await result.patchStream.toList();
    expect(patches, hasLength(1));
    expect(await result.object, {
      'a': 1,
      'list': [1, 2],
      'obj': {'x': 1},
    });
  });

  test('parses a fenced JSON object', () async {
    final result = await streamObject(
      model: snapshots(['```json\n{"a":1}\n```']),
      schema: schema,
      prompt: 'json',
    );
    expect(await result.object, {'a': 1});
  });
}
