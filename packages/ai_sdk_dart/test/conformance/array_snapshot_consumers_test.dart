import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/partial_json.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  final element = Schema<int>(
    jsonSchema: const {'type': 'object'},
    fromJson: (value) => value['id'] as int,
  );

  test('element-only consumer does not allocate array snapshots', () async {
    final counters = PartialJsonDebugCounters();
    partialJsonDebugCounters = counters;
    addTearDown(() => partialJsonDebugCounters = null);
    final result = await streamText<List<dynamic>>(
      model: textDeltaStream(['[', '{"id":1},', '{"id":2}', ']']),
      output: Output.array(element: element),
    );
    expect(await result.elementStream.toList(), [1, 2]);
    expect(await result.output, [1, 2]);
    expect(counters.snapshotCount, 0);
    expect(counters.snapshotElementsCopied, 0);
    expect(counters.snapshotStructuralNodes, 0);
    expect(counters.snapshotStructuralReferences, 0);
  });

  test('late snapshot subscriber gets the next complete prefix', () async {
    final source = StreamController<LanguageModelV4StreamPart>();
    final result = await streamText<List<dynamic>>(
      model: _ControlledModel(source.stream),
      output: Output.array(element: element),
    );
    final firstElement = Completer<void>();
    final elements = <Object?>[];
    final subscription = result.elementStream.listen((value) {
      elements.add(value);
      if (!firstElement.isCompleted) firstElement.complete();
    });
    source.add(const StreamPartTextStart(id: 'text'));
    source.add(const StreamPartTextDelta(id: 'text', delta: '[{"id":1},'));
    await firstElement.future;
    final snapshots = result.partialOutputStream.toList();
    source.add(const StreamPartTextDelta(id: 'text', delta: '{"id":2},'));
    source.add(const StreamPartTextDelta(id: 'text', delta: '{"id":3}]'));
    source.add(const StreamPartTextEnd(id: 'text'));
    source.add(
      const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    );
    await source.close();
    final retained = (await snapshots).cast<List<dynamic>>();
    expect(retained, [
      [1, 2],
      [1, 2, 3],
    ]);
    expect(() => retained.first.add(4), throwsUnsupportedError);
    expect(await result.output, [1, 2, 3]);
    expect(elements, [1, 2, 3]);
    await subscription.cancel();
  });
}

class _ControlledModel extends FakeStreamModel {
  _ControlledModel(this.source) : super(const []);
  final Stream<LanguageModelV4StreamPart> source;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: source);
}
