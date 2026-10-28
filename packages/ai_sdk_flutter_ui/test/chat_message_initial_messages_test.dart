import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

String Function() _sequentialIds() {
  var nextId = 0;
  return () => 'initial-${++nextId}';
}

List<String> _ids(ChatController controller) => [
  for (final entry in controller.chatMessages) entry.id,
];

void main() {
  group('clear with mutable initialMessages', () {
    test('includes messages added after construction with fresh ids', () {
      const first = ModelMessage(role: ModelMessageRole.user, content: 'first');
      const added = ModelMessage(role: ModelMessageRole.user, content: 'added');
      final initialMessages = <ModelMessage>[first];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);
      controller.append(
        const ModelMessage(role: ModelMessageRole.assistant, content: 'later'),
      );

      initialMessages.add(added);
      controller.clear();

      expect(controller.messages, [first, added]);
      expect(_ids(controller), ['initial-1', 'initial-3']);
      expect(controller.chatMessages[1].provider, isNull);
      expect(controller.chatMessages[1].modelId, isNull);
      expect(controller.chatMessages[1].finishReason, isNull);
    });

    test('omits removed messages while retaining the remaining ids', () {
      const first = ModelMessage(role: ModelMessageRole.user, content: 'first');
      const second = ModelMessage(
        role: ModelMessageRole.user,
        content: 'second',
      );
      final initialMessages = <ModelMessage>[first, second];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);

      initialMessages.removeAt(0);
      controller.clear();

      expect(controller.messages, [second]);
      expect(_ids(controller), ['initial-2']);
    });

    test(
      'assigns a fresh id to a replacement without changing retained ids',
      () {
        const first = ModelMessage(
          role: ModelMessageRole.user,
          content: 'first',
        );
        const second = ModelMessage(
          role: ModelMessageRole.user,
          content: 'second',
        );
        const replacement = ModelMessage(
          role: ModelMessageRole.user,
          content: 'replacement',
        );
        final initialMessages = <ModelMessage>[first, second];
        final controller = ChatController(
          initialMessages: initialMessages,
          generateId: _sequentialIds(),
        );
        addTearDown(controller.dispose);

        initialMessages[0] = replacement;
        controller.clear();

        expect(controller.messages, [replacement, second]);
        expect(_ids(controller), ['initial-3', 'initial-2']);
      },
    );

    test('reorders messages together with their original ids', () {
      const first = ModelMessage(role: ModelMessageRole.user, content: 'first');
      const second = ModelMessage(
        role: ModelMessageRole.user,
        content: 'second',
      );
      final initialMessages = <ModelMessage>[first, second];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);

      initialMessages
        ..clear()
        ..addAll([second, first]);
      controller.clear();

      expect(controller.messages, [second, first]);
      expect(_ids(controller), ['initial-2', 'initial-1']);
    });

    test('preserves separate ids for repeated references when reordered', () {
      const repeated = ModelMessage(
        role: ModelMessageRole.user,
        content: 'repeated',
      );
      const other = ModelMessage(role: ModelMessageRole.user, content: 'other');
      final initialMessages = <ModelMessage>[repeated, repeated, other];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);

      initialMessages
        ..clear()
        ..addAll([other, repeated, repeated]);
      controller.clear();

      expect(controller.messages, [other, repeated, repeated]);
      expect(_ids(controller), ['initial-3', 'initial-1', 'initial-2']);
    });

    test('gives an added duplicate reference its own fresh id', () {
      const repeated = ModelMessage(
        role: ModelMessageRole.user,
        content: 'repeated',
      );
      final initialMessages = <ModelMessage>[repeated];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);

      initialMessages.add(repeated);
      controller.clear();

      expect(controller.messages, [repeated, repeated]);
      expect(_ids(controller), ['initial-1', 'initial-2']);
    });

    test('returns an empty transcript when initialMessages is emptied', () {
      final initialMessages = <ModelMessage>[
        const ModelMessage(role: ModelMessageRole.user, content: 'first'),
      ];
      final controller = ChatController(
        initialMessages: initialMessages,
        generateId: _sequentialIds(),
      );
      addTearDown(controller.dispose);

      initialMessages.clear();
      controller.clear();

      expect(controller.messages, isEmpty);
      expect(controller.chatMessages, isEmpty);
      expect(controller.status, ChatStatus.ready);
    });
  });
}
