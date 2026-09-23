import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/streaming/tool_execution.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('streamed tool cleanup cannot replace or escape the source failure', () async {
    final escaped = <Object>[];
    final complete = Completer<void>();
    final primary = StateError('tool source failed');
    final cleanup = StateError('tool cleanup failed');
    Object? observed;
    runZonedGuarded(() async {
      final source = StreamController<Object?>(
        onCancel: () => Future<void>.error(cleanup),
      );
      final result = executeToolCall(
        tools: {'stream': dynamicTool<Stream<Object?>>(
          execute: (_, _) async => source.stream,
        )},
        call: const LanguageModelV4ToolCallPart(
          toolCallId: 'call-1', toolName: 'stream', input: {},
        ),
        messages: const [],
        approvalById: const {},
      );
      source.addError(primary);
      observed = (await result).toolError;
      await source.close();
      await Future<void>.delayed(Duration.zero);
      complete.complete();
    }, (error, stack) => escaped.add(error));
    await complete.future.timeout(const Duration(seconds: 2));
    expect(observed, same(primary));
    expect(escaped, isEmpty);
  });
}
