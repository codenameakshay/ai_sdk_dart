import 'dart:math';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Computes the cosine similarity between two embedding vectors.
///
/// Returns a value in [-1, 1] where 1 means identical direction,
/// 0 means orthogonal, and -1 means opposite.
///
/// Throws [ArgumentError] if the vectors have different lengths or are empty.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'Vectors must have the same length: ${a.length} vs ${b.length}',
    );
  }
  if (a.isEmpty) {
    throw ArgumentError('Vectors must not be empty.');
  }
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  final denom = sqrt(normA) * sqrt(normB);
  if (denom == 0.0) return 0.0;
  return dot / denom;
}

// ---------------------------------------------------------------------------
// ID generation
// ---------------------------------------------------------------------------

final _random = Random.secure();

/// Generates a unique random ID string with the given [prefix].
///
/// Format: `{prefix}-{timestamp}{random}`
String generateId([String prefix = 'id']) {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '$prefix-$ts$rand';
}

/// Creates an ID generator function with a fixed [prefix].
///
/// ```dart
/// final nextId = createIdGenerator(prefix: 'msg');
/// final id = nextId(); // 'msg-...'
/// ```
String Function() createIdGenerator({String prefix = 'id'}) {
  return () => generateId(prefix);
}

// ---------------------------------------------------------------------------
// Stream simulation
// ---------------------------------------------------------------------------

/// Simulates a [Stream] from a list of [parts], optionally with a [delay]
/// between each part.
///
/// Useful for testing streaming logic without a real provider.
///
/// ```dart
/// final stream = simulateReadableStream(
///   parts: [
///     StreamPartTextStart(id: '1'),
///     StreamPartTextDelta(id: '1', delta: 'Hello'),
///     StreamPartTextEnd(id: '1'),
///     StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
///   ],
/// );
/// ```
Stream<LanguageModelV3StreamPart> simulateReadableStream({
  required List<LanguageModelV3StreamPart> parts,
  Duration delay = Duration.zero,
}) async* {
  for (final part in parts) {
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    yield part;
  }
}
