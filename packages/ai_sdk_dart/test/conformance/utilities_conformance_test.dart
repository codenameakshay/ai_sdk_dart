import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('utilities conformance', () {
    // ── generateId() ──────────────────────────────────────────────────────

    group('generateId()', () {
      test('returns a non-empty string', () {
        final id = generateId();
        expect(id, isNotEmpty);
      });

      test('default size is 7 characters (nanoid-style, JS SDK parity)', () {
        final id = generateId();
        expect(id.length, 7);
      });

      test('custom size is respected', () {
        expect(generateId(size: 12).length, 12);
        expect(generateId(size: 16).length, 16);
        expect(generateId(size: 1).length, 1);
      });

      test('contains only characters from the nanoid alphabet', () {
        const alphabet =
            'useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict';
        for (var i = 0; i < 200; i++) {
          final id = generateId();
          for (final char in id.split('')) {
            expect(alphabet.contains(char), isTrue, reason: 'char "$char"');
          }
        }
      });

      test('consecutive calls return unique IDs', () {
        final ids = List.generate(200, (_) => generateId());
        expect(ids.toSet().length, ids.length);
      });
    });

    // ── createIdGenerator() ───────────────────────────────────────────────

    group('createIdGenerator()', () {
      test('returns a function', () {
        final gen = createIdGenerator();
        expect(gen, isA<Function>());
      });

      test('default size produces 7-char IDs', () {
        final gen = createIdGenerator();
        expect(gen().length, 7);
        expect(gen().length, 7);
      });

      test('custom size is respected', () {
        final gen = createIdGenerator(size: 12);
        expect(gen().length, 12);
        expect(gen().length, 12);
      });

      test('consecutive calls return unique IDs', () {
        final gen = createIdGenerator();
        final ids = List.generate(50, (_) => gen());
        expect(ids.toSet().length, ids.length);
      });

      test('two independent generators produce unique IDs', () {
        final gen1 = createIdGenerator();
        final gen2 = createIdGenerator();
        final id1 = gen1();
        final id2 = gen2();
        expect(id1, isNot(id2));
      });
    });

    // ── simulateReadableStream() ──────────────────────────────────────────

    group('simulateReadableStream()', () {
      test('emits all parts in the given order', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ];

        final emitted = await simulateReadableStream(parts: parts).toList();
        expect(emitted.length, 4);
        expect(emitted[0], isA<StreamPartTextStart>());
        expect(emitted[1], isA<StreamPartTextDelta>());
        expect(emitted[2], isA<StreamPartTextEnd>());
        expect(emitted[3], isA<StreamPartFinish>());
      });

      test('emits parts in correct typed order', () async {
        final parts = [
          const StreamPartReasoningDelta(delta: 'thinking'),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ];

        final emitted = await simulateReadableStream(parts: parts).toList();
        expect(emitted[0], isA<StreamPartReasoningDelta>());
        expect((emitted[0] as StreamPartReasoningDelta).delta, 'thinking');
      });

      test('empty parts list produces empty stream', () async {
        final emitted = await simulateReadableStream(parts: []).toList();
        expect(emitted, isEmpty);
      });

      test('with no delay, stream completes quickly', () async {
        final stopwatch = Stopwatch()..start();
        final parts = List.generate(
          10,
          (i) => StreamPartTextDelta(id: 't1', delta: 'chunk$i'),
        );
        await simulateReadableStream(parts: parts).toList();
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('initialDelayInMs delays only the first chunk', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
        ];

        final stopwatch = Stopwatch()..start();
        await simulateReadableStream(
          parts: parts,
          initialDelayInMs: 50,
        ).toList();
        stopwatch.stop();
        // Should wait at least ~50ms for the first chunk only
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
      });

      test('chunkDelayInMs delays between chunks (not before first)', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'a'),
          const StreamPartTextDelta(id: 't1', delta: 'b'),
          const StreamPartTextEnd(id: 't1'),
        ];

        final stopwatch = Stopwatch()..start();
        await simulateReadableStream(
          parts: parts,
          chunkDelayInMs: 20,
        ).toList();
        stopwatch.stop();
        // 3 gaps × 20ms = at least 60ms
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
      });

      test('legacy delay parameter still works', () async {
        final parts = [
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
        ];

        final stopwatch = Stopwatch()..start();
        await simulateReadableStream(
          parts: parts,
          delay: const Duration(milliseconds: 20),
        ).toList();
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(30));
      });

      test('preserves stream part data through emission', () async {
        const delta = StreamPartTextDelta(id: 'myId', delta: 'specific text');
        final emitted = await simulateReadableStream(parts: [delta]).toList();
        final emittedDelta = emitted[0] as StreamPartTextDelta;
        expect(emittedDelta.id, 'myId');
        expect(emittedDelta.delta, 'specific text');
      });
    });

    // ── convertToModelMessages() ──────────────────────────────────────────

    group('convertToModelMessages()', () {
      test('converts single text user message', () {
        final messages = [
          LanguageModelV3Message(
            role: LanguageModelV3Role.user,
            content: [const LanguageModelV3TextPart(text: 'hello')],
          ),
        ];
        final result = convertToModelMessages(messages);
        expect(result.length, 1);
        expect(result[0].role, ModelMessageRole.user);
        expect(result[0].content, 'hello');
      });

      test('converts assistant message', () {
        final messages = [
          LanguageModelV3Message(
            role: LanguageModelV3Role.assistant,
            content: [const LanguageModelV3TextPart(text: 'world')],
          ),
        ];
        final result = convertToModelMessages(messages);
        expect(result[0].role, ModelMessageRole.assistant);
        expect(result[0].content, 'world');
      });

      test('converts system message', () {
        final messages = [
          LanguageModelV3Message(
            role: LanguageModelV3Role.system,
            content: [const LanguageModelV3TextPart(text: 'be helpful')],
          ),
        ];
        final result = convertToModelMessages(messages);
        expect(result[0].role, ModelMessageRole.system);
        expect(result[0].content, 'be helpful');
      });

      test('converts multi-part message to ModelMessage.parts', () {
        final messages = [
          LanguageModelV3Message(
            role: LanguageModelV3Role.user,
            content: [
              const LanguageModelV3TextPart(text: 'look at this'),
              LanguageModelV3ImagePart(
                mediaType: 'image/png',
                image: DataContentUrl(Uri.parse('https://example.com/img.png')),
              ),
            ],
          ),
        ];
        final result = convertToModelMessages(messages);
        expect(result[0].parts, isNotNull);
        expect(result[0].parts!.length, 2);
      });

      test('converts empty list', () {
        expect(convertToModelMessages([]), isEmpty);
      });

      test('round-trips single-text messages', () {
        const original = ModelMessage(role: ModelMessageRole.user, content: 'hi');
        final messages = [
          LanguageModelV3Message(
            role: LanguageModelV3Role.user,
            content: [const LanguageModelV3TextPart(text: 'hi')],
          ),
        ];
        final result = convertToModelMessages(messages);
        expect(result[0].content, original.content);
        expect(result[0].role, original.role);
      });
    });

    // ── pruneMessages() ───────────────────────────────────────────────────

    group('pruneMessages()', () {
      test('removes system messages', () {
        final messages = [
          const ModelMessage(role: ModelMessageRole.system, content: 'sys'),
          const ModelMessage(role: ModelMessageRole.user, content: 'hi'),
          const ModelMessage(role: ModelMessageRole.assistant, content: 'hello'),
        ];
        final result = pruneMessages(messages);
        expect(result.length, 2);
        expect(result.any((m) => m.role == ModelMessageRole.system), isFalse);
      });

      test('preserves user messages', () {
        final messages = [
          const ModelMessage(role: ModelMessageRole.user, content: 'a'),
          const ModelMessage(role: ModelMessageRole.user, content: 'b'),
        ];
        final result = pruneMessages(messages);
        expect(result.length, 2);
      });

      test('preserves assistant messages', () {
        final messages = [
          const ModelMessage(role: ModelMessageRole.assistant, content: 'a'),
        ];
        final result = pruneMessages(messages);
        expect(result.length, 1);
        expect(result[0].role, ModelMessageRole.assistant);
      });

      test('preserves tool messages', () {
        final messages = [
          ModelMessage.parts(
            role: ModelMessageRole.tool,
            parts: [
              LanguageModelV3ToolResultPart(
                toolCallId: 'id',
                toolName: 'fn',
                output: const ToolResultOutputText('result'),
              ),
            ],
          ),
        ];
        final result = pruneMessages(messages);
        expect(result.length, 1);
        expect(result[0].role, ModelMessageRole.tool);
      });

      test('returns empty list when all messages are system', () {
        final messages = [
          const ModelMessage(role: ModelMessageRole.system, content: 'a'),
          const ModelMessage(role: ModelMessageRole.system, content: 'b'),
        ];
        expect(pruneMessages(messages), isEmpty);
      });

      test('returns empty list for empty input', () {
        expect(pruneMessages([]), isEmpty);
      });
    });
  });
}
