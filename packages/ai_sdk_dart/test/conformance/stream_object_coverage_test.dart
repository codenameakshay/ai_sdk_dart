import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Drives the JSON-Patch diff machinery in `streamObject.patchStream` (key
/// add/remove, list element add/remove/replace, scalar replace) plus the
/// fenced-JSON and nested-map parsing helpers.
void main() {
  final schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  /// Emits a sequence of complete JSON object snapshots. Because
  /// `_extractLastJsonObject` keeps the last complete top-level `{...}`, each
  /// snapshot becomes a successful parse and is diffed against the previous.
  FakeStreamModel snapshots(List<String> jsonSnapshots) {
    return FakeStreamModel([
      const StreamPartTextStart(id: 't1'),
      for (final snap in jsonSnapshots)
        StreamPartTextDelta(id: 't1', delta: snap),
      const StreamPartTextEnd(id: 't1'),
      StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
    ]);
  }

  group('streamObject patch diffing', () {
    test('adds a new key between snapshots', () async {
      final model = snapshots(['{"a":1}', '{"a":1,"b":2}']);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final patches = await result.patchStream.toList();
      // First batch: root replace. Later batches: 'add' op for new key 'b'.
      final ops = patches.expand((b) => b).toList();
      expect(ops.any((o) => o.op == 'add' && o.path == '/b'), isTrue);
      expect(await result.object, {'a': 1, 'b': 2});
    });

    test('removes a key between snapshots', () async {
      final model = snapshots(['{"a":1,"b":2}', '{"a":1}']);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final ops = (await result.patchStream.toList()).expand((b) => b).toList();
      expect(ops.any((o) => o.op == 'remove' && o.path == '/b'), isTrue);
    });

    test('replaces a scalar value between snapshots', () async {
      final model = snapshots(['{"a":1}', '{"a":2}']);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final ops = (await result.patchStream.toList()).expand((b) => b).toList();
      expect(
        ops.any((o) => o.op == 'replace' && o.path == '/a' && o.value == 2),
        isTrue,
      );
    });

    test('diffs nested lists: element replace, add, and remove', () async {
      // List grows (add), an element changes (replace), then shrinks (remove).
      final model = snapshots([
        '{"xs":[1,2]}',
        '{"xs":[1,9,3]}',
        '{"xs":[1]}',
      ]);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final ops = (await result.patchStream.toList()).expand((b) => b).toList();
      // Snapshot 2 vs 1: index 1 replaced (2 -> 9), index 2 added (3).
      expect(
        ops.any((o) => o.op == 'replace' && o.path == '/xs/1' && o.value == 9),
        isTrue,
      );
      expect(ops.any((o) => o.op == 'add' && o.path == '/xs/2'), isTrue);
      // Snapshot 3 vs 2: indices 1 and 2 removed.
      expect(ops.any((o) => o.op == 'remove' && o.path.startsWith('/xs/')),
          isTrue);
      expect(await result.object, {
        'xs': [1],
      });
    });

    test('diffs nested maps recursively', () async {
      final model = snapshots([
        '{"o":{"a":1}}',
        '{"o":{"a":1,"b":2}}',
      ]);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final ops = (await result.patchStream.toList()).expand((b) => b).toList();
      expect(ops.any((o) => o.op == 'add' && o.path == '/o/b'), isTrue);
    });

    test('no patch emitted when an identical snapshot repeats', () async {
      final model = snapshots([
        '{"a":1,"list":[1,2],"obj":{"x":1}}',
        '{"a":1,"list":[1,2],"obj":{"x":1}}',
      ]);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      final batches = await result.patchStream.toList();
      // Only the initial root replace; the identical repeat produces no patch.
      expect(batches, hasLength(1));
      expect(await result.object, {
        'a': 1,
        'list': [1, 2],
        'obj': {'x': 1},
      });
    });
  });

  group('streamObject JSON parsing helpers', () {
    test('parses a fenced JSON object', () async {
      final model = snapshots(['```json\n{"a":1}\n```']);
      final result = await streamObject(
        model: model,
        schema: schema,
        prompt: 'json',
      );
      expect(await result.object, {'a': 1});
    });
  });
}
