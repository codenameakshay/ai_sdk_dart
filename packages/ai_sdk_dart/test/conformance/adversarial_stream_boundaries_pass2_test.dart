import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

const _seed = 0x51A7E;

void main() {
  final schema = Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  );

  final payloads = <String>[
    jsonEncode({
      'title': 'astral 😀 at a boundary',
      'nested': {
        'items': [
          {'text': 'quote: "x", slash: \\', 'active': true},
          {'text': 'second line\nwith tab\t and null', 'active': false},
        ],
      },
    }),
    r'{"unicode":"\uD83D\uDE00","slashes":"\\\\","empty":[],"nil":null,"n":-12.5e+2}',
    '```json\n{"emoji":"🚀","deep":{"a":[1,{"b":"escaped \\"quote\\""}]}}\n```',
  ];

  test(
    'every two-way split and seeded chunking preserve stream semantics',
    () async {
      final cases = <({String payload, List<String> chunks, String label})>[];
      for (
        var payloadIndex = 0;
        payloadIndex < payloads.length;
        payloadIndex++
      ) {
        final payload = payloads[payloadIndex];
        for (var offset = 1; offset < payload.length; offset++) {
          cases.add((
            payload: payload,
            chunks: [payload.substring(0, offset), payload.substring(offset)],
            label: 'payload $payloadIndex split at UTF-16 offset $offset',
          ));
        }
        for (var partition = 0; partition < 40; partition++) {
          final rng = _StableRandom(_seed ^ (payloadIndex * 7919) ^ partition);
          cases.add((
            payload: payload,
            chunks: _partition(payload, rng),
            label:
                'payload $payloadIndex seed ${rng.seed} partition $partition',
          ));
        }
      }

      expect(cases.length, 428);
      expect(_seed, 0x51A7E);

      for (final testCase in cases) {
        final expected = _decodePayload(testCase.payload);
        final result = await streamObject<Map<String, dynamic>>(
          model: textDeltaStream(testCase.chunks),
          schema: schema,
        );

        final settled =
            await Future.wait<Object?>([
              result.object,
              result.stream.toList(),
              result.partialObjectStream.toList(),
              result.patchStream.toList(),
              result.textStream.toList(),
              result.rawStream.toList(),
            ]).timeout(
              const Duration(seconds: 2),
              onTimeout: () => throw TimeoutException(
                'A streamObject future failed to settle for ${testCase.label}',
              ),
            );

        final object = settled[0] as Map<String, dynamic>;
        final completedObjects = settled[1] as List<Map<String, dynamic>>;
        final partials = settled[2] as List<Map<String, dynamic>>;
        final textChunks = settled[4] as List<String>;
        expect(object, equals(expected), reason: testCase.label);
        expect(completedObjects, hasLength(1), reason: testCase.label);
        expect(
          completedObjects.single,
          equals(expected),
          reason: testCase.label,
        );
        expect(textChunks.join(), testCase.payload, reason: testCase.label);
        expect(partials, isNotEmpty, reason: testCase.label);

        for (final snapshot in partials) {
          _expectImmutableTree(snapshot, testCase.label);
        }
      }
    },
  );
}

void _expectImmutableTree(Object? value, String reason) {
  if (value is Map) {
    expect(
      () => value['auditMutation'] = true,
      throwsUnsupportedError,
      reason: reason,
    );
    for (final child in value.values) {
      _expectImmutableTree(child, reason);
    }
  } else if (value is List) {
    expect(() => value.add(null), throwsUnsupportedError, reason: reason);
    for (final child in value) {
      _expectImmutableTree(child, reason);
    }
  }
}

Map<String, dynamic> _decodePayload(String payload) {
  final trimmed = payload.trim();
  final fence = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return (jsonDecode(fence?.group(1) ?? trimmed) as Map)
      .cast<String, dynamic>();
}

List<String> _partition(String text, _StableRandom random) {
  final offsets = <int>[];
  for (var offset = 1; offset < text.length; offset++) {
    if (random.nextInt(5) == 0) offsets.add(offset);
  }
  if (offsets.isEmpty && text.length > 1) {
    offsets.add(random.nextInt(text.length - 1) + 1);
  }
  final chunks = <String>[];
  var start = 0;
  for (final end in offsets) {
    chunks.add(text.substring(start, end));
    start = end;
  }
  chunks.add(text.substring(start));
  return chunks;
}

class _StableRandom {
  _StableRandom(this.seed) : _state = seed & 0x7fffffff;

  final int seed;
  int _state;

  int nextInt(int max) {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state % max;
  }
}
