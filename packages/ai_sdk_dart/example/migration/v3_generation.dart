import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';

Future<void> main() async {
  var ended = 0;
  final model = MockLanguageModelV4(response: [mockText('hello')]);
  final result = await generateText(
    model: model,
    instructions: 'Answer briefly.',
    prompt: 'Say hello.',
    onEnd: (_) => ended++,
  );
  if (result.text != 'hello' ||
      result.finalStep.text != 'hello' ||
      ended != 1) {
    throw StateError('Generation migration example failed');
  }
  final history = [
    const ModelMessage(role: ModelMessageRole.user, content: 'Say hello.'),
    ...result.responseMessages.map(ModelMessage.fromProvider),
  ];
  await generateText(model: model, messages: history);
  if (model.generateCalls.last.prompt.messages.length != 2) {
    throw StateError('Response history was duplicated');
  }
}
