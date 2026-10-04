import 'dart:math';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:test/test.dart';

void main() {
  test('seeded nested unknown JSON round-trips and freezes (256 cases)', () {
    const seed = 0xC0DEC0DE;
    const cases = 256;
    final random = Random(seed);

    for (var index = 0; index < cases; index++) {
      final nested = <String, Object?>{'inner': _randomJson(random, 0)};
      final wire = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'conversation-$index',
        'futureRoot': {'payload': nested},
        'messages': [
          {
            'id': 'message-$index',
            'role': 'user',
            'status': 'complete',
            'futureMessage': [nested],
            'parts': [
              {
                'id': 'part-$index',
                'type': 'future_part_$index',
                'futurePart': {'payload': nested},
              },
            ],
          },
        ],
      };
      final expected = _copyJson(wire);
      final decoded = ConversationCodec.decode(wire);
      expect(
        ConversationCodec.encode(decoded),
        expected,
        reason: 'seed=$seed case=$index',
      );

      _mutateNestedWire(wire['futureRoot']!['payload']);
      expect(
        ConversationCodec.encode(decoded),
        expected,
        reason: 'decoded snapshot aliases input at seed=$seed case=$index',
      );
      expect(
        () => _mutateNestedWire(decoded.extra['futureRoot']!['payload']),
        throwsA(anything),
        reason: 'decoded extras must be immutable at seed=$seed case=$index',
      );
    }
  });

  test('seeded invalid schema boundaries are rejected (256 cases)', () {
    const seed = 0xBAD5EED;
    const cases = 256;
    final random = Random(seed);

    for (var index = 0; index < cases; index++) {
      final wire = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'conversation-$index',
        'messages': [
          {
            'id': 'message-$index',
            'role': 'user',
            'status': 'complete',
            'parts': [
              <String, dynamic>{
                'id': 'part-$index',
                'type': 'text',
                'text': 'payload',
              },
            ],
          },
        ],
      };
      switch (index % 4) {
        case 0:
          wire['schemaVersion'] = 2 + random.nextInt(1000);
        case 1:
          final message =
              (wire['messages'] as List).single as Map<String, dynamic>;
          message['role'] = 'future-${random.nextInt(9)}';
        case 2:
          final message =
              (wire['messages'] as List).single as Map<String, dynamic>;
          final part =
              (message['parts'] as List).single as Map<String, dynamic>;
          part['text'] = random.nextInt(2) == 0 ? null : 7;
        case 3:
          var tooDeep = <Object?>[];
          final root = tooDeep;
          for (var depth = 0; depth < 66; depth++) {
            final child = <Object?>[];
            tooDeep.add(child);
            tooDeep = child;
          }
          wire['futureRoot'] = root;
      }
      expect(
        () => ConversationCodec.decode(wire),
        throwsA(
          anyOf(
            isA<ConversationSchemaException>(),
            isA<ConversationValidationException>(),
          ),
        ),
        reason: 'seed=$seed case=$index variant=${index % 4}',
      );
    }
  });
}

Object? _randomJson(Random random, int depth) {
  if (depth >= 7 || random.nextInt(4) == 0) {
    return switch (random.nextInt(5)) {
      0 => null,
      1 => random.nextBool(),
      2 => random.nextInt(1 << 20) - (1 << 19),
      3 => 'value-${random.nextInt(1 << 16)}-é🧪',
      _ => random.nextDouble() * 1000,
    };
  }
  if (random.nextBool()) {
    return List<Object?>.generate(
      random.nextInt(4),
      (_) => _randomJson(random, depth + 1),
    );
  }
  return <String, Object?>{
    for (var index = 0; index < random.nextInt(4); index++)
      'k${random.nextInt(1 << 20)}': _randomJson(random, depth + 1),
  };
}

Object? _copyJson(Object? value) => switch (value) {
  Map() => value.map((key, item) => MapEntry(key, _copyJson(item))),
  List() => value.map(_copyJson).toList(),
  _ => value,
};

void _mutateNestedWire(Object? value) {
  switch (value) {
    case Map():
      value['mutated'] = true;
    case List():
      value.add('mutated');
    default:
      throw StateError('no mutable nested container found');
  }
}
