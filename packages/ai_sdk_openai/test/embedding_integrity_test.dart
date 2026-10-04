import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/test_server.dart';

void main() {
  final invalidRows = <String, Object?>{
    'short': [
      {
        'index': 0,
        'embedding': [1],
      },
    ],
    'extra': [
      for (var i = 0; i < 3; i++)
        {
          'index': i,
          'embedding': [1],
        },
    ],
    'duplicate indices': [
      {
        'index': 0,
        'embedding': [1],
      },
      {
        'index': 0,
        'embedding': [2],
      },
    ],
    'out of range': [
      {
        'index': 0,
        'embedding': [1],
      },
      {
        'index': 2,
        'embedding': [2],
      },
    ],
    'mixed indexed and unindexed': [
      {
        'index': 0,
        'embedding': [1],
      },
      {
        'embedding': [2],
      },
    ],
    'empty vector': [
      {'index': 0, 'embedding': []},
      {
        'index': 1,
        'embedding': [2],
      },
    ],
    'unequal dimensions': [
      {
        'index': 0,
        'embedding': [1],
      },
      {
        'index': 1,
        'embedding': [2, 3],
      },
    ],
    'nonnumeric': [
      {
        'index': 0,
        'embedding': ['bad'],
      },
      {
        'index': 1,
        'embedding': [2],
      },
    ],
    'missing': null,
  };
  for (final entry in invalidRows.entries) {
    test('embedding endpoint rejects ${entry.key}', () async {
      final server = await TestServer.start((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': entry.value}));
        await request.response.close();
      });
      addTearDown(server.close);
      final model = OpenAIProvider(
        apiKey: 'fixture',
        baseUrl: server.baseUrl,
      ).embedding('fixture');
      await expectLater(
        model.doEmbed(const EmbeddingModelV2CallOptions(values: ['a', 'b'])),
        throwsA(isA<AiApiCallError>()),
      );
    });
  }

  test(
    'embedding wire indices preserve input association when rows arrive reversed',
    () async {
      final server = await TestServer.start((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'index': 1,
                'embedding': [2],
              },
              {
                'index': 0,
                'embedding': [1],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);
      final model = OpenAIProvider(
        apiKey: 'fixture',
        baseUrl: server.baseUrl,
      ).embedding('fixture');
      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions(values: ['a', 'b']),
      );
      expect(result.embeddings.map((entry) => entry.embedding), [
        [1.0],
        [2.0],
      ]);
      expect(result.embeddings.map((entry) => entry.value), ['a', 'b']);
    },
  );
}
