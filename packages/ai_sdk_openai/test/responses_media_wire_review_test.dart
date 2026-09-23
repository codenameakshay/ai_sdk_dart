import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final image in [false, true]) {
    for (final url in [false, true]) {
      test('tool file wire image=$image url=$url', () async {
        final adapter = _Adapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        final mediaType = image ? 'image/png' : 'application/pdf';
        const location = 'https://example.test/asset';
        await OpenAIProvider(apiKey: 'fixture', client: dio)
            .responses('fixture')
            .doGenerate(
              LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(
                  messages: [
                    LanguageModelV4Message(
                      role: LanguageModelV4Role.tool,
                      content: [
                        LanguageModelV4ToolResultPart(
                          toolCallId: 'call-1',
                          toolName: 'read',
                          output: ToolResultOutputContent([
                            LanguageModelV4FilePart(
                              data: url
                                  ? DataContentUrl(Uri.parse(location))
                                  : DataContentBytes(
                                      Uint8List.fromList([1, 2, 3]),
                                    ),
                              mediaType: mediaType,
                              filename: 'asset',
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
        final item = (adapter.input.single as Map)['output'] as List;
        expect(item.single, {
          'type': image ? 'input_image' : 'input_file',
          if (image)
            'image_url': url ? location : 'data:$mediaType;base64,AQID'
          else if (url)
            'file_url': location
          else ...{
            'file_data': 'data:$mediaType;base64,AQID',
            'filename': 'asset',
          },
        });
      });
    }
  }
}

class _Adapter implements HttpClientAdapter {
  List<dynamic> input = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    input = (options.data as Map)['input'] as List<dynamic>;
    return ResponseBody.fromString(
      '{"id":"r","status":"completed","output":[]}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
