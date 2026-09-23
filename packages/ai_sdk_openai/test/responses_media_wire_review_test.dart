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

  test('prompt and tool media serialization stay in parity', () async {
    final cases =
        <
          ({
            String name,
            LanguageModelV4DataContent data,
            String mediaType,
            Map<String, dynamic> expected,
          })
        >[
          (
            name: 'bytes',
            data: DataContentBytes(Uint8List.fromList([1, 2, 3])),
            mediaType: 'application/pdf',
            expected: {
              'type': 'input_file',
              'file_data': 'data:application/pdf;base64,AQID',
              'filename': 'asset',
            },
          ),
          (
            name: 'url',
            data: DataContentUrl(Uri.parse('https://example.test/asset')),
            mediaType: 'application/pdf',
            expected: {
              'type': 'input_file',
              'file_url': 'https://example.test/asset',
            },
          ),
          (
            name: 'OpenAI file reference',
            data: const DataContentProviderReference(
              namespace: 'openai',
              id: 'file-1',
            ),
            mediaType: 'application/pdf',
            expected: {'type': 'input_file', 'file_id': 'file-1'},
          ),
          (
            name: 'image file with detail',
            data: DataContentBytes(Uint8List.fromList([1, 2, 3])),
            mediaType: 'image/png',
            expected: {
              'type': 'input_image',
              'image_url': 'data:image/png;base64,AQID',
              'detail': 'high',
            },
          ),
          (
            name: 'image URL with detail',
            data: DataContentUrl(Uri.parse('https://example.test/image.png')),
            mediaType: 'image/png',
            expected: {
              'type': 'input_image',
              'image_url': 'https://example.test/image.png',
              'detail': 'high',
            },
          ),
          (
            name: 'image OpenAI file reference with detail',
            data: const DataContentProviderReference(
              namespace: 'openai',
              id: 'file-image',
            ),
            mediaType: 'image/png',
            expected: {
              'type': 'input_image',
              'file_id': 'file-image',
              'detail': 'high',
            },
          ),
        ];

    for (final media in cases) {
      final part = LanguageModelV4FilePart(
        data: media.data,
        mediaType: media.mediaType,
        filename: 'asset',
        providerOptions: const {
          'openai': {'detail': 'high'},
        },
      );
      final prompt = await _promptMedia(part);
      final tool = await _toolMedia(part);
      expect(prompt, media.expected, reason: media.name);
      expect(tool, media.expected, reason: media.name);
    }
  });

  test('foreign media references are rejected before dispatch', () async {
    const foreign = DataContentProviderReference(
      namespace: 'other',
      id: 'asset-1',
    );
    for (final mediaType in ['application/pdf', 'image/png']) {
      final part = LanguageModelV4FilePart(data: foreign, mediaType: mediaType);
      await expectLater(_promptMedia(part), throwsA(isA<ArgumentError>()));
      await expectLater(_toolMedia(part), throwsA(isA<ArgumentError>()));
    }
  });

  test('foreign opaque prompt parts are rejected before dispatch', () async {
    const opaque = LanguageModelV4OpaquePart(
      provider: 'other',
      raw: {'type': 'unknown'},
    );
    await expectLater(_promptMedia(opaque), throwsA(isA<UnsupportedError>()));
    await expectLater(_toolMedia(opaque), throwsA(isA<UnsupportedError>()));
  });
}

Future<Map<String, dynamic>> _promptMedia(
  LanguageModelV4ContentPart part,
) async {
  final adapter = _MediaAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  await OpenAIProvider(apiKey: 'fixture', client: dio)
      .responses('fixture')
      .doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [part],
              ),
            ],
          ),
        ),
      );
  final input = adapter.input.single as Map;
  final message = (input['input'] as List).single as Map;
  return ((message['content'] as List).single as Map).cast<String, dynamic>();
}

Future<Map<String, dynamic>> _toolMedia(LanguageModelV4ContentPart part) async {
  final adapter = _MediaAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
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
                    output: ToolResultOutputContent([part]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  final input = adapter.input.single as Map;
  final item = (input['input'] as List).single as Map;
  return ((item['output'] as List).single as Map).cast<String, dynamic>();
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

class _MediaAdapter implements HttpClientAdapter {
  List<dynamic> input = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    input = [(options.data as Map).cast<String, dynamic>()];
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
