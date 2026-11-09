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
