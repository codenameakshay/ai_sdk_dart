import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  final schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  // Real streamed text only ever grows, so each case pads the object with a
  // long leading field to push the partial-parse tracker past its first
  // checkpoint, then splits the payload where the interesting change lands.
  const pad = '"pad":"0123456789ABCDEF"';

  FakeStreamModel splitAt(String text, String prefix) => textDeltaStream([
    text.substring(0, prefix.length),
    text.substring(prefix.length),
  ]);

  for (final fixture
      in <
        ({
          String name,
          String text,
          String prefix,
          Map<String, dynamic> value,
          void Function(List<StreamObjectPatchOperation> ops) assertOps,
        })
      >[
        (
          name: 'adds a new key',
          text: '{$pad,"a":1,"b":2}',
          prefix: '{$pad,"a":1',
          value: {'pad': '0123456789ABCDEF', 'a': 1, 'b': 2},
          assertOps: (ops) => expect(
            ops.any((o) => o.op == 'add' && o.path == '/b' && o.value == 2),
            isTrue,
          ),
        ),
        (
          // A key can only be removed by later overriding it via a duplicate
          // top-level key, since a real stream never un-writes characters.
          name: 'removes a key',
          text: '{$pad,"o":{"a":1,"b":2},"o":{"a":1}}',
          prefix: '{$pad,"o":{"a":1,"b":2}',
          value: {
            'pad': '0123456789ABCDEF',
            'o': {'a': 1},
          },
          assertOps: (ops) => expect(
            ops.any((o) => o.op == 'remove' && o.path == '/o/b'),
            isTrue,
          ),
        ),
        (
          name: 'replaces a scalar',
          text: '{$pad,"a":1,"a":2}',
          prefix: '{$pad,"a":1',
          value: {'pad': '0123456789ABCDEF', 'a': 2},
          assertOps: (ops) => expect(
            ops.any((o) => o.op == 'replace' && o.path == '/a' && o.value == 2),
            isTrue,
          ),
        ),
        (
          name: 'diffs nested lists',
          text: '{$pad,"xs":[1,19,3]}',
          prefix: '{$pad,"xs":[1,1',
          value: {
            'pad': '0123456789ABCDEF',
            'xs': [1, 19, 3],
          },
          assertOps: (ops) {
            expect(
              ops.any(
                (o) => o.op == 'replace' && o.path == '/xs/1' && o.value == 19,
              ),
              isTrue,
            );
            expect(ops.any((o) => o.op == 'add' && o.path == '/xs/2'), isTrue);
          },
        ),
        (
          name: 'diffs nested maps',
          text: '{$pad,"o":{"a":1,"b":2}}',
          prefix: '{$pad,"o":{"a":1',
          value: {
            'pad': '0123456789ABCDEF',
            'o': {'a': 1, 'b': 2},
          },
          assertOps: (ops) =>
              expect(ops.any((o) => o.op == 'add' && o.path == '/o/b'), isTrue),
        ),
      ]) {
    test('streamObject patch diffing ${fixture.name}', () async {
      final result = await streamObject(
        model: splitAt(fixture.text, fixture.prefix),
        schema: schema,
        prompt: 'json',
      );
      final ops = (await result.patchStream.toList())
          .expand((batch) => batch)
          .toList();
      fixture.assertOps(ops);
      expect(await result.object, fixture.value);
    });
  }

  test('identical complete output yields one immutable root patch', () async {
    const text = '{"a":1,"list":[1,2],"obj":{"x":1}}';
    final result = await streamObject(
      model: splitAt(text, text.substring(0, text.length - 2)),
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
      model: textDeltaStream(['```json\n{"a":1}\n```']),
      schema: schema,
      prompt: 'json',
    );
    expect(await result.object, {'a': 1});
  });
}
