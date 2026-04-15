import 'dart:math';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../messages/model_message.dart';

/// Computes the cosine similarity between two embedding vectors.
///
/// Returns a value in [-1, 1] where 1 means identical direction,
/// 0 means orthogonal, and -1 means opposite.
/// Mirrors `cosineSimilarity` from the JS AI SDK v6.
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

/// Alphabet used for nanoid-style IDs — matches the JS AI SDK v6 default.
const _nanoidAlphabet =
    'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';

/// Generates a unique random ID string.
///
/// Produces a nanoid-style 7-character alphanumeric ID matching the JS AI
/// SDK v6 default output format.  Optionally a [size] can be specified.
/// Mirrors `generateId` from the JS AI SDK v6.
String generateId({int size = 7}) {
  final bytes = List<int>.generate(size, (_) => _random.nextInt(256));
  return String.fromCharCodes(
    bytes.map((b) => _nanoidAlphabet.codeUnitAt(b % _nanoidAlphabet.length)),
  );
}

/// Creates an ID generator function with a fixed [size].
///
/// Mirrors `createIdGenerator` from the JS AI SDK v6.
///
/// ```dart
/// final nextId = createIdGenerator(size: 16);
/// final id = nextId(); // e.g. 'n6NxhNlT1fxqy4RE'
/// ```
String Function() createIdGenerator({int size = 7}) {
  return () => generateId(size: size);
}

// ---------------------------------------------------------------------------
// Stream simulation
// ---------------------------------------------------------------------------

/// Simulates a [Stream] from a list of [parts], optionally with [delay].
///
/// Useful for testing streaming logic without a real provider.
/// Mirrors `simulateReadableStream` from the JS AI SDK v6.
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
/// Simulates a [Stream] from a list of [parts].
///
/// Useful for testing streaming logic without a real provider.
/// Mirrors `simulateReadableStream` from the JS AI SDK v6.
///
/// - [initialDelayInMs] — delay before the first chunk (default: 0).
/// - [chunkDelayInMs] — delay between subsequent chunks (default: 0).
///
/// ```dart
/// final stream = simulateReadableStream(
///   parts: [
///     StreamPartTextStart(id: '1'),
///     StreamPartTextDelta(id: '1', delta: 'Hello'),
///     StreamPartTextEnd(id: '1'),
///     StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
///   ],
///   initialDelayInMs: 50,
///   chunkDelayInMs: 10,
/// );
/// ```
Stream<LanguageModelV3StreamPart> simulateReadableStream({
  required List<LanguageModelV3StreamPart> parts,
  int initialDelayInMs = 0,
  int chunkDelayInMs = 0,
  // Legacy alias kept for backward compatibility.
  Duration delay = Duration.zero,
}) async* {
  final firstDelay = initialDelayInMs > 0
      ? Duration(milliseconds: initialDelayInMs)
      : delay;
  final betweenDelay = chunkDelayInMs > 0
      ? Duration(milliseconds: chunkDelayInMs)
      : delay;

  var first = true;
  for (final part in parts) {
    if (first) {
      if (firstDelay != Duration.zero) {
        await Future<void>.delayed(firstDelay);
      }
      first = false;
    } else if (betweenDelay != Duration.zero) {
      await Future<void>.delayed(betweenDelay);
    }
    yield part;
  }
}

// ---------------------------------------------------------------------------
// Message utilities
// ---------------------------------------------------------------------------

/// Converts a list of provider-level [LanguageModelV3Message] objects to
/// user-facing [ModelMessage] objects.
///
/// Mirrors `convertToModelMessages` from the JS AI SDK v6.
List<ModelMessage> convertToModelMessages(
  List<LanguageModelV3Message> messages,
) {
  return messages.map((m) {
    final role = switch (m.role) {
      LanguageModelV3Role.system => ModelMessageRole.system,
      LanguageModelV3Role.user => ModelMessageRole.user,
      LanguageModelV3Role.assistant => ModelMessageRole.assistant,
      LanguageModelV3Role.tool => ModelMessageRole.tool,
    };
    if (m.content.length == 1 && m.content.first is LanguageModelV3TextPart) {
      return ModelMessage(
        role: role,
        content: (m.content.first as LanguageModelV3TextPart).text,
      );
    }
    return ModelMessage.parts(role: role, parts: m.content);
  }).toList();
}

/// Trims a message list to at most [maxMessages] entries, keeping the most
/// recent messages while always preserving the first system message (if any).
///
/// Mirrors `pruneMessages` from the JS AI SDK v6. Useful for context-window
/// management: when a conversation grows too long, drop the oldest non-system
/// turns rather than the newest ones.
///
/// - If [maxMessages] is null (the default), the list is returned unchanged.
/// - System messages at index 0 are always kept and do not count against
///   [maxMessages].
/// - If the list has ≤ [maxMessages] entries (excluding a leading system
///   message), it is returned unchanged.
///
/// Example:
/// ```dart
/// final history = [systemMsg, userA, assistantA, userB, assistantB];
/// pruneMessages(history, maxMessages: 2);
/// // → [systemMsg, userB, assistantB]
/// ```
List<ModelMessage> pruneMessages(
  List<ModelMessage> messages, {
  int? maxMessages,
}) {
  if (maxMessages == null || messages.isEmpty) return List.of(messages);

  // Split off a leading system message so it's always preserved.
  final hasLeadingSystem =
      messages.first.role == ModelMessageRole.system;
  final systemPrefix = hasLeadingSystem ? [messages.first] : <ModelMessage>[];
  final rest = hasLeadingSystem ? messages.sublist(1) : messages;

  if (rest.length <= maxMessages) return List.of(messages);

  // Keep the most recent maxMessages entries from the non-system portion.
  final kept = rest.sublist(rest.length - maxMessages);
  return [...systemPrefix, ...kept];
}
