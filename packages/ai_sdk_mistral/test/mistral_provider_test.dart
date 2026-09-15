import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/http_helpers.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  group('MistralProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider('mistral-large-latest');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-large-latest');
      expect(model.specificationVersion, 'v4');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider.embedding('mistral-embed');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-embed');
      expect(model.specificationVersion, 'v2');
    });

    test(
      'chat credentials are resolved immediately before each request',
      () async {
        final authorizations = <String?>[];
        final server = await _startServer((request) async {
          authorizations.add(request.headers.value('authorization'));
          writeOk(request);
        });
        addTearDown(server.close);

        var token = 'first-token';
        final provider = MistralProvider(
          baseUrl: server.baseUrl,
          credentialProvider: () async => token,
        );

        await provider(
          'mistral-small',
        ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
        token = 'second-token';
        await provider(
          'mistral-small',
        ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

        expect(authorizations, ['Bearer first-token', 'Bearer second-token']);
      },
    );

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await _startServer((request) async {
          writeOk(request);
        });
        addTearDown(server.close);

        final ownedProvider = MistralProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider('mistral-small').doGenerate(
            LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
          ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = MistralProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider('mistral-small').doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
        );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test('forwards providerOptions into the request body', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      await MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'mistral-small',
      ).doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          providerOptions: const {
            'mistral': {'safe_prompt': true},
          },
        ),
      );

      expect(captured['safe_prompt'], isTrue);
    });
  });

  group('OpenAI-compatible capabilities (via shared base)', () {
    test('serializes tools and tool_choice', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'mistral-large-latest',
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('weather'),
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceAuto(),
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect((tools.single['function'] as Map)['name'], 'weather');
      expect(captured['tool_choice'], 'auto');
    });

    test('serializes multimodal image content part', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'pixtral-large-latest',
      );
      await model.doGenerate(LanguageModelV4CallOptions(prompt: imagePrompt()));

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
    });

    test('uses random_seed and max_tokens quirks', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'mistral-small',
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          seed: 99,
          maxOutputTokens: 200,
        ),
      );
      expect(captured['random_seed'], 99);
      expect(captured.containsKey('seed'), isFalse);
      expect(captured['max_tokens'], 200);
    });

    test(
      'baseUrl ending with slash still posts to chat/completions once',
      () async {
        late String path;
        final server = await _startServer((request) async {
          path = request.uri.path;
          writeOk(request);
        });
        addTearDown(server.close);

        final model = MistralProvider(
          apiKey: 'key',
          baseUrl: '${server.baseUrl}/',
        )('mistral-small');
        await model.doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('hi')),
        );

        expect(path, '/v1/chat/completions');
      },
    );
  });

  group('Mistral embedding doEmbed wire format', () {
    test('forwards embedding providerOptions', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = await captureBody(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'embedding': [0.1],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      await MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)
          .embedding('mistral-embed')
          .doEmbed(
            const EmbeddingModelV2CallOptions<String>(
              values: ['hello'],
              providerOptions: {
                'mistral': {'output_dtype': 'float'},
              },
            ),
          );

      expect(captured['output_dtype'], 'float');
    });

    test(
      'posts to /embeddings with bearer auth, parses embeddings in order',
      () async {
        late Map<String, dynamic> captured;
        String? path;
        String? authHeader;
        final server = await _startServer((request) async {
          path = request.uri.path;
          authHeader = request.headers.value('authorization');
          captured = await captureBody(request);

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'index': 0,
                  'embedding': [0.1, 0.2],
                },
                {
                  'index': 1,
                  'embedding': [0.3, 0.4],
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = MistralProvider(
          apiKey: 'secret-key',
          baseUrl: server.baseUrl,
        ).embedding('mistral-embed');

        final result = await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
        );

        expect(path, '/v1/embeddings');
        expect(authHeader, 'Bearer secret-key');
        expect(captured['model'], 'mistral-embed');
        expect(captured['input'], ['a', 'b']);
        expect(result.embeddings, hasLength(2));
        expect(result.embeddings[0].value, 'a');
        expect(result.embeddings[0].embedding, [0.1, 0.2]);
        expect(result.embeddings[1].value, 'b');
        expect(result.embeddings[1].embedding, [0.3, 0.4]);
      },
    );

    test('tolerates a response with no data list', () async {
      final server = await _startServer((request) async {
        await captureBody(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'object': 'list'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = MistralProvider(
        apiKey: 'key',
        baseUrl: server.baseUrl,
      ).embedding('mistral-embed');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['only']),
      );
      expect(result.embeddings, isEmpty);
    });

    test(
      'normalizes numeric vectors and ignores response rows beyond the input',
      () async {
        final server = await _startServer((request) async {
          await captureBody(request);
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'embedding': [1, 2.5],
                },
                {
                  'embedding': [-3, 4],
                },
                {
                  'embedding': [99],
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final result =
            await MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)
                .embedding('mistral-embed')
                .doEmbed(
                  const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
                );

        expect(result.embeddings, hasLength(2));
        expect(result.embeddings.map((embedding) => embedding.value), [
          'a',
          'b',
        ]);
        expect(result.embeddings.map((embedding) => embedding.embedding), [
          [1.0, 2.5],
          [-3.0, 4.0],
        ]);
      },
    );

    test('baseUrl ending with slash still posts to embeddings once', () async {
      late String path;
      final server = await _startServer((request) async {
        path = request.uri.path;
        await captureBody(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'index': 0,
                'embedding': [0.1, 0.2],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = MistralProvider(
        apiKey: 'key',
        baseUrl: '${server.baseUrl}/',
      ).embedding('mistral-embed');

      await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['hello']),
      );

      expect(path, '/v1/embeddings');
    });

    test(
      'embedding credentials are resolved immediately before each request',
      () async {
        final authorizations = <String?>[];
        final server = await _startServer((request) async {
          authorizations.add(request.headers.value('authorization'));
          await captureBody(request);
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'index': 0,
                  'embedding': [0.1, 0.2],
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        var token = 'first-token';
        final model = MistralProvider(
          baseUrl: server.baseUrl,
          credentialProvider: () async => token,
        ).embedding('mistral-embed');

        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['first']),
        );
        token = 'second-token';
        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['second']),
        );

        expect(authorizations, ['Bearer first-token', 'Bearer second-token']);
      },
    );
  });
}

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/v1');
