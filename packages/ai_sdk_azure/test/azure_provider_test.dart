import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/http_helpers.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  test('chat alias and default provider expose expected models', () {
    expect(azureOpenAI.responses('deployment').provider, 'azure');
    expect(azureOpenAI.chat('deployment').modelId, 'deployment');
    expect(azureOpenAI.embedding('deployment').maxEmbeddingsPerCall, 2048);
    expect(azureOpenAI.embedding('deployment').supportsParallelCalls, isTrue);
  });

  group('AzureOpenAIProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider('my-gpt4-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-gpt4-deployment');
      expect(model.specificationVersion, 'v4');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider.embedding('my-ada-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-ada-deployment');
      expect(model.specificationVersion, 'v2');
    });

    test('uses default api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      expect(provider.apiVersion, '2024-02-15-preview');
    });

    test('accepts custom api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
        apiVersion: '2024-05-01-preview',
      );
      expect(provider.apiVersion, '2024-05-01-preview');
    });
  });

  test('malformed 2xx embedding responses raise AiApiCallError', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(server.close);

    final model = AzureOpenAIProvider(
      endpoint: server.baseUrl,
      apiKey: 'key',
    ).embedding('text-embedding-ada-002');

    await expectLater(
      model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['hello']),
      ),
      throwsA(isA<AiApiCallError>()),
    );
  });

  test('wrong-shaped 2xx embedding responses raise AiApiCallError', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': 'not-a-list'}));
      await request.response.close();
    });
    addTearDown(server.close);

    final model = AzureOpenAIProvider(
      endpoint: server.baseUrl,
      apiKey: 'key',
    ).embedding('text-embedding-ada-002');

    await expectLater(
      model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['hello']),
      ),
      throwsA(isA<AiApiCallError>()),
    );
  });

  group('OpenAI-compatible capabilities (via shared base)', () {
    test('serializes tools and tool_choice', () async {
      late Map<String, dynamic> captured;
      final server = await TestServer.start((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'key',
      )('gpt-4-deployment');
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('weather'),
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect((tools.single['function'] as Map)['name'], 'weather');
      expect(captured['tool_choice'], 'required');
    });

    test('serializes multimodal image content part', () async {
      late Map<String, dynamic> captured;
      final server = await TestServer.start((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'key',
      )('gpt-4o-deployment');
      await model.doGenerate(LanguageModelV4CallOptions(prompt: imagePrompt()));

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
    });

    test('sends api-key header and api-version query param', () async {
      String? authHeader;
      String? apiKeyHeader;
      String? query;
      final server = await TestServer.start((request) async {
        authHeader = request.headers.value('authorization');
        apiKeyHeader = request.headers.value('api-key');
        query = request.uri.query;
        writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'secret-key',
        apiVersion: '2024-05-01-preview',
      )('gpt-4-deployment');
      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: userPrompt('hi')),
      );

      expect(apiKeyHeader, 'secret-key');
      expect(authHeader, isNull);
      expect(query, contains('api-version=2024-05-01-preview'));
    });

    test(
      'endpoint ending with slash still posts to deployment chat once',
      () async {
        late String path;
        final server = await TestServer.start((request) async {
          path = request.uri.path;
          writeOk(request);
        });
        addTearDown(server.close);

        final model = AzureOpenAIProvider(
          endpoint: '${server.baseUrl}/',
          apiKey: 'secret-key',
        )('gpt-4-deployment');
        await model.doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('hi')),
        );

        expect(path, '/openai/deployments/gpt-4-deployment/chat/completions');
      },
    );

    test(
      'chat credentials are resolved immediately before each request',
      () async {
        final apiKeys = <String?>[];
        final server = await TestServer.start((request) async {
          apiKeys.add(request.headers.value('api-key'));
          writeOk(request);
        });
        addTearDown(server.close);

        var token = 'first-key';
        final provider = AzureOpenAIProvider(
          endpoint: server.baseUrl,
          credentialProvider: () async => token,
        );

        await provider(
          'gpt-4-deployment',
        ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
        token = 'second-key';
        await provider(
          'gpt-4-deployment',
        ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

        expect(apiKeys, ['first-key', 'second-key']);
      },
    );

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await TestServer.start((request) async {
          writeOk(request);
        });
        addTearDown(server.close);

        final ownedProvider = AzureOpenAIProvider(
          endpoint: server.baseUrl,
          apiKey: 'test',
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider('gpt-4-deployment').doGenerate(
            LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
          ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = AzureOpenAIProvider(
          endpoint: server.baseUrl,
          apiKey: 'test',
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider('gpt-4-deployment').doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
        );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test(
      'response_format json_schema is serialized from a JSON response format',
      () async {
        late Map<String, dynamic> captured;
        final server = await TestServer.start((request) async {
          captured = await captureBody(request);
          writeOk(request);
        });
        addTearDown(server.close);

        final model = AzureOpenAIProvider(
          endpoint: server.baseUrl,
          apiKey: 'key',
        )('gpt-4o-deployment');
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('weather'),
            responseFormat: const LanguageModelV4JsonResponseFormat(
              schema: {'type': 'object'},
            ),
          ),
        );

        final rf = captured['response_format'] as Map<String, dynamic>;
        expect(rf['type'], 'json_schema');
      },
    );

    test('forwards providerOptions into the request body', () async {
      late Map<String, dynamic> captured;
      final server = await TestServer.start((request) async {
        captured = await captureBody(request);
        writeOk(request);
      });
      addTearDown(server.close);

      await AzureOpenAIProvider(endpoint: server.baseUrl, apiKey: 'key')(
        'gpt-4o-deployment',
      ).doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          providerOptions: const {
            'azure': {'data_residency': 'eu'},
          },
        ),
      );

      expect(captured['data_residency'], 'eu');
    });
  });

  group('Azure embedding doEmbed wire format', () {
    test('forwards embedding providerOptions', () async {
      late Map<String, dynamic> captured;
      final server = await TestServer.start((request) async {
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

      await AzureOpenAIProvider(endpoint: server.baseUrl, apiKey: 'key')
          .embedding('text-embedding-ada-002')
          .doEmbed(
            const EmbeddingModelV2CallOptions<String>(
              values: ['hello'],
              providerOptions: {
                'azure': {'dimensions': 3},
              },
            ),
          );

      expect(captured['dimensions'], 3);
    });

    test('posts to deployment /embeddings with api-key header and api-version '
        'query, parses embeddings in input order', () async {
      late Map<String, dynamic> captured;
      String? path;
      String? apiKeyHeader;
      String? query;
      final server = await TestServer.start((request) async {
        path = request.uri.path;
        apiKeyHeader = request.headers.value('api-key');
        query = request.uri.query;
        captured = await captureBody(request);

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'index': 0,
                'embedding': [0.1, 0.2, 0.3],
              },
              {
                'index': 1,
                'embedding': [0.4, 0.5, 0.6],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'secret-key',
        apiVersion: '2024-05-01-preview',
      ).embedding('text-embedding-ada-002');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['hello', 'world']),
      );

      // Routed to the deployment-scoped embeddings endpoint.
      expect(path, '/openai/deployments/text-embedding-ada-002/embeddings');
      // Azure auth wiring on the embedding path.
      expect(apiKeyHeader, 'secret-key');
      expect(query, contains('api-version=2024-05-01-preview'));
      // Request body carries input and the deployment as model.
      expect(captured['input'], ['hello', 'world']);
      expect(captured['model'], 'text-embedding-ada-002');
      // Embeddings parsed and paired with their source values, in order.
      expect(result.embeddings, hasLength(2));
      expect(result.embeddings[0].value, 'hello');
      expect(result.embeddings[0].embedding, [0.1, 0.2, 0.3]);
      expect(result.embeddings[1].value, 'world');
      expect(result.embeddings[1].embedding, [0.4, 0.5, 0.6]);
    });

    test('rejects a response with no data list', () async {
      final server = await TestServer.start((request) async {
        await captureBody(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'object': 'list'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'key',
      ).embedding('text-embedding-ada-002');

      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['only']),
        ),
        throwsA(isA<AiApiCallError>()),
      );
    });

    test('normalizes numeric vectors', () async {
      final server = await TestServer.start((request) async {
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
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result =
          await AzureOpenAIProvider(endpoint: server.baseUrl, apiKey: 'key')
              .embedding('text-embedding-ada-002')
              .doEmbed(
                const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
              );

      expect(result.embeddings, hasLength(2));
      expect(result.embeddings.map((embedding) => embedding.value), ['a', 'b']);
      expect(result.embeddings.map((embedding) => embedding.embedding), [
        [1.0, 2.5],
        [-3.0, 4.0],
      ]);
    });

    test(
      'endpoint ending with slash still posts to deployment embeddings once',
      () async {
        late String path;
        final server = await TestServer.start((request) async {
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

        final model = AzureOpenAIProvider(
          endpoint: '${server.baseUrl}/',
          apiKey: 'secret-key',
        ).embedding('text-embedding-ada-002');

        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['hello']),
        );

        expect(path, '/openai/deployments/text-embedding-ada-002/embeddings');
      },
    );

    test(
      'embedding credentials are resolved immediately before each request',
      () async {
        final apiKeys = <String?>[];
        final server = await TestServer.start((request) async {
          apiKeys.add(request.headers.value('api-key'));
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

        var token = 'first-key';
        final model = AzureOpenAIProvider(
          endpoint: server.baseUrl,
          credentialProvider: () async => token,
        ).embedding('text-embedding-ada-002');

        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['first']),
        );
        token = 'second-key';
        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['second']),
        );

        expect(apiKeys, ['first-key', 'second-key']);
      },
    );
  });
}
