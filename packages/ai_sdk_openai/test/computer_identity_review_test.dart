import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'computer action with call_id remains a client-executed request',
    () async {
      final adapter = _Adapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final model = OpenAIProvider(
        apiKey: 'fixture',
        client: dio,
      ).responses('fixture');
      final result = await model.doGenerate(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
        ),
      );
      final call = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      expect(call.toolCallId, 'call-action');
      expect(call.toolName, 'computer');
      expect(
        result.content.whereType<LanguageModelV4ToolResultPart>(),
        isEmpty,
      );
      expect(
        call.providerOptions?['openai']?['provider_executed'],
        isNot(true),
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  call,
                  LanguageModelV4ToolResultPart(
                    toolCallId: call.toolCallId,
                    toolName: call.toolName,
                    output: ToolResultOutputContent([
                      LanguageModelV4ImagePart(
                        image: DataContentUrl(
                          Uri.parse('https://fixture.test/screenshot.png'),
                        ),
                        mediaType: 'image/png',
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      final replayInput = adapter.inputs.last;
      final computerOutput = replayInput.whereType<Map>().firstWhere(
        (item) => item['type'] == 'computer_call_output',
      );
      expect(computerOutput['call_id'], 'call-action');
      expect(computerOutput['output'], {
        'type': 'computer_screenshot',
        'image_url': 'https://fixture.test/screenshot.png',
      });
    },
  );
}

class _Adapter implements HttpClientAdapter {
  final inputs = <List<dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    inputs.add((options.data as Map)['input'] as List<dynamic>);
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'response-${inputs.length}',
        'status': 'completed',
        'output': [
          {
            'type': 'computer_call',
            'id': 'item-action',
            'call_id': 'call-action',
            'action': {'type': 'click', 'x': 12, 'y': 34, 'button': 'left'},
            'pending_safety_checks': [],
            'status': 'completed',
          },
        ],
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
