import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test('exposes provider escape hatches and embedding metadata', () {
    final dio = Dio();
    final provider = OpenAIProvider(apiKey: 'fixture', client: dio);
    addTearDown(() => dio.close(force: true));
    expect(provider.chat('gpt-4.1-mini').modelId, 'gpt-4.1-mini');
    final embedding = provider.embedding('text-embedding-3-small');
    expect(embedding.modelId, 'text-embedding-3-small');
    expect(embedding.provider, 'openai');
    expect(embedding.specificationVersion, 'v2');
    expect(embedding.maxEmbeddingsPerCall, 2048);
    expect(embedding.supportsParallelCalls, isTrue);
  });

  test('validates upload metadata and runtime source constraints', () {
    for (final upload in [
      OpenAIFileUpload(filename: ' ', purpose: 'batch', bytes: Uint8List(0)),
      OpenAIFileUpload(filename: 'file', purpose: ' ', bytes: Uint8List(0)),
    ]) {
      expect(upload.validate, throwsA(isA<OpenAIFileException>()));
    }
    expect(
      () => OpenAIFileUpload(filename: 'file', purpose: 'batch'),
      throwsA(isA<AssertionError>()),
    );
    for (final json in [
      {'id': '', 'created_at': 1, 'bytes': 0, 'filename': 'f', 'purpose': 'p'},
      {
        'id': 'f',
        'created_at': 1.5,
        'bytes': 0,
        'filename': 'f',
        'purpose': 'p',
      },
      {
        'id': 'f',
        'created_at': 1,
        'bytes': -1,
        'filename': 'f',
        'purpose': 'p',
      },
      {'id': 'f', 'created_at': 1, 'bytes': 0, 'filename': '', 'purpose': 'p'},
      {
        'id': 'f',
        'created_at': 1,
        'bytes': 0,
        'filename': 'f',
        'purpose': 'p',
        'expires_at': 'soon',
      },
      {
        'id': 'f',
        'created_at': 1,
        'bytes': 0,
        'filename': 'f',
        'purpose': 'p',
        'status': false,
      },
    ]) {
      expect(
        () => OpenAIFileMetadata.fromJson(json),
        throwsA(isA<OpenAIFileException>()),
      );
    }
    expect(
      OpenAIFileTimeoutException().toString(),
      'OpenAIFileTimeoutException',
    );
  });

  test('maps transport failures for each file operation', () async {
    final dio = Dio()..httpClientAdapter = _FailureAdapter();
    addTearDown(() => dio.close(force: true));
    final files = OpenAIFiles(
      client: dio,
      headers: () async => const {},
      baseUrl: 'https://api.openai.test/v1/',
    );
    const reference = DataContentProviderReference(
      namespace: 'openai',
      id: 'file-1',
    );
    final upload = OpenAIFileUpload(
      filename: 'file.txt',
      purpose: 'batch',
      bytes: Uint8List(0),
    );
    await expectLater(files.upload(upload), throwsA(isA<AiApiCallError>()));
    await expectLater(
      files.retrieve(reference),
      throwsA(isA<AiApiCallError>()),
    );
    await expectLater(
      files.download(reference),
      throwsA(isA<AiApiCallError>()),
    );
    await expectLater(files.delete(reference), throwsA(isA<AiApiCallError>()));
    await expectLater(
      files.download(
        const DataContentProviderReference(namespace: 'openai', id: '  '),
      ),
      throwsArgumentError,
    );
  });
}

class _FailureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"message":"failed"}}',
    503,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
