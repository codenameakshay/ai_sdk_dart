import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _SilentModel extends MockLanguageModelV4 {
  final started = Completer<void>();
  late final source = StreamController<LanguageModelV4StreamPart>.broadcast(
    onListen: () => started.complete(),
  );
  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: source.stream);
}

void main() {
  test(
    'a stopped object stream cannot clear a newer stream after delayed cleanup',
    () async {
      final release = Completer<void>();
      final old = StreamController<String>(onCancel: () => release.future);
      final newer = StreamController<String>.broadcast();
      final objects = ObjectStreamController<String>();
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        if (!objects.isDisposed) objects.dispose();
        await newer.close();
      });
      await objects.bind(old.stream);
      final stopping = objects.stop();
      await objects.bind(newer.stream);
      newer.add('new value');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await stopping;
      expect(objects.value, 'new value');
      expect(objects.isStreaming, isTrue);
      expect(objects.isLoading, isTrue);
      objects.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(newer.hasListener, isFalse);
    },
  );

  test('late completion stop cannot reset a newer request', () async {
    final model = _SilentModel();
    final completion = CompletionController(agent: ToolLoopAgent(model: model));
    addTearDown(() async {
      completion.dispose();
      await model.source.close();
    });
    final stopping = completion.stop();
    final starting = completion.complete('new');
    await Future.wait([stopping, starting]);
    expect(completion.isLoading, isTrue);
    expect(completion.isStreaming, isTrue);
  });

  test('late chat stop cannot reset a newer request', () async {
    final model = _SilentModel();
    final chat = ChatController();
    addTearDown(() async {
      chat.dispose();
      await model.source.close();
    });
    final stopping = chat.stop();
    final starting = chat.sendMessage(
      agent: ToolLoopAgent(model: model),
      text: 'new',
    );
    await Future.wait([stopping, starting]);
    expect(chat.status, ChatStatus.streaming);
    await model.started.future;
    model.source.add(const StreamPartTextStart(id: 'new'));
    model.source.add(const StreamPartTextDelta(id: 'new', delta: 'new value'));
    await Future<void>.delayed(Duration.zero);
    expect(chat.streamingContent, 'new value');
  });
}
