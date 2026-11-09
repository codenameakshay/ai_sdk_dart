import 'dart:async';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _library = OpenUiLibrary(
  root: _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  components: [
    _Spec('Out', {'value': S.any(), 'action': actionSchema.optional()}),
  ],
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('dispose cancels an event-stream listener', () async {
    final answers = OpenUiAnswers(library: _library);
    var canceled = 0;
    final controller = StreamController<OpenUiMessageEvent>(
      onCancel: () => canceled++,
    );
    addTearDown(controller.close);
    answers.listen(controller.stream);

    answers.dispose();
    await settle();

    expect(controller.hasListener, isFalse);
    expect(canceled, 1);
  });

  test('a transport error goes to onError with its message id and cancels '
      'the stream', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    var canceled = 0;
    final controller = StreamController<OpenUiMessageEvent>(
      onCancel: () => canceled++,
    );
    addTearDown(controller.close);
    final errors = <(String?, Object)>[];
    answers.listen(
      controller.stream,
      onError: (id, error, _) => errors.add((id, error)),
    );

    controller
      ..add(const OpenUiTextDelta('m1', 'root = Out('))
      ..addError(StateError('socket closed'));
    await settle();

    expect(errors, hasLength(1));
    expect(errors.single.$1, 'm1');
    expect(errors.single.$2, isA<StateError>());
    expect(canceled, 1);
    expect(controller.hasListener, isFalse);
    expect(answers.isStreaming('m1'), isTrue);
    expect(answers.textOf('m1'), 'root = Out(');
  });

  test('a stream that ends leaves its finished messages in place', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    final errors = <Object>[];
    answers.listen(
      Stream.fromIterable(const [
        OpenUiTextDelta('m1', 'root = Out(1)'),
        OpenUiMessageDone('m1'),
      ]),
      onError: (_, error, _) => errors.add(error),
    );
    await settle();

    expect(errors, isEmpty);
    expect(answers.isStreaming('m1'), isFalse);
    expect(answers.textOf('m1'), 'root = Out(1)');
  });

  test('a transport error before any message reports no id', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    final ids = <String?>[];
    answers.listen(
      Stream<OpenUiMessageEvent>.error(const FormatException('bad frame')),
      onError: (id, _, _) => ids.add(id),
    );
    await settle();

    expect(ids, [null]);
  });

  test('a transport error without onError is not an uncaught error', () async {
    final answers = OpenUiAnswers(library: _library);
    addTearDown(answers.dispose);
    final controller = StreamController<OpenUiMessageEvent>();
    addTearDown(controller.close);
    answers.listen(controller.stream);

    controller.addError(StateError('socket closed'));
    await settle();

    expect(controller.hasListener, isFalse);
  });

  test('listen after dispose throws synchronously', () {
    final answers = OpenUiAnswers(library: _library)..dispose();

    expect(
      () => answers.listen(const Stream<OpenUiMessageEvent>.empty()),
      throwsStateError,
    );
  });

  test('model snapshots do not call onSave', () async {
    final saved = <String, String>{};
    final answers = OpenUiAnswers(
      library: _library,
      onSave: (id, text) => saved[id] = text,
    );
    addTearDown(answers.dispose);

    answers.update('m1', 'root = Out(1)', streaming: true);
    answers.update('m1', 'root = Out(12)', streaming: true);
    answers.finish('m1');
    await settle();

    expect(saved, isEmpty);
  });
}
