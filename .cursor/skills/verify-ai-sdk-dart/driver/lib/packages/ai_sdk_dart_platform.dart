// Verification checks for package:ai_sdk_dart (platform half): embeddings,
// media, rerank, middleware, registry, typed errors and retries, telemetry and
// testing utilities. See features/ai_sdk_dart-platform.md.
//
// Each check builds a real provider adapter (ai_sdk_openai, ai_sdk_cohere or
// the OpenAI-compatible chat model) against the loopback fixture server, calls
// the public ai_sdk_dart function, and asserts both the request that reached
// the server and the result the caller observed.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

// ---------------------------------------------------------------------------
// Builders and wire fixtures
// ---------------------------------------------------------------------------

OpenAIProvider _openai(CheckContext ctx, FixtureServer server) {
  final provider = OpenAIProvider(
    apiKey: 'verify-key',
    baseUrl: server.url('/v1'),
  );
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

CohereProvider _cohere(CheckContext ctx, FixtureServer server) {
  final provider = CohereProvider(
    apiKey: 'verify-cohere',
    baseUrl: server.url('/v2'),
  );
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

OpenAICompatibleChatLanguageModel _chat(
  CheckContext ctx,
  FixtureServer server,
) {
  final baseUrl = server.url('/v1');
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  ctx.onCleanup(() async => dio.close(force: true));
  return OpenAICompatibleChatLanguageModel(
    modelId: 'verify-model',
    config: OpenAICompatibleConfig(
      provider: 'verify-compat',
      baseUrl: baseUrl,
      client: dio,
      headers: () => {'Authorization': 'Bearer verify-key'},
    ),
  );
}

Map<String, Object?> _completion(
  String content, {
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': {'prompt_tokens': 11, 'completion_tokens': 7, 'total_tokens': 18},
};

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Map<String, Object?> _errorBody(String message, {String? type, String? code}) =>
    {
      'error': {'message': message, 'type': type, 'code': code},
    };

/// A real `/v1/embeddings` response: one row per input, vector derived from the
/// input so the caller can prove ordering.
FixtureResponse _embeddingsReply(FixtureRequest request) {
  final inputs = (request.jsonObject['input'] as List).cast<String>();
  return FixtureResponse.json({
    'object': 'list',
    'data': [
      for (var i = 0; i < inputs.length; i++)
        {
          'object': 'embedding',
          'index': i,
          'embedding': [inputs[i].length.toDouble(), 1.0, 0.5],
        },
    ],
    'model': 'text-embedding-3-small',
    'usage': {
      'prompt_tokens': inputs.length * 3,
      'total_tokens': inputs.length * 3,
    },
  });
}

// 1x1 PNG.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

FixtureResponse _imagesReply(int count) => FixtureResponse.json({
  'created': 1767225600,
  'data': [
    for (var i = 0; i < count; i++) {'b64_json': _pngBase64},
  ],
});

final _mp3Bytes = [0x49, 0x44, 0x33, 0x03, 0x00, 0x01, 0x02, 0x03];

FixtureResponse _rerankReply() => FixtureResponse.json({
  'id': 'rerank-verify',
  'results': [
    {'index': 1, 'relevance_score': 0.97},
    {'index': 0, 'relevance_score': 0.12},
  ],
  'meta': {
    'billed_units': {'search_units': 1},
  },
});

/// One fixture server that answers every category the registry check uses.
FutureOr<FixtureResponse> _allCategories(FixtureRequest request) {
  switch (request.path) {
    case '/v1/chat/completions':
      return FixtureResponse.json(_completion('registry says hi'));
    case '/v1/embeddings':
      return _embeddingsReply(request);
    case '/v1/images/generations':
      return _imagesReply(1);
    case '/v1/audio/speech':
      return FixtureResponse.bytes(_mp3Bytes, contentType: 'audio/mpeg');
    case '/v1/audio/transcriptions':
      return FixtureResponse.json({'text': 'transcribed by registry'});
    case '/v2/rerank':
      return _rerankReply();
  }
  return FixtureResponse.text('no route ${request.path}', status: 404);
}

Uint8List _audio() => Uint8List.fromList([1, 2, 3, 4, 5, 6]);

// ---------------------------------------------------------------------------
// Telemetry test doubles (the user implements these against their backend)
// ---------------------------------------------------------------------------

class _RecordedSpan implements TelemetrySpan {
  _RecordedSpan(this.name, this.attributes);
  final String name;
  final Map<String, Object?> attributes;
  final List<Object> exceptions = [];
  bool ended = false;
  Object? endError;

  @override
  void setAttribute(String key, Object? value) => attributes[key] = value;

  @override
  void recordException(Object error, {StackTrace? stackTrace}) =>
      exceptions.add(error);

  @override
  void end({Object? error}) {
    ended = true;
    endError = error;
  }
}

class _RecordingRecorder implements TelemetryRecorder {
  final List<_RecordedSpan> spans = [];

  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, Object?> attributes = const {},
  }) {
    final span = _RecordedSpan(name, Map.of(attributes));
    spans.add(span);
    return span;
  }
}

class _ThrowingRecorder implements TelemetryRecorder {
  @override
  TelemetrySpan startSpan(
    String name, {
    Map<String, Object?> attributes = const {},
  }) => throw StateError('telemetry backend is down');
}

// ---------------------------------------------------------------------------
// Middleware test doubles
// ---------------------------------------------------------------------------

class _OrderMiddleware extends LanguageModelMiddlewareBase {
  _OrderMiddleware(this.name, this.log);
  final String name;
  final List<String> log;

  @override
  Future<LanguageModelV4CallOptions> transformParams({
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    log.add('$name:transform');
    return LanguageModelV4CallOptions(
      prompt: options.prompt,
      headers: {...?options.headers, 'x-mw-${name.toLowerCase()}': name},
    );
  }

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    log.add('$name:before');
    final result = await doGenerate(options);
    log.add('$name:after');
    return result;
  }
}

class _ReverseEmbeddingMiddleware extends EmbeddingModelMiddlewareBase<String> {
  @override
  FutureOr<EmbeddingModelV2CallOptions<String>> transformParams({
    required EmbeddingModelV2CallOptions<String> options,
    required EmbeddingModelV2<String> model,
  }) => EmbeddingModelV2CallOptions<String>(
    values: options.values,
    headers: {...?options.headers, 'x-embed-mw': 'on'},
  );

  @override
  Future<EmbeddingModelV2GenerateResult<String>> wrapEmbed({
    required Future<EmbeddingModelV2GenerateResult<String>> Function(
      EmbeddingModelV2CallOptions<String> options,
    )
    doEmbed,
    required EmbeddingModelV2CallOptions<String> options,
    required EmbeddingModelV2<String> model,
  }) async {
    final result = await doEmbed(options);
    return EmbeddingModelV2GenerateResult<String>(
      embeddings: [
        for (final e in result.embeddings)
          EmbeddingModelV2Embedding(
            value: e.value,
            embedding: e.embedding.reversed.toList(),
          ),
      ],
      usage: result.usage,
    );
  }
}

class _FirstImageMiddleware extends ImageModelMiddlewareBase {
  @override
  FutureOr<ImageModelV3CallOptions> transformParams({
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  }) => ImageModelV3CallOptions(prompt: '${options.prompt} (styled)', n: 2);

  @override
  Future<ImageModelV3GenerateResult> wrapGenerate({
    required Future<ImageModelV3GenerateResult> Function(
      ImageModelV3CallOptions options,
    )
    doGenerate,
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  }) async {
    final result = await doGenerate(options);
    return ImageModelV3GenerateResult(
      images: result.images.take(1).toList(),
      usage: result.usage,
    );
  }
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

final List<Check> platformChecks = [
  // ---- Embeddings --------------------------------------------------------
  Check(
    id: 'embed-openai',
    feature: 'platform-embed',
    description:
        'embed sends POST /v1/embeddings with auth, model and input, and '
        'returns the vector and token usage.',
    run: (ctx) async {
      final server = await ctx.server(_embeddingsReply);
      final result = await embed(
        model: _openai(ctx, server).embedding('text-embedding-3-small'),
        value: 'hello world',
        headers: {'x-trace': 'abc'},
      );
      ctx.observe('embedding', result.embedding);
      ctx.observe('usage', result.usage?.tokens);
      final request = ctx.singleRequest(
        server,
        '/v1/embeddings',
        method: 'POST',
      );
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(request.headers['x-trace'], 'abc', 'custom header');
      ctx.expectEquals(body['model'], 'text-embedding-3-small', 'model');
      ctx.expectEquals(body['input'], ['hello world'], 'input');
      ctx.expectEquals(result.value, 'hello world', 'echoed value');
      ctx.expectEquals(result.embedding, [11.0, 1.0, 0.5], 'embedding');
      ctx.expectEquals(result.usage?.tokens, 3, 'usage tokens');
    },
  ),
  Check(
    id: 'embed-many-chunking',
    feature: 'platform-embed-many',
    description:
        'embedMany splits values by maxEmbeddingsPerCall, keeps input order '
        'and sums token usage across the calls.',
    run: (ctx) async {
      final server = await ctx.server(_embeddingsReply);
      final values = ['a', 'bb', 'ccc', 'dddd', 'eeeee'];
      final result = await embedMany(
        model: _openai(ctx, server).embedding('text-embedding-3-small'),
        values: values,
        maxEmbeddingsPerCall: 2,
      );
      final requests = ctx.requestsTo(server, '/v1/embeddings');
      final inputs = [for (final r in requests) r.jsonObject['input']];
      ctx.observe('requestInputs', inputs);
      ctx.observe('entries', [
        for (final e in result.embeddings)
          {'value': e.value, 'dim': e.embedding.length},
      ]);
      ctx.observe('usage', result.usage?.tokens);
      ctx.expectEquals(inputs, [
        ['a', 'bb'],
        ['ccc', 'dddd'],
        ['eeeee'],
      ], 'chunked request inputs');
      ctx.expectEquals(
        result.embeddings.map((e) => e.value).toList(),
        values,
        'result order',
      );
      ctx.expectEquals(
        result.embeddings.map((e) => e.embedding.first).toList(),
        [1.0, 2.0, 3.0, 4.0, 5.0],
        'vectors match their inputs',
      );
      ctx.expectEquals(result.usage?.tokens, 15, 'summed usage');
      final empty = await embedMany(
        model: _openai(ctx, server).embedding('text-embedding-3-small'),
        values: const <String>[],
      );
      ctx.expectEquals(empty.embeddings.length, 0, 'empty input result');
      ctx.expectEquals(
        ctx.requestsTo(server, '/v1/embeddings').length,
        3,
        'empty input sends no request',
      );
    },
  ),
  Check(
    id: 'embed-many-parallel',
    feature: 'platform-embed-many',
    description:
        'maxParallelCalls controls how many embedding requests are in flight '
        'at once (default one) and results stay in input order.',
    run: (ctx) async {
      var inFlight = 0;
      var peak = 0;
      final server = await ctx.server((request) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        inFlight--;
        return _embeddingsReply(request);
      });
      final model = _openai(ctx, server).embedding('text-embedding-3-small');
      final values = ['a', 'bb', 'ccc', 'dddd'];
      final serial = await embedMany(
        model: model,
        values: values,
        maxEmbeddingsPerCall: 1,
      );
      final serialPeak = peak;
      peak = 0;
      final parallel = await embedMany(
        model: model,
        values: values,
        maxEmbeddingsPerCall: 1,
        maxParallelCalls: 4,
      );
      ctx.observe('serialPeak', serialPeak);
      ctx.observe('parallelPeak', peak);
      ctx.expectEquals(serialPeak, 1, 'default concurrency is one');
      ctx.expect(peak >= 2, 'maxParallelCalls: 4 never overlapped requests');
      ctx.expectEquals(
        parallel.embeddings.map((e) => e.value).toList(),
        values,
        'parallel result order',
      );
      ctx.expectEquals(
        serial.embeddings.map((e) => e.embedding.first).toList(),
        parallel.embeddings.map((e) => e.embedding.first).toList(),
        'serial and parallel vectors agree',
      );
      await ctx.expectThrows<ArgumentError>(
        () => embedMany(model: model, values: values, maxParallelCalls: 0),
        'maxParallelCalls zero',
      );
    },
  ),
  Check(
    id: 'cosine-similarity',
    feature: 'platform-cosine',
    description:
        'cosineSimilarity returns 1, 0 and -1 for the textbook cases and '
        'rejects mismatched or empty vectors.',
    run: (ctx) async {
      ctx.expect(
        (cosineSimilarity([1, 2, 3], [2, 4, 6]) - 1).abs() < 1e-9,
        'same direction should score 1',
      );
      ctx.expectEquals(cosineSimilarity([1, 0], [0, 1]), 0.0, 'orthogonal');
      ctx.expectEquals(cosineSimilarity([1, 0], [-1, 0]), -1.0, 'opposite');
      ctx.expectEquals(cosineSimilarity([0, 0], [1, 1]), 0.0, 'zero vector');
      final server = await ctx.server(_embeddingsReply);
      final model = _openai(ctx, server).embedding('text-embedding-3-small');
      final a = await embed(model: model, value: 'abc');
      final b = await embed(model: model, value: 'abcd');
      final score = cosineSimilarity(a.embedding, b.embedding);
      ctx.observe('scoreOfEmbeddedVectors', score);
      ctx.expect(score > 0.9 && score <= 1.0, 'similar vectors score $score');
      await ctx.expectThrows<ArgumentError>(
        () async => cosineSimilarity([1, 2], [1]),
        'length mismatch',
      );
      await ctx.expectThrows<ArgumentError>(
        () async => cosineSimilarity([], []),
        'empty vectors',
      );
    },
  ),
  Check(
    id: 'embed-invalid-response',
    feature: 'platform-embed',
    description:
        'A model that returns the wrong number, order or dimension of '
        'vectors is rejected with AiInvalidEmbeddingResponseError.',
    run: (ctx) async {
      Future<void> run(List<EmbeddingModelV2Embedding<String>> rows) =>
          embedMany(model: _FixedEmbeddingModel(rows), values: ['x', 'y']);
      final tooFew = await ctx.expectThrows<AiInvalidEmbeddingResponseError>(
        () => run(const [
          EmbeddingModelV2Embedding(value: 'x', embedding: [1.0]),
        ]),
        'too few rows',
      );
      ctx.expectEquals(tooFew.expectedCount, 2, 'expectedCount');
      ctx.expectEquals(tooFew.actualCount, 1, 'actualCount');
      final swapped = await ctx.expectThrows<AiInvalidEmbeddingResponseError>(
        () => run(const [
          EmbeddingModelV2Embedding(value: 'y', embedding: [1.0]),
          EmbeddingModelV2Embedding(value: 'x', embedding: [1.0]),
        ]),
        'wrong order',
      );
      ctx.expectEquals(swapped.index, 0, 'first mismatched index');
      await ctx.expectThrows<AiInvalidEmbeddingResponseError>(
        () => run(const [
          EmbeddingModelV2Embedding(value: 'x', embedding: [1.0, 2.0]),
          EmbeddingModelV2Embedding(value: 'y', embedding: [1.0]),
        ]),
        'dimension mismatch',
      );
      await ctx.expectThrows<AiInvalidEmbeddingResponseError>(
        () => run([
          const EmbeddingModelV2Embedding(value: 'x', embedding: [1.0]),
          EmbeddingModelV2Embedding(value: 'y', embedding: [double.nan]),
        ]),
        'non-finite vector',
      );
    },
  ),

  // ---- Media and rerank ---------------------------------------------------
  Check(
    id: 'generate-image-openai',
    feature: 'platform-image',
    description:
        'generateImage sends POST /v1/images/generations and returns decoded '
        'PNG bytes; an empty result raises AiNoImageGeneratedError.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.jsonObject['prompt'] == 'nothing') {
          return FixtureResponse.json({'data': <Object>[]});
        }
        return _imagesReply(2);
      });
      final model = _openai(ctx, server).image('dall-e-2');
      final result = await generateImage(
        model: model,
        prompt: 'a red square',
        n: 2,
        size: '1024x1024',
      );
      final body = ctx.requestsTo(server, '/v1/images/generations').first;
      ctx.observe('imageCount', result.images.length);
      ctx.observe('mediaType', result.image.mediaType);
      ctx.expectEquals(
        body.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body.jsonObject['model'], 'dall-e-2', 'model');
      ctx.expectEquals(body.jsonObject['prompt'], 'a red square', 'prompt');
      ctx.expectEquals(body.jsonObject['n'], 2, 'n');
      ctx.expectEquals(body.jsonObject['size'], '1024x1024', 'size');
      ctx.expectEquals(
        body.jsonObject['response_format'],
        'b64_json',
        'response_format',
      );
      ctx.expectEquals(result.images.length, 2, 'image count');
      ctx.expectEquals(result.image.mediaType, 'image/png', 'media type');
      ctx.expectEquals(result.image.bytes.sublist(0, 4), [
        0x89,
        0x50,
        0x4E,
        0x47,
      ], 'PNG signature');
      ctx.expectEquals(result.usage?.imagesGenerated, 2, 'usage');
      ctx.expectEquals(
        decodeBase64Image(_pngBase64).length,
        result.image.bytes.length,
        'decodeBase64Image',
      );
      await ctx.expectThrows<AiNoImageGeneratedError>(
        () => generateImage(model: model, prompt: 'nothing'),
        'empty image result',
      );
    },
  ),
  Check(
    id: 'generate-speech-openai',
    feature: 'platform-speech',
    description:
        'generateSpeech sends POST /v1/audio/speech with voice, format and '
        'speed and returns the audio bytes with the response media type.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.jsonObject['input'] == 'silence') {
          return FixtureResponse.bytes(const [], contentType: 'audio/mpeg');
        }
        return FixtureResponse.bytes(_mp3Bytes, contentType: 'audio/mpeg');
      });
      final model = _openai(ctx, server).speech('tts-1');
      final result = await generateSpeech(
        model: model,
        text: 'Hello there.',
        voice: 'alloy',
        format: 'mp3',
        speed: 1.25,
      );
      final request = ctx.requestsTo(server, '/v1/audio/speech').first;
      final body = request.jsonObject;
      ctx.observe('audioBytes', result.audio.length);
      ctx.observe('mediaType', result.mediaType);
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'tts-1', 'model');
      ctx.expectEquals(body['input'], 'Hello there.', 'input');
      ctx.expectEquals(body['voice'], 'alloy', 'voice');
      ctx.expectEquals(body['response_format'], 'mp3', 'response_format');
      ctx.expectEquals(body['speed'], 1.25, 'speed');
      ctx.expectEquals(result.audio.toList(), _mp3Bytes, 'audio bytes');
      ctx.expectEquals(result.mediaType, 'audio/mpeg', 'media type');
      await ctx.expectThrows<AiNoSpeechGeneratedError>(
        () => generateSpeech(model: model, text: 'silence'),
        'empty audio',
      );
    },
  ),
  Check(
    id: 'transcribe-openai',
    feature: 'platform-transcribe',
    description:
        'transcribe uploads the audio as multipart form data with model, '
        'language and prompt and returns the transcript text.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.bodyText.contains('name="prompt"\r\n\r\nempty')) {
          return FixtureResponse.json({'text': ''});
        }
        return FixtureResponse.json({'text': 'hello from the audio'});
      });
      final model = _openai(ctx, server).transcription('whisper-1');
      final result = await transcribe(
        model: model,
        audio: _audio(),
        audioMediaType: 'audio/wav',
        language: 'en',
        prompt: 'greeting',
      );
      final request = ctx
          .requestsTo(server, '/v1/audio/transcriptions', method: 'POST')
          .first;
      final text = request.bodyText;
      ctx.observe('text', result.text);
      ctx.observe('contentType', request.headers['content-type']);
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expect(
        (request.headers['content-type'] ?? '').startsWith(
          'multipart/form-data',
        ),
        'request is not multipart',
      );
      ctx.expect(text.contains('name="model"\r\n\r\nwhisper-1'), 'model field');
      ctx.expect(text.contains('name="language"\r\n\r\nen'), 'language field');
      ctx.expect(
        text.contains('name="prompt"\r\n\r\ngreeting'),
        'prompt field',
      );
      ctx.expect(text.contains('filename="audio.wav"'), 'file name from type');
      ctx.expectEquals(result.text, 'hello from the audio', 'transcript');
      await ctx.expectThrows<AiNoTranscriptGeneratedError>(
        () => transcribe(model: model, audio: _audio(), prompt: 'empty'),
        'empty transcript',
      );
    },
  ),
  Check(
    id: 'rerank-cohere',
    feature: 'platform-rerank',
    description:
        'rerank sends POST /v2/rerank with query, documents and top_n and '
        'returns documents in ranked order with original indices.',
    run: (ctx) async {
      final server = await ctx.server((_) => _rerankReply());
      final result = await rerank(
        model: _cohere(ctx, server).rerank('rerank-english-v3.0'),
        query: 'capital of France',
        documents: ['Berlin is in Germany.', 'Paris is the capital of France.'],
        topN: 2,
      );
      final request = ctx.singleRequest(server, '/v2/rerank', method: 'POST');
      final body = request.jsonObject;
      ctx.observe('ranked', [
        for (final d in result.documents)
          {'index': d.index, 'score': d.relevanceScore, 'document': d.document},
      ]);
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-cohere',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'rerank-english-v3.0', 'model');
      ctx.expectEquals(body['query'], 'capital of France', 'query');
      ctx.expectEquals(body['top_n'], 2, 'top_n');
      ctx.expectEquals((body['documents'] as List).length, 2, 'documents');
      ctx.expectEquals(result.document.index, 1, 'top document index');
      ctx.expectEquals(
        result.document.document,
        'Paris is the capital of France.',
        'top document text',
      );
      ctx.expectEquals(result.document.relevanceScore, 0.97, 'top score');
      ctx.expectEquals(result.documents.map((d) => d.index).toList(), [
        1,
        0,
      ], 'ranked order');
    },
  ),
  Check(
    id: 'media-timeouts',
    feature: 'platform-timeout',
    description:
        'A Duration timeout aborts embed, generateImage, generateSpeech, '
        'transcribe and rerank with TimeoutException when the server is slow.',
    run: (ctx) async {
      final server = await ctx.server((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return _allCategories(request);
      });
      final openai = _openai(ctx, server);
      const limit = Duration(milliseconds: 120);
      final stopwatch = Stopwatch()..start();
      await ctx.expectThrows<TimeoutException>(
        () => embed(model: openai.embedding('e'), value: 'x', timeout: limit),
        'embed',
      );
      await ctx.expectThrows<TimeoutException>(
        () => embedMany(
          model: openai.embedding('e'),
          values: ['x'],
          timeout: limit,
        ),
        'embedMany',
      );
      await ctx.expectThrows<TimeoutException>(
        () => generateImage(
          model: openai.image('i'),
          prompt: 'p',
          timeout: limit,
        ),
        'generateImage',
      );
      await ctx.expectThrows<TimeoutException>(
        () => generateSpeech(
          model: openai.speech('s'),
          text: 't',
          timeout: limit,
        ),
        'generateSpeech',
      );
      await ctx.expectThrows<TimeoutException>(
        () => transcribe(
          model: openai.transcription('w'),
          audio: _audio(),
          timeout: limit,
        ),
        'transcribe',
      );
      await ctx.expectThrows<TimeoutException>(
        () => rerank(
          model: _cohere(ctx, server).rerank('r'),
          query: 'q',
          documents: ['d'],
          timeout: limit,
        ),
        'rerank',
      );
      ctx.observe('elapsedMs', stopwatch.elapsedMilliseconds);
      ctx.expect(
        stopwatch.elapsedMilliseconds < 3500,
        'timeouts did not fire before the server replied',
      );
      ctx.expectEquals(
        server.requests.length,
        6,
        'requests that reached server',
      );
      final ok = await embed(
        model: openai.embedding('e'),
        value: 'x',
        timeout: const Duration(seconds: 5),
      );
      ctx.expectEquals(ok.embedding.length, 3, 'a generous timeout succeeds');
    },
  ),

  // ---- Language-model middleware ------------------------------------------
  Check(
    id: 'middleware-extract-reasoning',
    feature: 'platform-middleware-language',
    description:
        'extractReasoningMiddleware moves <think> blocks into reasoning for '
        'generateText.',
    run: (ctx) async {
      final generateServer = await ctx.server(
        (_) => FixtureResponse.json(
          _completion('<think>2 plus 2 is 4</think>The answer is 4.'),
        ),
      );
      final wrapped = wrapLanguageModel(
        model: _chat(ctx, generateServer),
        middleware: extractReasoningMiddleware(),
      );
      final generated = await generateText(
        model: wrapped,
        prompt: 'What is 2+2?',
      );
      ctx.observe('generate.text', generated.text);
      ctx.observe('generate.reasoning', generated.reasoningText);
      ctx.expectEquals(generated.text, 'The answer is 4.', 'generate text');
      ctx.expectEquals(
        generated.reasoningText,
        '2 plus 2 is 4',
        'generate reasoning',
      );
      ctx.expectEquals(generated.reasoning.length, 1, 'reasoning parts');
      ctx.expect(
        !jsonEncode(
          ctx.singleRequest(generateServer, '/v1/chat/completions').jsonObject,
        ).contains('<think>'),
        'request unexpectedly carried the tag',
      );
    },
  ),
  Check(
    id: 'middleware-extract-reasoning-stream',
    feature: 'platform-middleware-language',
    description:
        'extractReasoningMiddleware over an SSE stream whose <think> tags are '
        'split across deltas: reasoning and the final text both reach the '
        'streamText result.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'content': '<thi'}),
          _chunk({'content': 'nk>plan it '}),
          _chunk({'content': 'carefully</think>Do'}),
          _chunk({'content': 'ne.'}),
          _chunk({}, finish: 'stop'),
        ], done: true),
      );
      final streamed = await streamText(
        model: wrapLanguageModel(
          model: _chat(ctx, server),
          middleware: extractReasoningMiddleware(),
        ),
        prompt: 'think',
      );
      final pieces = streamed.textStream.toList();
      final reasoning = await streamed.reasoningText;
      final joined = (await pieces).join();
      final text = await streamed.text;
      ctx.observe('stream.textStream', joined);
      ctx.observe('stream.text', text);
      ctx.observe('stream.reasoning', reasoning);
      ctx.expectEquals(reasoning, 'plan it carefully', 'stream reasoning');
      ctx.expectEquals(joined, 'Done.', 'textStream pieces');
      ctx.expectEquals(text, 'Done.', 'final text future');
    },
  ),
  Check(
    id: 'middleware-extract-reasoning-stream-one-delta',
    feature: 'platform-middleware-language',
    description:
        'extractReasoningMiddleware when one SSE delta holds the whole '
        '<think>...</think> block followed by the answer.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'content': '<think>plan</think>Done.'}),
          _chunk({}, finish: 'stop'),
        ], done: true),
      );
      final streamed = await streamText(
        model: wrapLanguageModel(
          model: _chat(ctx, server),
          middleware: extractReasoningMiddleware(),
        ),
        prompt: 'think',
      );
      final text = await streamed.text;
      final reasoning = await streamed.reasoningText;
      ctx.observe('stream.text', text);
      ctx.observe('stream.reasoning', reasoning);
      ctx.expectEquals(reasoning, 'plan', 'reasoning');
      ctx.expectEquals(text, 'Done.', 'text');
    },
  ),
  Check(
    id: 'middleware-extract-json',
    feature: 'platform-middleware-language',
    description:
        'extractJsonMiddleware strips a ```json fence so the caller gets bare '
        'JSON text.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _completion('```json\n{"city":"Tokyo","pop":14}\n```'),
        ),
      );
      final raw = await generateText(model: _chat(ctx, server), prompt: 'json');
      final cleaned = await generateText(
        model: wrapLanguageModel(
          model: _chat(ctx, server),
          middleware: extractJsonMiddleware(),
        ),
        prompt: 'json',
      );
      ctx.observe('raw', raw.text);
      ctx.observe('cleaned', cleaned.text);
      ctx.expect(raw.text.startsWith('```'), 'fixture should be fenced');
      ctx.expectEquals(
        cleaned.text,
        '{"city":"Tokyo","pop":14}',
        'stripped text',
      );
      ctx.expectEquals(jsonDecode(cleaned.text), {
        'city': 'Tokyo',
        'pop': 14,
      }, 'decoded JSON');
    },
  ),
  Check(
    id: 'middleware-simulate-streaming',
    feature: 'platform-middleware-language',
    description:
        'simulateStreamingMiddleware lets streamText run on a model call that '
        'is not streamed on the wire.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion('Whole answer at once.')),
      );
      final result = await streamText(
        model: wrapLanguageModel(
          model: _chat(ctx, server),
          middleware: simulateStreamingMiddleware(),
        ),
        prompt: 'stream me',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      ctx.observe('deltas', deltas);
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      ctx.expect(body['stream'] != true, 'wire request must not stream');
      ctx.expectEquals(deltas.join(), 'Whole answer at once.', 'streamed text');
      ctx.expectEquals(usage?.inputTokens.total, 11, 'usage from generate');
      ctx.expectEquals(
        await result.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish',
      );
    },
  ),
  Check(
    id: 'middleware-default-settings',
    feature: 'platform-middleware-language',
    description:
        'defaultSettingsMiddleware fills temperature, topP, seed and max '
        'tokens on the wire; a per-call value wins.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion('ok')),
      );
      final model = wrapLanguageModel(
        model: _chat(ctx, server),
        middleware: defaultSettingsMiddleware(
          temperature: 0.3,
          topP: 0.9,
          seed: 7,
          maxOutputTokens: 77,
        ),
      );
      await generateText(model: model, prompt: 'one');
      await generateText(model: model, prompt: 'two', temperature: 0.8);
      final requests = ctx.requestsTo(server, '/v1/chat/completions');
      final first = requests[0].jsonObject;
      final second = requests[1].jsonObject;
      ctx.observe('first', {
        'temperature': first['temperature'],
        'top_p': first['top_p'],
        'seed': first['seed'],
        'max': first['max_completion_tokens'] ?? first['max_tokens'],
      });
      ctx.expectEquals(first['temperature'], 0.3, 'default temperature');
      ctx.expectEquals(first['top_p'], 0.9, 'default top_p');
      ctx.expectEquals(first['seed'], 7, 'default seed');
      ctx.expectEquals(
        first['max_completion_tokens'] ?? first['max_tokens'],
        77,
        'default max tokens',
      );
      ctx.expectEquals(second['temperature'], 0.8, 'per-call temperature wins');
      ctx.expectEquals(second['seed'], 7, 'other defaults still apply');
    },
  ),
  Check(
    id: 'middleware-tool-examples',
    feature: 'platform-middleware-language',
    description:
        'addToolInputExamplesMiddleware appends the tool input examples to '
        'the tool description sent on the wire.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion('ok')),
      );
      final weather = tool<Map<String, dynamic>, String>(
        description: 'Get the weather.',
        inputSchema: Schema(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
          fromJson: (json) => json,
        ),
        inputExamples: const [
          ToolInputExample(input: {'city': 'Paris'}),
        ],
        execute: (input, _) async => 'sunny',
      );
      Future<String> descriptionFor(LanguageModelV4 model) async {
        await generateText(
          model: model,
          prompt: 'w',
          tools: {'getWeather': weather},
        );
        final body = ctx
            .requestsTo(server, '/v1/chat/completions')
            .last
            .jsonObject;
        final fn = ((body['tools'] as List).single as Map)['function'] as Map;
        return fn['description'] as String;
      }

      final plain = await descriptionFor(_chat(ctx, server));
      final enriched = await descriptionFor(
        wrapLanguageModel(
          model: _chat(ctx, server),
          middleware: addToolInputExamplesMiddleware(),
        ),
      );
      ctx.observe('plain', plain);
      ctx.observe('enriched', enriched);
      ctx.expect(
        !plain.contains('Examples:'),
        'plain description has examples',
      );
      ctx.expect(
        enriched.startsWith('Get the weather.'),
        'base description kept',
      );
      ctx.expect(enriched.contains('Examples:'), 'examples header missing');
      ctx.expect(enriched.contains('{"city":"Paris"}'), 'example JSON missing');
    },
  ),
  Check(
    id: 'middleware-chain-order',
    feature: 'platform-middleware-language',
    description:
        'A middleware list runs first-to-last on the way in and last-to-first '
        'on the way out, and each transformParams change reaches the wire.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion('ok')),
      );
      final log = <String>[];
      final model = wrapLanguageModel(
        model: _chat(ctx, server),
        middleware: [_OrderMiddleware('A', log), _OrderMiddleware('B', log)],
      );
      await generateText(model: model, prompt: 'order');
      ctx.observe('log', log);
      ctx.expectEquals(log, [
        'A:transform',
        'A:before',
        'B:transform',
        'B:before',
        'B:after',
        'A:after',
      ], 'middleware order');
      final request = ctx.singleRequest(server, '/v1/chat/completions');
      ctx.expectEquals(
        request.headers['x-mw-b'],
        'B',
        'inner middleware header',
      );
      ctx.expect(model.modelId == 'verify-model', 'wrapper keeps the model id');
      ctx.expectThrowsSync<ArgumentError>(
        () => wrapLanguageModel(model: model, middleware: 'not a middleware'),
        'invalid middleware argument',
      );
    },
  ),
  Check(
    id: 'middleware-embedding-image',
    feature: 'platform-middleware-media',
    description:
        'wrapEmbeddingModel and wrapImageModel run transformParams and the '
        'wrap hook on real OpenAI-format requests.',
    run: (ctx) async {
      final server = await ctx.server(_allCategories);
      final openai = _openai(ctx, server);
      final embedModel = wrapEmbeddingModel<String>(
        model: openai.embedding('text-embedding-3-small'),
        middleware: _ReverseEmbeddingMiddleware(),
      );
      final embedded = await embed(model: embedModel, value: 'abc');
      final imageModel = wrapImageModel(
        model: openai.image('dall-e-2'),
        middleware: _FirstImageMiddleware(),
      );
      final image = await generateImage(model: imageModel, prompt: 'cat');
      final embedRequest = ctx.singleRequest(server, '/v1/embeddings');
      final imageRequest = ctx.singleRequest(server, '/v1/images/generations');
      ctx.observe('embedding', embedded.embedding);
      ctx.observe('imageCount', image.images.length);
      ctx.expectEquals(
        embedRequest.headers['x-embed-mw'],
        'on',
        'embedding header',
      );
      ctx.expectEquals(embedded.embedding, [0.5, 1.0, 3.0], 'reversed vector');
      ctx.expectEquals(embedModel.modelId, 'text-embedding-3-small', 'modelId');
      ctx.expectEquals(
        embedModel.maxEmbeddingsPerCall,
        2048,
        'limit forwarded',
      );
      ctx.expectEquals(
        imageRequest.jsonObject['prompt'],
        'cat (styled)',
        'prompt',
      );
      ctx.expectEquals(imageRequest.jsonObject['n'], 2, 'n set by middleware');
      ctx.expectEquals(image.images.length, 1, 'wrapGenerate kept one image');
    },
  ),

  // ---- Registry -----------------------------------------------------------
  Check(
    id: 'registry-resolve',
    feature: 'platform-registry',
    description:
        'createProviderRegistry resolves "provider:modelId" for all six model '
        'categories and each resolved model works over HTTP.',
    run: (ctx) async {
      final server = await ctx.server(_allCategories);
      final openai = _openai(ctx, server);
      final cohere = _cohere(ctx, server);
      final registry = createProviderRegistry({
        'openai': RegistrableProvider(
          languageModelFactory: (id) => _chat(ctx, server),
          embeddingModelFactory: openai.embedding,
          imageModelFactory: openai.image,
          speechModelFactory: openai.speech,
          transcriptionModelFactory: openai.transcription,
        ),
        'cohere': RegistrableProvider(
          languageModelFactory: cohere.call,
          rerankModelFactory: cohere.rerank,
        ),
      });
      final text = await generateText(
        model: registry.languageModel('openai:gpt-verify'),
        prompt: 'hi',
      );
      final vector = await embed(
        model: registry.textEmbeddingModel('openai:text-embedding-3-small'),
        value: 'abc',
      );
      final image = await generateImage(
        model: registry.imageModel('openai:dall-e-3'),
        prompt: 'cat',
      );
      final speech = await generateSpeech(
        model: registry.speechModel('openai:tts-1'),
        text: 'hi',
      );
      final transcript = await transcribe(
        model: registry.transcriptionModel('openai:whisper-1'),
        audio: _audio(),
      );
      final ranked = await rerank(
        model: registry.rerankModel('cohere:rerank-english-v3.0'),
        query: 'q',
        documents: ['a', 'b'],
      );
      ctx.observe('paths', [for (final r in server.requests) r.path]);
      ctx.expectEquals(text.text, 'registry says hi', 'language');
      ctx.expectEquals(vector.embedding.length, 3, 'embedding');
      ctx.expectEquals(image.images.length, 1, 'image');
      ctx.expectEquals(speech.audio.length, _mp3Bytes.length, 'speech');
      ctx.expectEquals(
        transcript.text,
        'transcribed by registry',
        'transcription',
      );
      ctx.expectEquals(ranked.document.index, 1, 'rerank');
      ctx.expectEquals(
        server.requests.map((r) => r.path).toList(),
        [
          '/v1/chat/completions',
          '/v1/embeddings',
          '/v1/images/generations',
          '/v1/audio/speech',
          '/v1/audio/transcriptions',
          '/v2/rerank',
        ],
        'one request per category, in call order',
      );
      ctx.expectEquals(
        registry.textEmbeddingModel('openai:text-embedding-3-small').modelId,
        'text-embedding-3-small',
        'resolved model id',
      );
      ctx.expectEquals(
        registry.rerankModel('cohere:rerank-v4.0').provider,
        'cohere',
        'cohere provider name',
      );
    },
  ),
  Check(
    id: 'registry-errors',
    feature: 'platform-registry',
    description:
        'The registry rejects unknown providers and ids without a colon with '
        'ArgumentError, splits only at the first colon, and reports missing '
        'factories with UnsupportedError.',
    run: (ctx) async {
      final seen = <String>[];
      final registry = createProviderRegistry({
        'acme': RegistrableProvider(
          languageModelFactory: (id) {
            seen.add(id);
            return MockLanguageModelV4(modelId: id, provider: 'acme');
          },
        ),
      });
      final unknown = ctx.expectThrowsSync<ArgumentError>(
        () => registry.languageModel('nope:model'),
        'unknown provider',
      );
      ctx.expect(
        '${unknown.message}'.contains('No provider registered for "nope"') &&
            '${unknown.message}'.contains('acme'),
        'unknown provider message does not list providers: ${unknown.message}',
      );
      final noColon = ctx.expectThrowsSync<ArgumentError>(
        () => registry.languageModel('justamodel'),
        'missing colon',
      );
      ctx.expect(
        '${noColon.message}'.contains('provider:modelId'),
        'format hint missing',
      );
      final model = registry.languageModel('acme:ft:base:custom-1');
      ctx.expectEquals(model.modelId, 'ft:base:custom-1', 'colons in model id');
      ctx.expectEquals(seen, ['ft:base:custom-1'], 'factory input');
      for (final call in <String, Object Function()>{
        'embedding': () => registry.textEmbeddingModel('acme:x'),
        'image': () => registry.imageModel('acme:x'),
        'speech': () => registry.speechModel('acme:x'),
        'transcription': () => registry.transcriptionModel('acme:x'),
        'rerank': () => registry.rerankModel('acme:x'),
      }.entries) {
        ctx.expectThrowsSync<UnsupportedError>(
          call.value,
          'missing ${call.key} factory',
        );
      }
    },
  ),
  Check(
    id: 'custom-provider',
    feature: 'platform-registry',
    description:
        'customProvider serves named models per category, falls back to the '
        'fallback factory, and throws ArgumentError otherwise.',
    run: (ctx) async {
      final server = await ctx.server(_allCategories);
      final openai = _openai(ctx, server);
      final provider = customProvider(
        languageModels: {
          'fast': MockLanguageModelV4(response: [mockText('mock reply')]),
        },
        embeddingModels: {'embed': openai.embedding('text-embedding-3-small')},
        imageModels: {'img': openai.image('dall-e-3')},
        speechModels: {'voice': openai.speech('tts-1')},
        transcriptionModels: {'ears': openai.transcription('whisper-1')},
        fallbackLanguageModel: (id) => MockLanguageModelV4(
          modelId: id,
          response: [mockText('fallback $id')],
        ),
      );
      final named = await generateText(
        model: provider.languageModel('fast'),
        prompt: 'x',
      );
      final fallback = await generateText(
        model: provider.languageModel('anything'),
        prompt: 'x',
      );
      ctx.expectEquals(named.text, 'mock reply', 'named language model');
      ctx.expectEquals(
        fallback.text,
        'fallback anything',
        'fallback language model',
      );
      final vector = await embed(
        model: provider.textEmbeddingModel('embed'),
        value: 'ab',
      );
      final image = await generateImage(
        model: provider.imageModel('img'),
        prompt: 'p',
      );
      final speech = await generateSpeech(
        model: provider.speechModel('voice'),
        text: 't',
      );
      final transcript = await transcribe(
        model: provider.transcriptionModel('ears'),
        audio: _audio(),
      );
      ctx.observe('paths', [for (final r in server.requests) r.path]);
      ctx.expectEquals(vector.embedding.first, 2.0, 'embedding');
      ctx.expectEquals(image.images.length, 1, 'image');
      ctx.expectEquals(speech.mediaType, 'audio/mpeg', 'speech');
      ctx.expectEquals(
        transcript.text,
        'transcribed by registry',
        'transcription',
      );
      final missing = ctx.expectThrowsSync<ArgumentError>(
        () => provider.textEmbeddingModel('unknown'),
        'unknown embedding',
      );
      ctx.expect('${missing.message}'.contains('embed'), 'message lists names');
      ctx.expectThrowsSync<ArgumentError>(
        () => provider.imageModel('unknown'),
        'unknown image',
      );
      final registry = createProviderRegistry({
        'mine': RegistrableProvider(
          languageModelFactory: provider.languageModel,
          embeddingModelFactory: provider.textEmbeddingModel,
        ),
      });
      ctx.expectEquals(
        (await generateText(
          model: registry.languageModel('mine:fast'),
          prompt: 'x',
        )).text,
        'mock reply',
        'custom provider inside a registry',
      );
    },
  ),

  // ---- Errors and retries -------------------------------------------------
  Check(
    id: 'errors-api-call',
    feature: 'platform-errors',
    description:
        'Non-2xx responses from embeddings, image, speech, transcription and '
        'rerank surface as AiApiCallError with status, message, type, code, '
        'url, body and the right isRetryable flag.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        switch (request.index) {
          case 0:
            return FixtureResponse.json(
              _errorBody(
                'Incorrect API key provided.',
                type: 'invalid_request_error',
                code: 'invalid_api_key',
              ),
              status: 401,
            );
          case 1:
            return FixtureResponse.text('upstream exploded', status: 502);
          case 2:
            return FixtureResponse.json(
              _errorBody('Too many requests.'),
              status: 429,
            );
          case 3:
            return FixtureResponse.json(_errorBody('Bad size.'), status: 400);
          default:
            return FixtureResponse.json(_errorBody('Conflict.'), status: 409);
        }
      });
      final openai = _openai(ctx, server);
      final auth = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: openai.embedding('e'), value: 'x'),
        'embed 401',
      );
      ctx.expectEquals(auth.statusCode, 401, 'statusCode');
      ctx.expectEquals(auth.message, 'Incorrect API key provided.', 'message');
      ctx.expectEquals(auth.type, 'invalid_request_error', 'type');
      ctx.expectEquals(auth.code, 'invalid_api_key', 'code');
      ctx.expect(
        (auth.url ?? '').endsWith('/v1/embeddings'),
        'url ${auth.url}',
      );
      ctx.expect(
        (auth.responseBody ?? '').contains('invalid_api_key'),
        'raw body kept',
      );
      ctx.expect(!auth.isRetryable, '401 must not be retryable');
      final gateway = await ctx.expectThrows<AiApiCallError>(
        () => generateImage(model: openai.image('i'), prompt: 'p'),
        'image 502',
      );
      ctx.expectEquals(gateway.statusCode, 502, 'image status');
      ctx.expectEquals(
        gateway.message,
        'upstream exploded',
        'non-JSON body becomes message',
      );
      ctx.expect(gateway.isRetryable, '5xx must be retryable');
      final limited = await ctx.expectThrows<AiApiCallError>(
        () => generateSpeech(model: openai.speech('s'), text: 't'),
        'speech 429',
      );
      ctx.expectEquals(limited.statusCode, 429, 'speech status');
      ctx.expect(limited.isRetryable, '429 must be retryable');
      final badRequest = await ctx.expectThrows<AiApiCallError>(
        () => transcribe(model: openai.transcription('w'), audio: _audio()),
        'transcribe 400',
      );
      ctx.expect(!badRequest.isRetryable, '400 must not be retryable');
      final conflict = await ctx.expectThrows<AiApiCallError>(
        () => rerank(
          model: _cohere(ctx, server).rerank('r'),
          query: 'q',
          documents: ['d'],
        ),
        'rerank 409',
      );
      ctx.expectEquals(conflict.statusCode, 409, 'rerank status');
      ctx.expect(conflict.isRetryable, '409 must be retryable');
      ctx.expect(AiApiCallError.isInstance(conflict), 'isInstance');
      final AiSdkError asSdkError = auth;
      ctx.expect(
        asSdkError.toString().startsWith('AiApiCallError: '),
        'toString ${asSdkError.toString()}',
      );
      ctx.expectEquals(
        server.requests.length,
        5,
        'non-chat calls are not retried',
      );
    },
  ),
  Check(
    id: 'retry-exhausted',
    feature: 'platform-retry',
    description:
        'generateText retries a retryable 503 maxRetries times, then throws '
        'AiRetryError with the attempt count and the error history.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _errorBody('Overloaded.', type: 'server_error'),
          status: 503,
        ),
      );
      final error = await ctx.expectThrows<AiRetryError>(
        () => generateText(
          model: _chat(ctx, server),
          prompt: 'hi',
          maxRetries: 2,
        ),
        'generateText',
      );
      ctx.observe('attempts', error.attempts);
      ctx.observe('requests', server.requests.length);
      ctx.expectEquals(server.requests.length, 3, 'one try plus two retries');
      ctx.expectEquals(error.attempts, 3, 'attempts');
      ctx.expectEquals(error.errors.length, 3, 'error history');
      final last = error.lastError;
      ctx.expect(last is AiApiCallError, 'lastError is ${last.runtimeType}');
      ctx.expectEquals((last as AiApiCallError).statusCode, 503, 'last status');
      ctx.expectEquals(last.message, 'Overloaded.', 'last message');
      final immediate = await ctx.expectThrows<AiRetryError>(
        () => generateText(
          model: _chat(ctx, server),
          prompt: 'hi',
          maxRetries: 0,
        ),
        'maxRetries 0',
      );
      ctx.expectEquals(immediate.attempts, 1, 'maxRetries 0 attempts');
      ctx.expectEquals(
        server.requests.length,
        4,
        'maxRetries 0 sends one request',
      );
    },
  ),
  Check(
    id: 'retry-recovers',
    feature: 'platform-retry',
    description:
        'A retryable 500 followed by a 200 succeeds without error; a '
        'non-retryable 400 is not retried and is not wrapped in AiRetryError.',
    run: (ctx) async {
      final flaky = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(_errorBody('Try again.'), status: 500);
        }
        return FixtureResponse.json(_completion('recovered'));
      });
      final result = await generateText(model: _chat(ctx, flaky), prompt: 'hi');
      ctx.observe('text', result.text);
      ctx.expectEquals(result.text, 'recovered', 'text after retry');
      ctx.expectEquals(
        flaky.requests.length,
        2,
        'requests after a transient 500',
      );

      final strict = await ctx.server(
        (_) => FixtureResponse.json(
          _errorBody('Bad request.', code: 'bad'),
          status: 400,
        ),
      );
      final error = await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: _chat(ctx, strict),
          prompt: 'hi',
          maxRetries: 5,
        ),
        'non-retryable',
      );
      ctx.expectEquals(error.statusCode, 400, 'status');
      ctx.expectEquals(strict.requests.length, 1, 'a 400 is sent once');
    },
  ),
  Check(
    id: 'retry-after-header',
    feature: 'platform-retry',
    description:
        'A numeric Retry-After header on a 429 sets the wait before the next '
        'attempt.',
    run: (ctx) async {
      final times = <DateTime>[];
      final server = await ctx.server((request) {
        times.add(DateTime.now());
        if (request.index == 0) {
          return FixtureResponse.json(
            _errorBody('Slow down.', type: 'rate_limit'),
            status: 429,
            headers: {'retry-after': '1'},
          );
        }
        return FixtureResponse.json(_completion('after the wait'));
      });
      final result = await generateText(
        model: _chat(ctx, server),
        prompt: 'hi',
      );
      final gapMs = times[1].difference(times[0]).inMilliseconds;
      ctx.observe('gapMs', gapMs);
      ctx.expectEquals(result.text, 'after the wait', 'text');
      ctx.expectEquals(server.requests.length, 2, 'requests');
      ctx.expect(
        gapMs >= 900,
        'waited only ${gapMs}ms; the default backoff is at most 100ms, so Retry-After: 1 was ignored',
      );
      ctx.expect(
        gapMs < 3000,
        'waited ${gapMs}ms, far more than Retry-After: 1',
      );
    },
  ),

  // ---- Telemetry ----------------------------------------------------------
  Check(
    id: 'telemetry-spans-metrics',
    feature: 'platform-telemetry',
    description:
        'TelemetrySettings sends a span with model, function id, metadata, '
        'usage and finish reason to the recorder and metrics to the sink, for '
        'generateText and streamText.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => (request.jsonObject['stream'] == true)
            ? FixtureResponse.sse([
                _chunk({'role': 'assistant', 'content': 'streamed'}),
                _chunk({}, finish: 'stop'),
              ], done: true)
            : FixtureResponse.json(_completion('telemetry ok')),
      );
      final recorder = _RecordingRecorder();
      final metrics = <TelemetryMetric>[];
      final settings = TelemetrySettings(
        isEnabled: true,
        functionId: 'verify-fn',
        metadata: const {'tenant': 'acme'},
        recorder: recorder,
        metricSink: CallbackTelemetryMetricSink(metrics.add),
      );
      await generateText(
        model: _chat(ctx, server),
        prompt: 'hi',
        telemetry: settings,
      );
      final span = recorder.spans.single;
      ctx.observe('span', {
        'name': span.name,
        'attributes': span.attributes,
        'ended': span.ended,
      });
      ctx.observe('metrics', [for (final m in metrics) '${m.name}=${m.value}']);
      ctx.expectEquals(span.name, 'ai.generateText', 'span name');
      ctx.expect(span.ended, 'span was not ended');
      ctx.expectEquals(
        span.attributes[AiTelemetryKeys.modelProvider],
        'verify-compat',
        'provider attribute',
      );
      ctx.expectEquals(
        span.attributes[AiTelemetryKeys.modelId],
        'verify-model',
        'model attribute',
      );
      ctx.expectEquals(
        span.attributes['ai.telemetry.functionId'],
        'verify-fn',
        'functionId',
      );
      ctx.expectEquals(span.attributes['tenant'], 'acme', 'metadata');
      ctx.expectEquals(
        span.attributes[AiTelemetryKeys.promptTokens],
        11,
        'prompt tokens',
      );
      ctx.expectEquals(
        span.attributes[AiTelemetryKeys.completionTokens],
        7,
        'completion tokens',
      );
      ctx.expectEquals(
        span.attributes['ai.finishReason'],
        'stop',
        'finish reason',
      );
      ctx.expect(span.endError == null, 'successful call ended with an error');
      Map<String, TelemetryMetric> byName() => {
        for (final m in metrics) m.name: m,
      };
      final seen = byName();
      ctx.expectEquals(
        seen[AiTelemetryMetrics.success]?.value,
        1,
        'success metric',
      );
      ctx.expectEquals(
        seen[AiTelemetryMetrics.stepCount]?.value,
        1,
        'step count',
      );
      ctx.expectEquals(
        seen[AiTelemetryMetrics.retryCount]?.value,
        0,
        'retry count',
      );
      ctx.expectEquals(
        seen[AiTelemetryMetrics.usageKnown]?.value,
        1,
        'usage known',
      );
      ctx.expect(
        seen.containsKey(AiTelemetryMetrics.totalMs),
        'totalMs metric',
      );
      final total = seen[AiTelemetryMetrics.totalMs]!;
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.operation],
        'generateText',
        'operation attr',
      );
      ctx.expectEquals(
        total.attributes[AiTelemetryKeys.operationStatus],
        'success',
        'status attr',
      );
      ctx.expectEquals(
        total.attributes['tenant'],
        'acme',
        'metadata on metrics',
      );

      final streamed = await streamText(
        model: _chat(ctx, server),
        prompt: 'hi',
        telemetry: settings,
      );
      await streamed.text;
      await streamed.finishReason;
      final streamSpan = recorder.spans.last;
      ctx.expectEquals(
        streamSpan.name,
        'ai.streamText',
        'streamText span name',
      );
      ctx.expectEquals(
        streamSpan.attributes['ai.telemetry.functionId'],
        'verify-fn',
        'stream functionId',
      );
      ctx.expect(
        metrics.any(
          (m) => m.attributes[AiTelemetryKeys.operation] == 'streamText',
        ),
        'streamText emitted no metrics',
      );

      final off = _RecordingRecorder();
      await generateText(
        model: _chat(ctx, server),
        prompt: 'hi',
        telemetry: TelemetrySettings(recorder: off),
      );
      ctx.expectEquals(
        off.spans.length,
        0,
        'disabled telemetry records nothing',
      );
    },
  ),
  Check(
    id: 'telemetry-privacy',
    feature: 'platform-telemetry',
    description:
        'Prompts are left out of spans unless captureInputs is on, and '
        'redactAttribute can rewrite or drop any attribute.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion('ok')),
      );
      Future<_RecordedSpan> spanFor(
        TelemetrySettings settings,
        _RecordingRecorder recorder,
      ) async {
        await generateText(
          model: _chat(ctx, server),
          prompt: 'secret prompt',
          telemetry: settings,
        );
        return recorder.spans.last;
      }

      final hidden = _RecordingRecorder();
      final hiddenSpan = await spanFor(
        TelemetrySettings(isEnabled: true, recorder: hidden),
        hidden,
      );
      final shown = _RecordingRecorder();
      final shownSpan = await spanFor(
        TelemetrySettings(
          isEnabled: true,
          recorder: shown,
          captureInputs: true,
        ),
        shown,
      );
      final redacted = _RecordingRecorder();
      final redactedSpan = await spanFor(
        TelemetrySettings(
          isEnabled: true,
          recorder: redacted,
          captureInputs: true,
          redactAttribute: (key, value) {
            if (key == 'ai.prompt') return '[redacted]';
            if (key == AiTelemetryKeys.modelId) return null;
            return value;
          },
        ),
        redacted,
      );
      ctx.observe('hidden', hiddenSpan.attributes.keys.toList());
      ctx.observe('shown.prompt', shownSpan.attributes['ai.prompt']);
      ctx.observe('redacted.prompt', redactedSpan.attributes['ai.prompt']);
      ctx.expect(
        !hiddenSpan.attributes.containsKey('ai.prompt'),
        'prompt leaked by default',
      );
      ctx.expectEquals(
        shownSpan.attributes['ai.prompt'],
        'secret prompt',
        'captured prompt',
      );
      ctx.expectEquals(
        redactedSpan.attributes['ai.prompt'],
        '[redacted]',
        'redacted prompt',
      );
      ctx.expect(
        !redactedSpan.attributes.containsKey(AiTelemetryKeys.modelId),
        'dropped attribute present',
      );
      ctx.expectEquals(
        redactedSpan.attributes[AiTelemetryKeys.modelProvider],
        'verify-compat',
        'kept attribute',
      );
    },
  ),
  Check(
    id: 'telemetry-failure-isolation',
    feature: 'platform-telemetry',
    description:
        'A failed call ends the span with the error type and records a '
        'failure metric; a broken telemetry backend never fails the call and '
        'is reported to onDiagnostic.',
    run: (ctx) async {
      final bad = await ctx.server(
        (_) => FixtureResponse.json(
          _errorBody('Nope.', code: 'denied'),
          status: 403,
        ),
      );
      final recorder = _RecordingRecorder();
      final metrics = <TelemetryMetric>[];
      await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: _chat(ctx, bad),
          prompt: 'hi',
          maxRetries: 0,
          telemetry: TelemetrySettings(
            isEnabled: true,
            recorder: recorder,
            metricSink: CallbackTelemetryMetricSink(metrics.add),
          ),
        ),
        'failing call',
      );
      final span = recorder.spans.single;
      ctx.observe('endError', '${span.endError}');
      ctx.observe('metrics', [for (final m in metrics) '${m.name}=${m.value}']);
      ctx.expect(span.ended, 'span not ended on failure');
      ctx.expectEquals(
        '${span.endError}',
        'AiApiCallError',
        'error type only by default',
      );
      ctx.expectEquals(
        '${span.exceptions.single}',
        'AiApiCallError',
        'recorded exception type',
      );
      ctx.expect(
        metrics.any(
          (m) => m.name == AiTelemetryMetrics.failure && m.value == 1,
        ),
        'failure metric missing',
      );
      ctx.expect(
        !metrics.any((m) => m.name == AiTelemetryMetrics.success),
        'success metric on a failed call',
      );

      final detailed = _RecordingRecorder();
      await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: _chat(ctx, bad),
          prompt: 'hi',
          maxRetries: 0,
          telemetry: TelemetrySettings(
            isEnabled: true,
            recorder: detailed,
            captureExceptionDetails: true,
          ),
        ),
        'failing call with details',
      );
      ctx.expect(
        detailed.spans.single.endError is AiApiCallError,
        'details not captured',
      );

      final ok = await ctx.server(
        (_) => FixtureResponse.json(_completion('still works')),
      );
      final diagnostics = <Object>[];
      final result = await generateText(
        model: _chat(ctx, ok),
        prompt: 'hi',
        telemetry: TelemetrySettings(
          isEnabled: true,
          recorder: _ThrowingRecorder(),
          metricSink: CallbackTelemetryMetricSink(
            (_) => throw StateError('sink down'),
          ),
          onDiagnostic: diagnostics.add,
        ),
      );
      ctx.observe('diagnostics', diagnostics.map((e) => '$e').toList());
      ctx.expectEquals(
        result.text,
        'still works',
        'call survives a broken backend',
      );
      ctx.expect(
        diagnostics.length >= 2,
        'onDiagnostic saw ${diagnostics.length} errors',
      );
    },
  ),

  // ---- Testing utilities and helpers ---------------------------------------
  Check(
    id: 'testing-utilities',
    feature: 'platform-testing',
    description:
        'package:ai_sdk_dart/test.dart mocks drive embed, generateImage, '
        'generateText and streamText and record the calls they received.',
    run: (ctx) async {
      final embedding = MockEmbeddingModelV2<String>(
        embedding: [0.1, 0.2, 0.3],
        usage: const EmbeddingModelV2Usage(tokens: 4),
      );
      final single = await embed(model: embedding, value: 'hello');
      final many = await embedMany(model: embedding, values: ['a', 'b', 'c']);
      ctx.expectEquals(single.embedding, [0.1, 0.2, 0.3], 'mock vector');
      ctx.expectEquals(single.usage?.tokens, 4, 'mock usage');
      ctx.expectEquals(many.embeddings.length, 3, 'embedMany on mock');
      ctx.expectEquals(embedding.embedCalls.length, 2, 'recorded calls');
      ctx.expectEquals(embedding.embedCalls.last.values, [
        'a',
        'b',
        'c',
      ], 'recorded values');
      final v3 = MockEmbeddingModelV3<String>(embedding: [1.0]);
      ctx.expectEquals((await embed(model: v3, value: 'x')).embedding, [
        1.0,
      ], 'MockEmbeddingModelV3 alias');
      await ctx.expectThrows<StateError>(
        () => embed(
          model: MockEmbeddingModelV2<String>(
            embedding: [1.0],
            doEmbedError: StateError('boom'),
          ),
          value: 'x',
        ),
        'doEmbedError',
      );

      final image = MockImageModelV3(
        images: [
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      final generated = await generateImage(
        model: image,
        prompt: 'cat',
        n: 1,
        seed: 5,
      );
      ctx.expectEquals(generated.image.bytes.toList(), [
        1,
        2,
        3,
      ], 'mock image bytes');
      ctx.expectEquals(
        image.generateCalls.single.prompt,
        'cat',
        'image prompt recorded',
      );
      ctx.expectEquals(
        image.generateCalls.single.seed,
        5,
        'image seed recorded',
      );
      await ctx.expectThrows<AiNoImageGeneratedError>(
        () => generateImage(model: MockImageModelV3(), prompt: 'x'),
        'mock with no images',
      );

      final language = MockLanguageModelV4(
        response: [mockReasoning('thinking'), mockText('mock answer')],
        usage: const LanguageModelV4Usage(
          inputTokens: LanguageModelV4InputTokenUsage(total: 3),
          outputTokens: LanguageModelV4OutputTokenUsage(total: 2),
        ),
        finishReason: LanguageModelV4FinishReason.length,
        providerMetadata: const {
          'mock': {'seen': true},
        },
        warnings: const ['careful'],
      );
      final text = await generateText(
        model: language,
        prompt: 'hi',
        temperature: 0.4,
      );
      ctx.expectEquals(text.text, 'mock answer', 'mock text');
      ctx.expectEquals(text.reasoningText, 'thinking', 'mock reasoning');
      ctx.expectEquals(
        text.finishReason,
        LanguageModelV4FinishReason.length,
        'mock finish',
      );
      ctx.expectEquals(text.usage?.inputTokens.total, 3, 'mock input tokens');
      ctx.expectEquals(text.providerMetadata, {
        'mock': {'seen': true},
      }, 'mock metadata');
      ctx.expectEquals(text.warnings.length, 1, 'mock warnings');
      ctx.expectEquals(
        language.generateCalls.single.temperature,
        0.4,
        'recorded temperature',
      );
      final streamed = await streamText(model: language, prompt: 'hi');
      ctx.expectEquals(await streamed.text, 'mock answer', 'mock stream text');
      ctx.expectEquals(language.streamCalls.length, 1, 'stream call recorded');
      final toolCall = MockLanguageModelV4(
        response: [
          mockToolCall(toolName: 'lookup', input: {'q': 'x'}, toolCallId: 'c1'),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
      final called = await generateText(
        model: toolCall,
        prompt: 'hi',
        tools: {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: Schema(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
          ),
        },
      );
      ctx.expectEquals(
        called.toolCalls.single.toolName,
        'lookup',
        'mock tool call',
      );
      await ctx.expectThrows<StateError>(
        () => generateText(
          model: MockLanguageModelV4(doGenerateError: StateError('model down')),
          prompt: 'hi',
        ),
        'doGenerateError',
      );

      final next = mockId();
      ctx.expectEquals([next(), next(), next()], ['0', '1', '2'], 'mockId');
      final values = mockValues([1, 2, 3]);
      ctx.expectEquals(
        [values(), values(), values(), values()],
        [1, 2, 3, 3],
        'mockValues',
      );
    },
  ),
  Check(
    id: 'utils-helpers',
    feature: 'platform-utils',
    description:
        'generateId, createIdGenerator, simulateReadableStream, '
        'convertToModelMessages and pruneMessages behave as documented.',
    run: (ctx) async {
      final id = generateId();
      final long = createIdGenerator(size: 16)();
      ctx.observe('id', id);
      ctx.expectEquals(id.length, 7, 'default id length');
      ctx.expectEquals(long.length, 16, 'custom id length');
      ctx.expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id), 'id alphabet');
      ctx.expect(generateId() != generateId(), 'ids collide');

      final parts = <LanguageModelV4StreamPart>[
        const StreamPartTextStart(id: 't'),
        const StreamPartTextDelta(id: 't', delta: 'hi'),
        const StreamPartTextEnd(id: 't'),
      ];
      final watch = Stopwatch()..start();
      final replayed = await simulateReadableStream(
        parts: parts,
        chunkDelayInMs: 40,
      ).toList();
      ctx.expectEquals(replayed.length, 3, 'replayed parts');
      ctx.expect(
        watch.elapsedMilliseconds >= 70,
        'chunk delay ignored (${watch.elapsedMilliseconds}ms)',
      );

      final provider = [
        LanguageModelV4Message(
          role: LanguageModelV4Role.user,
          content: [const LanguageModelV4TextPart(text: 'plain')],
        ),
      ];
      final converted = convertToModelMessages(provider);
      ctx.expectEquals(converted.single.role, ModelMessageRole.user, 'role');
      ctx.expectEquals(converted.single.text, 'plain', 'collapsed text');

      final history = [
        const ModelMessage(role: ModelMessageRole.system, content: 's'),
        for (var i = 0; i < 5; i++)
          ModelMessage(role: ModelMessageRole.user, content: 'm$i'),
      ];
      final pruned = pruneMessages(history, maxMessages: 2);
      ctx.expectEquals(pruned.map((m) => m.text).toList(), [
        's',
        'm3',
        'm4',
      ], 'system kept, newest kept');
      ctx.expectEquals(pruneMessages(history).length, 6, 'no limit keeps all');
      await ctx.expectThrows<ArgumentError>(
        () async => pruneMessages(history, maxMessages: -1),
        'negative maxMessages',
      );
    },
  ),
];

/// A model that returns canned rows regardless of the input.
class _FixedEmbeddingModel implements EmbeddingModelV2<String> {
  _FixedEmbeddingModel(this.rows);
  final List<EmbeddingModelV2Embedding<String>> rows;

  @override
  String get specificationVersion => 'v2';
  @override
  String get provider => 'fixed';
  @override
  String get modelId => 'fixed-embedding';
  @override
  int? get maxEmbeddingsPerCall => null;
  @override
  bool get supportsParallelCalls => false;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async => EmbeddingModelV2GenerateResult<String>(embeddings: rows);
}

extension on CheckContext {
  T expectThrowsSync<T extends Object>(void Function() body, String what) {
    try {
      body();
    } on T catch (error) {
      observe('$what.error', '${error.runtimeType}: $error');
      return error;
    }
    throw CheckFailure('$what: expected $T to be thrown, nothing was');
  }
}
