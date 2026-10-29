// Verification checks for package:ai_sdk_provider. See
// features/ai_sdk_provider.md.
//
// A provider author implements the interfaces in ai_sdk_provider. These checks
// do exactly that: each one writes a minimal custom model against the public
// interfaces, runs it through the public ai_sdk_dart functions, and asserts the
// contract end to end (stream parts to result fields, usage and finish reasons,
// typed errors, provider metadata, call options).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_provider';

// ---------------------------------------------------------------------------
// Minimal custom providers (what a provider author writes)
// ---------------------------------------------------------------------------

typedef _Generate =
    Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    );
typedef _Stream =
    Future<LanguageModelV4StreamResult> Function(
      LanguageModelV4CallOptions options,
    );

class _AcmeLanguageModel extends LanguageModelV4 {
  _AcmeLanguageModel({_Generate? generate, _Stream? stream})
    : _generate = generate,
      _stream = stream;

  final _Generate? _generate;
  final _Stream? _stream;
  final List<LanguageModelV4CallOptions> generateCalls = [];
  final List<LanguageModelV4CallOptions> streamCalls = [];

  @override
  String get provider => 'acme';

  @override
  String get modelId => 'acme-chat-1';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) {
    generateCalls.add(options);
    return _generate!(options);
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) {
    streamCalls.add(options);
    return _stream!(options);
  }
}

class _AcmeEmbeddingModel implements EmbeddingModelV2<String> {
  _AcmeEmbeddingModel({this.limit, this.parallel = true, this.onEmbed});

  final int? limit;
  final bool parallel;
  final Future<void> Function(EmbeddingModelV2CallOptions<String>)? onEmbed;
  final List<EmbeddingModelV2CallOptions<String>> calls = [];
  var _inFlight = 0;
  var peakInFlight = 0;

  @override
  String get specificationVersion => 'v2';
  @override
  String get provider => 'acme';
  @override
  String get modelId => 'acme-embed-1';
  @override
  int? get maxEmbeddingsPerCall => limit;
  @override
  bool get supportsParallelCalls => parallel;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    calls.add(options);
    _inFlight++;
    if (_inFlight > peakInFlight) peakInFlight = _inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await onEmbed?.call(options);
      return EmbeddingModelV2GenerateResult<String>(
        embeddings: [
          for (final v in options.values)
            EmbeddingModelV2Embedding(
              value: v,
              embedding: [v.length.toDouble(), 0.5],
            ),
        ],
        usage: EmbeddingModelV2Usage(tokens: options.values.length * 2),
        warnings: const ['acme warning'],
        providerMetadata: const {
          'acme': {'batch': true},
        },
      );
    } finally {
      _inFlight--;
    }
  }
}

class _AcmeImageModel implements ImageModelV3 {
  _AcmeImageModel(this.images);
  final List<GeneratedImage> images;
  final List<ImageModelV3CallOptions> calls = [];

  @override
  String get specificationVersion => 'v3';
  @override
  String get provider => 'acme';
  @override
  String get modelId => 'acme-image-1';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    calls.add(options);
    return ImageModelV3GenerateResult(
      images: images,
      usage: ImageModelV3Usage(imagesGenerated: images.length),
      warnings: const ['image warning'],
      providerMetadata: const {
        'acme': {'seedUsed': 1},
      },
      responses: [
        ImageModelV3ResponseMetadata(
          timestamp: DateTime.utc(2026, 1, 1),
          modelId: modelId,
        ),
      ],
    );
  }
}

class _AcmeSpeechModel implements SpeechModelV1 {
  _AcmeSpeechModel(this.audio);
  final Uint8List audio;
  final List<SpeechModelV1CallOptions> calls = [];

  @override
  String get specificationVersion => 'v1';
  @override
  String get provider => 'acme';
  @override
  String get modelId => 'acme-voice-1';

  @override
  Future<SpeechModelV1GenerateResult> doGenerate(
    SpeechModelV1CallOptions options,
  ) async {
    calls.add(options);
    return SpeechModelV1GenerateResult(audio: audio, mediaType: 'audio/ogg');
  }
}

class _AcmeTranscriptionModel implements TranscriptionModelV1 {
  _AcmeTranscriptionModel(this.text);
  final String text;
  final List<TranscriptionModelV1CallOptions> calls = [];

  @override
  String get specificationVersion => 'v1';
  @override
  String get provider => 'acme';
  @override
  String get modelId => 'acme-ears-1';

  @override
  Future<TranscriptionModelV1GenerateResult> doGenerate(
    TranscriptionModelV1CallOptions options,
  ) async {
    calls.add(options);
    return TranscriptionModelV1GenerateResult(text: text);
  }
}

class _AcmeRerankModel implements RerankModelV1 {
  final List<RerankModelV1CallOptions> calls = [];

  @override
  String get specificationVersion => 'v1';
  @override
  String get provider => 'acme';
  @override
  String get modelId => 'acme-rank-1';

  @override
  Future<RerankModelV1Result> doRerank(RerankModelV1CallOptions options) async {
    calls.add(options);
    // Score by how many query words the document contains, best first.
    final words = options.query.toLowerCase().split(' ');
    final scored = [
      for (var i = 0; i < options.documents.length; i++)
        RerankDocument(
          index: i,
          document: options.documents[i],
          relevanceScore:
              words
                  .where((w) => options.documents[i].toLowerCase().contains(w))
                  .length /
              words.length,
        ),
    ]..sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    return RerankModelV1Result(
      documents: scored.take(options.topN ?? scored.length).toList(),
    );
  }
}

const _lookupSchema = {
  'type': 'object',
  'properties': {
    'q': {'type': 'string'},
  },
  'required': ['q'],
};

Tool<Map<String, dynamic>, String> _lookupTool({
  List<ToolInputExample> examples = const [],
}) => tool<Map<String, dynamic>, String>(
  description: 'Look something up.',
  inputSchema: Schema(jsonSchema: _lookupSchema, fromJson: (json) => json),
  strict: true,
  inputExamples: examples,
);

const _usage = LanguageModelV4Usage(
  inputTokens: LanguageModelV4InputTokenUsage(
    total: 20,
    noCache: 12,
    cacheRead: 6,
    cacheWrite: 2,
  ),
  outputTokens: LanguageModelV4OutputTokenUsage(
    total: 9,
    text: 5,
    reasoning: 4,
  ),
  raw: {'vendor': 'raw-usage'},
);

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

final checks = PackageChecks(_package, [
  Check(
    id: 'language-generate-contract',
    feature: 'provider-language',
    description:
        'A custom LanguageModelV4.doGenerate result maps to generateText '
        'fields: text, reasoning, tool calls, sources, files, usage, finish '
        'reasons, warnings and provider metadata.',
    run: (ctx) async {
      final model = _AcmeLanguageModel(
        generate: (options) async => LanguageModelV4GenerateResult(
          content: [
            const LanguageModelV4ReasoningPart(
              text: 'weigh options',
              signature: 'sig-1',
            ),
            const LanguageModelV4TextPart(text: 'Here is '),
            const LanguageModelV4TextPart(text: 'the answer.'),
            const LanguageModelV4ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: {'q': 'dart'},
            ),
            const LanguageModelV4SourcePart(
              id: 'src-1',
              url: 'https://example.com/a',
              title: 'Example',
            ),
            const LanguageModelV4FilePart(
              data: DataContentBase64('aGVsbG8='),
              mediaType: 'text/plain',
              filename: 'hello.txt',
            ),
          ],
          finishReason: LanguageModelV4FinishReason.toolCalls,
          rawFinishReason: 'tool_use',
          usage: _usage,
          warnings: const [
            LanguageModelV4UnsupportedWarning(
              feature: 'topK',
              details: 'ignored',
            ),
            LanguageModelV4CompatibilityWarning(feature: 'seed'),
            LanguageModelV4DeprecatedWarning(
              setting: 'stop',
              message: 'use stopSequences',
            ),
            LanguageModelV4OtherWarning(message: 'free text'),
          ],
          response: LanguageModelV4ResponseMetadata(
            id: 'resp-1',
            modelId: 'acme-chat-1-0613',
            timestamp: DateTime.utc(2026, 2, 3),
            headers: const {'x-request-id': 'req-9'},
          ),
          providerMetadata: const {
            'acme': {'trace': 't-1'},
          },
        ),
      );
      final result = await generateText(
        model: model,
        prompt: 'go',
        tools: {'lookup': _lookupTool()},
      );
      ctx.observe('text', result.text);
      ctx.observe('finishReason', result.finishReason?.name);
      ctx.observe('rawFinishReason', result.rawFinishReason);
      ctx.observe('warnings', [for (final w in result.warnings) w.type]);
      ctx.expectEquals(model.generateCalls.length, 1, 'doGenerate calls');
      ctx.expectEquals(result.text, 'Here is the answer.', 'text parts joined');
      ctx.expectEquals(result.reasoningText, 'weigh options', 'reasoning');
      ctx.expectEquals(result.reasoning.single.signature, 'sig-1', 'signature');
      ctx.expectEquals(result.toolCalls.length, 1, 'tool calls');
      ctx.expectEquals(result.toolCalls.single.toolCallId, 'call-1', 'call id');
      ctx.expectEquals(result.toolCalls.single.toolName, 'lookup', 'tool name');
      ctx.expectEquals(result.toolCalls.single.input, {'q': 'dart'}, 'input');
      ctx.expectEquals(
        result.sources.single.url,
        'https://example.com/a',
        'source',
      );
      ctx.expectEquals(result.files.single.filename, 'hello.txt', 'file');
      ctx.expectEquals(
        result.finishReason,
        LanguageModelV4FinishReason.toolCalls,
        'finishReason',
      );
      ctx.expectEquals(result.rawFinishReason, 'tool_use', 'rawFinishReason');
      final usage = result.usage!;
      ctx.expectEquals(usage.inputTokens.total, 20, 'input total');
      ctx.expectEquals(usage.inputTokens.noCache, 12, 'input noCache');
      ctx.expectEquals(usage.inputTokens.cacheRead, 6, 'input cacheRead');
      ctx.expectEquals(usage.inputTokens.cacheWrite, 2, 'input cacheWrite');
      ctx.expectEquals(usage.outputTokens.total, 9, 'output total');
      ctx.expectEquals(usage.outputTokens.text, 5, 'output text');
      ctx.expectEquals(usage.outputTokens.reasoning, 4, 'output reasoning');
      ctx.expectEquals(result.finalStep.usage?.raw, {
        'vendor': 'raw-usage',
      }, 'raw usage on the final step');
      ctx.expectEquals(result.totalUsage?.inputTokens.total, 20, 'totalUsage');
      ctx.expectEquals(result.warnings.map((w) => w.type).toList(), [
        'unsupported',
        'compatibility',
        'deprecated',
        'other',
      ], 'warning types in order');
      ctx.expectEquals(
        (result.warnings.first as LanguageModelV4UnsupportedWarning).feature,
        'topK',
        'warning feature',
      );
      ctx.expectEquals(result.providerMetadata, {
        'acme': {'trace': 't-1'},
      }, 'providerMetadata');
      final meta = result.responseInfo.metadata;
      ctx.expectEquals(meta?.id, 'resp-1', 'response id');
      ctx.expectEquals(meta?.modelId, 'acme-chat-1-0613', 'response model id');
      ctx.expectEquals(meta?.headers, {
        'x-request-id': 'req-9',
      }, 'response headers');
      ctx.expectEquals(
        result.responseMessages.first.role,
        LanguageModelV4Role.assistant,
        'assistant message in history',
      );
    },
  ),
  Check(
    id: 'language-stream-contract',
    feature: 'provider-language',
    description:
        'A custom LanguageModelV4.doStream part sequence maps to streamText '
        'events and result futures: text, reasoning, tool input, sources, '
        'files, warnings, usage, finish reason and provider metadata.',
    run: (ctx) async {
      final model = _AcmeLanguageModel(
        stream: (options) async => LanguageModelV4StreamResult(
          stream: Stream.fromIterable(<LanguageModelV4StreamPart>[
            const StreamPartStreamStart(
              warnings: [LanguageModelV4OtherWarning(message: 'stream warn')],
            ),
            StreamPartResponseMetadata(
              metadata: LanguageModelV4ResponseMetadata(
                id: 'resp-s',
                modelId: 'acme-chat-1-0613',
              ),
            ),
            const StreamPartReasoningStart(id: 'r1'),
            const StreamPartReasoningDelta(id: 'r1', delta: 'think '),
            const StreamPartReasoningDelta(id: 'r1', delta: 'hard'),
            const StreamPartReasoningEnd(id: 'r1', signature: 'sig-s'),
            const StreamPartTextStart(id: 't1'),
            const StreamPartTextDelta(id: 't1', delta: 'Hel'),
            const StreamPartTextDelta(id: 't1', delta: 'lo'),
            const StreamPartTextEnd(id: 't1'),
            const StreamPartToolInputStart(id: 'call-s', toolName: 'lookup'),
            const StreamPartToolInputDelta(id: 'call-s', delta: '{"q":'),
            const StreamPartToolInputDelta(id: 'call-s', delta: '"x"}'),
            const StreamPartToolInputEnd(id: 'call-s'),
            const StreamPartToolCall(
              toolCall: LanguageModelV4ToolCallPart(
                toolCallId: 'call-s',
                toolName: 'lookup',
                input: {'q': 'x'},
              ),
            ),
            const StreamPartSource(
              source: LanguageModelV4SourcePart(
                id: 'src-s',
                url: 'https://example.com/s',
              ),
            ),
            const StreamPartFile(
              file: LanguageModelV4FilePart(
                data: DataContentBase64('QUJD'),
                mediaType: 'text/plain',
              ),
            ),
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.toolCalls,
              rawFinishReason: 'tool_use',
              usage: _usage,
              providerMetadata: {
                'acme': {'trace': 't-s'},
              },
            ),
          ]),
        ),
      );
      final result = await streamText(
        model: model,
        prompt: 'go',
        tools: {'lookup': _lookupTool()},
      );
      final piecesFuture = result.textStream.toList();
      final events = await result.stream.toList();
      final pieces = await piecesFuture;
      final text = await result.text;
      final eventTypes = events.map((e) => e.runtimeType.toString()).toList();
      ctx.observe('eventTypes', eventTypes);
      ctx.observe('text', text);
      ctx.observe('textStreamPieces', pieces);
      ctx.expectEquals(model.streamCalls.length, 1, 'doStream calls');
      ctx.expectEquals(text, 'Hello', 'text');
      ctx.expectEquals(await result.reasoningText, 'think hard', 'reasoning');
      ctx.expectEquals(
        (await result.reasoning).single.signature,
        'sig-s',
        'signature',
      );
      final toolCall = (await result.toolCalls).single;
      ctx.expectEquals(toolCall.toolCallId, 'call-s', 'tool call id');
      ctx.expectEquals(toolCall.input, {'q': 'x'}, 'tool call input');
      ctx.expectEquals((await result.sources).single.id, 'src-s', 'source');
      ctx.expectEquals(
        (await result.files).single.mediaType,
        'text/plain',
        'file',
      );
      ctx.expectEquals(
        await result.finishReason,
        LanguageModelV4FinishReason.toolCalls,
        'finishReason',
      );
      ctx.expectEquals(
        await result.rawFinishReason,
        'tool_use',
        'rawFinishReason',
      );
      final usage = (await result.usage)!;
      ctx.expectEquals(usage.inputTokens.cacheRead, 6, 'cacheRead');
      ctx.expectEquals(usage.outputTokens.reasoning, 4, 'reasoning tokens');
      ctx.expectEquals(await result.providerMetadata, {
        'acme': {'trace': 't-s'},
      }, 'providerMetadata');
      ctx.expectEquals((await result.warnings).map((w) => w.type).toList(), [
        'other',
      ], 'stream warnings');
      ctx.expect(
        pieces.length >= 2,
        'textStream should yield incremental pieces',
      );
      ctx.expect(
        eventTypes.contains('StreamTextTextDeltaEvent') &&
            eventTypes.contains('StreamTextReasoningDeltaEvent') &&
            eventTypes.contains('StreamTextToolInputDeltaEvent') &&
            eventTypes.contains('StreamTextFinishEvent<dynamic>'),
        'missing lifecycle events: $eventTypes',
      );
      final ids = (await result.providerStream.toList()).length;
      ctx.observe('providerStreamParts', ids);
    },
  ),
  Check(
    id: 'language-finish-reasons',
    feature: 'provider-language',
    description:
        'Every LanguageModelV4FinishReason value and its raw string reaches '
        'generateText and streamText unchanged.',
    run: (ctx) async {
      final seen = <String, String>{};
      for (final reason in LanguageModelV4FinishReason.values) {
        final raw = 'raw-${reason.name}';
        final model = _AcmeLanguageModel(
          generate: (_) async => LanguageModelV4GenerateResult(
            content: const [LanguageModelV4TextPart(text: 'x')],
            finishReason: reason,
            rawFinishReason: raw,
          ),
          stream: (_) async => LanguageModelV4StreamResult(
            stream: Stream.fromIterable(<LanguageModelV4StreamPart>[
              const StreamPartTextStart(id: 't'),
              const StreamPartTextDelta(id: 't', delta: 'x'),
              const StreamPartTextEnd(id: 't'),
              StreamPartFinish(finishReason: reason, rawFinishReason: raw),
            ]),
          ),
        );
        final generated = await generateText(model: model, prompt: 'go');
        final streamed = await streamText(model: model, prompt: 'go');
        final streamReason = await streamed.finishReason;
        seen[reason.name] =
            '${generated.finishReason?.name}/${streamReason?.name}';
        ctx.expectEquals(
          generated.finishReason,
          reason,
          'generate ${reason.name}',
        );
        ctx.expectEquals(
          generated.rawFinishReason,
          raw,
          'generate raw ${reason.name}',
        );
        ctx.expectEquals(streamReason, reason, 'stream ${reason.name}');
        ctx.expectEquals(
          await streamed.rawFinishReason,
          raw,
          'stream raw ${reason.name}',
        );
      }
      ctx.observe('mapped', seen);
      ctx.expectEquals(seen.length, 7, 'finish reason values covered');
    },
  ),
  Check(
    id: 'language-call-options',
    feature: 'provider-language',
    description:
        'generateText hands a custom model complete LanguageModelV4CallOptions: '
        'prompt messages and data content, sampling settings, headers, '
        'provider options, tools, tool choice and response format.',
    run: (ctx) async {
      final model = _AcmeLanguageModel(
        generate: (options) async => options.toolChoice != null
            ? const LanguageModelV4GenerateResult(
                content: [
                  LanguageModelV4ToolCallPart(
                    toolCallId: 'c1',
                    toolName: 'lookup',
                    input: {'q': 'dart'},
                  ),
                ],
                finishReason: LanguageModelV4FinishReason.toolCalls,
              )
            : const LanguageModelV4GenerateResult(
                content: [LanguageModelV4TextPart(text: '{"city":"Oslo"}')],
                finishReason: LanguageModelV4FinishReason.stop,
              ),
      );
      final token = CancellationToken();
      await generateText(
        model: model,
        instructions: 'Be terse.',
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(text: 'Look at these.'),
              LanguageModelV4ImagePart(
                image: DataContentUrl(Uri.parse('https://example.com/i.png')),
                mediaType: 'image/png',
              ),
              const LanguageModelV4FilePart(
                data: DataContentBase64('UERG'),
                mediaType: 'application/pdf',
                filename: 'doc.pdf',
              ),
            ],
          ),
        ],
        maxOutputTokens: 123,
        temperature: 0.4,
        topP: 0.8,
        topK: 12,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        stopSequences: const ['END'],
        seed: 99,
        headers: const {'x-trace': 'abc'},
        providerOptions: const {
          'acme': {'mode': 'fast'},
        },
        reasoning: LanguageModelV4Reasoning.high,
        tools: {
          'lookup': _lookupTool(
            examples: const [
              ToolInputExample(input: {'q': 'dart'}),
            ],
          ),
        },
        toolChoice: const ToolChoiceSpecific(toolName: 'lookup'),
        abortSignal: token,
      );
      final o = model.generateCalls.single;
      ctx.observe('system', o.prompt.system);
      ctx.observe('roles', [for (final m in o.prompt.messages) m.role.name]);
      ctx.expect(
        (o.prompt.system ?? '').contains('Be terse.') ||
            o.prompt.messages.any(
              (m) =>
                  m.role == LanguageModelV4Role.system &&
                  m.content.whereType<LanguageModelV4TextPart>().any(
                    (p) => p.text == 'Be terse.',
                  ),
            ),
        'instructions not delivered',
      );
      final user = o.prompt.messages.lastWhere(
        (m) => m.role == LanguageModelV4Role.user,
      );
      ctx.expectEquals(user.content.length, 3, 'user content parts');
      final image = user.content[1] as LanguageModelV4ImagePart;
      ctx.expectEquals(
        (image.image as DataContentUrl).url.toString(),
        'https://example.com/i.png',
        'image URL data content',
      );
      final file = user.content[2] as LanguageModelV4FilePart;
      ctx.expectEquals(dataContentToBase64(file.data), 'UERG', 'file base64');
      ctx.expectEquals(file.filename, 'doc.pdf', 'file name');
      ctx.expectEquals(o.maxOutputTokens, 123, 'maxOutputTokens');
      ctx.expectEquals(o.temperature, 0.4, 'temperature');
      ctx.expectEquals(o.topP, 0.8, 'topP');
      ctx.expectEquals(o.topK, 12, 'topK');
      ctx.expectEquals(o.presencePenalty, 0.1, 'presencePenalty');
      ctx.expectEquals(o.frequencyPenalty, 0.2, 'frequencyPenalty');
      ctx.expectEquals(o.stopSequences, ['END'], 'stopSequences');
      ctx.expectEquals(o.seed, 99, 'seed');
      ctx.expectEquals(o.headers?['x-trace'], 'abc', 'headers');
      ctx.expectEquals(o.providerOptions, {
        'acme': {'mode': 'fast'},
      }, 'providerOptions');
      ctx.expectEquals(o.reasoning, LanguageModelV4Reasoning.high, 'reasoning');
      final fn = o.functionTools.single;
      ctx.expectEquals(fn.name, 'lookup', 'tool name');
      ctx.expectEquals(
        fn.description,
        'Look something up.',
        'tool description',
      );
      ctx.expectEquals(fn.inputSchema['required'], ['q'], 'tool schema');
      ctx.expectEquals(fn.strict, true, 'tool strict');
      ctx.expectEquals(fn.inputExamples, [
        {'q': 'dart'},
      ], 'tool input examples');
      final choice = o.toolChoice;
      ctx.expect(
        choice is ToolChoiceSpecific && choice.toolName == 'lookup',
        'toolChoice is ${choice.runtimeType}',
      );
      ctx.expect(o.abortSignal != null, 'abort signal not forwarded');
      ctx.expect(!o.abortSignal!.isCancelled, 'signal starts un-cancelled');
      ctx.expect(
        o.responseFormat is! LanguageModelV4JsonResponseFormat,
        'plain text call asked for JSON',
      );

      final structured = await generateText<Map<String, dynamic>>(
        model: model,
        prompt: 'Which city?',
        output: Output.object(
          name: 'City',
          description: 'A city.',
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
            },
            fromJson: (json) => json,
          ),
        ),
      );
      final format = model.generateCalls.last.responseFormat;
      ctx.observe('responseFormat', format?.runtimeType.toString());
      ctx.expectEquals(structured.output, {'city': 'Oslo'}, 'parsed output');
      ctx.expect(
        format is LanguageModelV4JsonResponseFormat,
        'response format ${format.runtimeType}',
      );
      format as LanguageModelV4JsonResponseFormat;
      ctx.expectEquals(format.name, 'City', 'format name');
      ctx.expectEquals(format.description, 'A city.', 'format description');
      ctx.expectEquals(format.schema?['type'], 'object', 'format schema');
    },
  ),
  Check(
    id: 'language-errors',
    feature: 'provider-errors',
    description:
        'Errors thrown by a custom language model surface as documented: '
        'AiApiCallError as is, retryable ones as AiRetryError after '
        'maxRetries, other exceptions unwrapped, and stream error parts.',
    run: (ctx) async {
      final bad = _AcmeLanguageModel(
        generate: (_) async => throw const AiApiCallError(
          'quota exceeded',
          statusCode: 400,
          type: 'quota',
          code: 'q1',
        ),
      );
      final plain = await ctx.expectThrows<AiApiCallError>(
        () => generateText(model: bad, prompt: 'go'),
        'non-retryable',
      );
      ctx.expectEquals(plain.statusCode, 400, 'status');
      ctx.expectEquals(plain.message, 'quota exceeded', 'message');
      ctx.expectEquals(plain.type, 'quota', 'type');
      ctx.expectEquals(plain.code, 'q1', 'code');
      ctx.expectEquals(bad.generateCalls.length, 1, 'non-retryable call count');

      final flaky = _AcmeLanguageModel(
        generate: (_) async => throw const AiApiCallError(
          'overloaded',
          statusCode: 503,
          isRetryable: true,
        ),
      );
      final retry = await ctx.expectThrows<AiRetryError>(
        () => generateText(model: flaky, prompt: 'go', maxRetries: 1),
        'retryable',
      );
      ctx.expectEquals(retry.attempts, 2, 'attempts');
      ctx.expectEquals(flaky.generateCalls.length, 2, 'retryable call count');
      ctx.expect(retry.lastError is AiApiCallError, 'lastError type');

      final crash = _AcmeLanguageModel(
        generate: (_) async => throw StateError('adapter bug'),
      );
      await ctx.expectThrows<StateError>(
        () => generateText(model: crash, prompt: 'go'),
        'unrelated exception',
      );
      ctx.expectEquals(
        crash.generateCalls.length,
        1,
        'exceptions are not retried',
      );

      final empty = _AcmeLanguageModel(
        generate: (_) async => const LanguageModelV4GenerateResult(
          finishReason: LanguageModelV4FinishReason.stop,
        ),
      );
      final emptyResult = await generateText(model: empty, prompt: 'go');
      ctx.expectEquals(emptyResult.text, '', 'empty content gives empty text');

      final streamErrors = <Object>[];
      final failing = _AcmeLanguageModel(
        stream: (_) async => LanguageModelV4StreamResult(
          stream: Stream.fromIterable(<LanguageModelV4StreamPart>[
            const StreamPartTextStart(id: 't'),
            const StreamPartTextDelta(id: 't', delta: 'partial'),
            const StreamPartError(
              error: AiApiCallError('mid-stream failure', statusCode: 500),
            ),
          ]),
        ),
      );
      final streamed = await streamText(
        model: failing,
        prompt: 'go',
        onError: (error) => streamErrors.add(error),
      );
      Object? futureError;
      try {
        await streamed.text;
      } catch (error) {
        futureError = error;
      }
      ctx.observe('streamErrors', streamErrors.map((e) => '$e').toList());
      ctx.observe('futureError', '$futureError');
      ctx.expect(
        streamErrors.any(
          (e) => e is AiApiCallError && e.message == 'mid-stream failure',
        ),
        'onError did not receive the stream error part: $streamErrors',
      );
    },
  ),
  Check(
    id: 'embedding-contract',
    feature: 'provider-embedding',
    description:
        'A custom EmbeddingModelV2 is called with the documented options; '
        'maxEmbeddingsPerCall and supportsParallelCalls shape embedMany, and '
        'usage is summed.',
    run: (ctx) async {
      final model = _AcmeEmbeddingModel(limit: 3, parallel: false);
      final values = ['a', 'bb', 'ccc', 'dddd', 'eeeee', 'ffffff', 'g'];
      final result = await embedMany(
        model: model,
        values: values,
        maxParallelCalls: 4,
        headers: const {'x-trace': 'e1'},
        providerOptions: const {
          'acme': {'dimensions': 2},
        },
      );
      ctx.observe('batches', [for (final c in model.calls) c.values]);
      ctx.observe('peakInFlight', model.peakInFlight);
      ctx.expectEquals(
        model.calls.map((c) => c.values).toList(),
        [
          ['a', 'bb', 'ccc'],
          ['dddd', 'eeeee', 'ffffff'],
          ['g'],
        ],
        'batches follow maxEmbeddingsPerCall',
      );
      ctx.expectEquals(model.peakInFlight, 1, 'supportsParallelCalls: false');
      ctx.expectEquals(model.calls.first.headers, {'x-trace': 'e1'}, 'headers');
      ctx.expectEquals(model.calls.first.providerOptions, {
        'acme': {'dimensions': 2},
      }, 'providerOptions');
      ctx.expect(model.calls.first.abortSignal != null, 'abort signal missing');
      ctx.expectEquals(
        result.embeddings.map((e) => e.value).toList(),
        values,
        'order',
      );
      ctx.expectEquals(
        result.embeddings.map((e) => e.embedding.first).toList(),
        [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 1.0],
        'vectors',
      );
      ctx.expectEquals(result.usage?.tokens, 14, 'summed usage');

      final parallelModel = _AcmeEmbeddingModel(limit: 1, parallel: true);
      await embedMany(
        model: parallelModel,
        values: ['a', 'b', 'c'],
        maxParallelCalls: 3,
      );
      ctx.expectEquals(parallelModel.peakInFlight, 3, 'parallel calls allowed');

      final single = await embed(
        model: _AcmeEmbeddingModel(),
        value: 'hello',
        providerOptions: const {
          'acme': {'x': 1},
        },
      );
      ctx.expectEquals(single.embedding, [5.0, 0.5], 'embed vector');
      ctx.expectEquals(single.usage?.tokens, 2, 'embed usage');
    },
  ),
  Check(
    id: 'image-contract',
    feature: 'provider-image',
    description:
        'A custom ImageModelV3 receives prompt, n, size, aspectRatio, seed, '
        'headers and provider options from generateImage, and its images and '
        'usage come back; an empty result is AiNoImageGeneratedError.',
    run: (ctx) async {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
      final model = _AcmeImageModel([
        GeneratedImage(bytes: png, mediaType: 'image/png'),
        GeneratedImage(bytes: jpeg, mediaType: 'image/jpeg'),
      ]);
      final result = await generateImage(
        model: model,
        prompt: 'a lighthouse',
        n: 2,
        size: '512x512',
        aspectRatio: '1:1',
        seed: 17,
        headers: const {'x-trace': 'i1'},
        providerOptions: const {
          'acme': {'style': 'ink'},
        },
      );
      final o = model.calls.single;
      ctx.observe('mediaTypes', [for (final i in result.images) i.mediaType]);
      ctx.expectEquals(o.prompt, 'a lighthouse', 'prompt');
      ctx.expectEquals(o.n, 2, 'n');
      ctx.expectEquals(o.size, '512x512', 'size');
      ctx.expectEquals(o.aspectRatio, '1:1', 'aspectRatio');
      ctx.expectEquals(o.seed, 17, 'seed');
      ctx.expectEquals(o.headers, {'x-trace': 'i1'}, 'headers');
      ctx.expectEquals(o.providerOptions, {
        'acme': {'style': 'ink'},
      }, 'providerOptions');
      ctx.expect(o.abortSignal != null, 'abort signal missing');
      ctx.expectEquals(result.images.length, 2, 'images');
      ctx.expectEquals(result.image.mediaType, 'image/png', 'first image');
      ctx.expectEquals(
        result.images[1].bytes.toList(),
        jpeg.toList(),
        'second bytes',
      );
      ctx.expectEquals(result.usage?.imagesGenerated, 2, 'usage');
      await ctx.expectThrows<AiNoImageGeneratedError>(
        () =>
            generateImage(model: _AcmeImageModel(const []), prompt: 'nothing'),
        'empty result',
      );
    },
  ),
  Check(
    id: 'speech-transcription-contract',
    feature: 'provider-speech-transcription',
    description:
        'Custom SpeechModelV1 and TranscriptionModelV1 implementations get '
        'the documented options and their results reach generateSpeech and '
        'transcribe; empty results raise the documented typed errors.',
    run: (ctx) async {
      final audio = Uint8List.fromList([9, 8, 7, 6]);
      final speech = _AcmeSpeechModel(audio);
      final spoken = await generateSpeech(
        model: speech,
        text: 'Good morning.',
        voice: 'nova',
        format: 'ogg',
        speed: 0.9,
        headers: const {'x-trace': 's1'},
        providerOptions: const {
          'acme': {'emotion': 'calm'},
        },
      );
      final so = speech.calls.single;
      ctx.expectEquals(so.text, 'Good morning.', 'speech text');
      ctx.expectEquals(so.voice, 'nova', 'voice');
      ctx.expectEquals(so.format, 'ogg', 'format');
      ctx.expectEquals(so.speed, 0.9, 'speed');
      ctx.expectEquals(so.headers, {'x-trace': 's1'}, 'speech headers');
      ctx.expectEquals(so.providerOptions, {
        'acme': {'emotion': 'calm'},
      }, 'speech providerOptions');
      ctx.expectEquals(spoken.audio.toList(), audio.toList(), 'audio');
      ctx.expectEquals(spoken.mediaType, 'audio/ogg', 'mediaType');
      await ctx.expectThrows<AiNoSpeechGeneratedError>(
        () => generateSpeech(model: _AcmeSpeechModel(Uint8List(0)), text: 'x'),
        'empty audio',
      );

      final ears = _AcmeTranscriptionModel('good morning');
      final heard = await transcribe(
        model: ears,
        audio: audio,
        audioMediaType: 'audio/ogg',
        language: 'en',
        prompt: 'greeting',
        headers: const {'x-trace': 't1'},
        providerOptions: const {
          'acme': {'diarize': true},
        },
      );
      final to = ears.calls.single;
      ctx.expectEquals(to.audio.toList(), audio.toList(), 'audio bytes');
      ctx.expectEquals(to.audioMediaType, 'audio/ogg', 'audio media type');
      ctx.expectEquals(to.language, 'en', 'language');
      ctx.expectEquals(to.prompt, 'greeting', 'prompt');
      ctx.expectEquals(to.headers, {'x-trace': 't1'}, 'transcription headers');
      ctx.expectEquals(to.providerOptions, {
        'acme': {'diarize': true},
      }, 'transcription providerOptions');
      ctx.expectEquals(heard.text, 'good morning', 'transcript');
      await ctx.expectThrows<AiNoTranscriptGeneratedError>(
        () => transcribe(model: _AcmeTranscriptionModel(''), audio: audio),
        'empty transcript',
      );
      ctx.observe('mediaType', spoken.mediaType);
      ctx.observe('text', heard.text);
    },
  ),
  Check(
    id: 'rerank-contract',
    feature: 'provider-rerank',
    description:
        'A custom RerankModelV1 gets query, documents and topN and its '
        'ranked documents come back in the order the provider returned.',
    run: (ctx) async {
      final model = _AcmeRerankModel();
      final result = await rerank(
        model: model,
        query: 'dart sdk',
        documents: [
          'Rust is fast.',
          'The Dart SDK ships a compiler.',
          'A Dart tutorial.',
        ],
        topN: 2,
        headers: const {'x-trace': 'r1'},
        providerOptions: const {
          'acme': {'lang': 'en'},
        },
      );
      final o = model.calls.single;
      ctx.observe('ranked', [
        for (final d in result.documents)
          {'index': d.index, 'score': d.relevanceScore},
      ]);
      ctx.expectEquals(o.query, 'dart sdk', 'query');
      ctx.expectEquals(o.documents.length, 3, 'documents');
      ctx.expectEquals(o.topN, 2, 'topN');
      ctx.expectEquals(o.headers, {'x-trace': 'r1'}, 'headers');
      ctx.expectEquals(o.providerOptions, {
        'acme': {'lang': 'en'},
      }, 'providerOptions');
      ctx.expectEquals(result.documents.length, 2, 'topN honored');
      ctx.expectEquals(result.document.index, 1, 'best document index');
      ctx.expectEquals(result.document.relevanceScore, 1.0, 'best score');
      ctx.expectEquals(result.documents.map((d) => d.index).toList(), [
        1,
        2,
      ], 'order');
    },
  ),
  Check(
    id: 'abort-signal',
    feature: 'provider-abort-signal',
    description:
        'The AbortSignal handed to a custom model fires when the caller '
        'cancels, the call ends with AiOperationCancelledError, and '
        'runWithAbortSignal / AbortSignalObservation behave as documented.',
    run: (ctx) async {
      AbortSignal? seen;
      var sawCancel = false;
      final model = _AcmeEmbeddingModel(
        onEmbed: (options) async {
          seen = options.abortSignal;
          await options.abortSignal!.onCancelled.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
          sawCancel = options.abortSignal!.isCancelled;
        },
      );
      final token = CancellationToken();
      Timer(const Duration(milliseconds: 120), token.cancel);
      await ctx.expectThrows<AiOperationCancelledError>(
        () => embed(model: model, value: 'x', abortSignal: token),
        'embed cancelled mid-flight',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ctx.observe('providerSawCancel', sawCancel);
      ctx.expect(seen != null, 'model never received a signal');
      ctx.expect(sawCancel, 'provider signal did not report cancellation');

      final preCancelled = CancellationToken()..cancel();
      final idle = _AcmeEmbeddingModel();
      await ctx.expectThrows<AiOperationCancelledError>(
        () => embed(model: idle, value: 'x', abortSignal: preCancelled),
        'embed with cancelled token',
      );
      ctx.expectEquals(idle.calls.length, 0, 'no provider call after cancel');

      var ran = false;
      await ctx.expectThrows<AiOperationCancelledError>(() async {
        await runWithAbortSignal(() async {
          ran = true;
          return 1;
        }, preCancelled);
      }, 'runWithAbortSignal pre-cancelled');
      ctx.expect(!ran, 'operation ran despite a cancelled signal');
      final live = CancellationToken();
      final pending = Completer<int>();
      final raced = runWithAbortSignal(() => pending.future, live);
      live.cancel();
      await ctx.expectThrows<AiOperationCancelledError>(() async {
        await raced;
      }, 'runWithAbortSignal cancelled while pending');
      ctx.expectEquals(
        await runWithAbortSignal(() async => 7, CancellationToken()),
        7,
        'runWithAbortSignal passes the value through',
      );
      var fired = 0;
      final token2 = CancellationToken();
      final observation = AbortSignalObservation.attach(token2, () => fired++);
      token2.cancel();
      token2.cancel();
      await observation.dispose();
      ctx.expectEquals(fired, 1, 'observation fires once');
    },
  ),
  Check(
    id: 'api-error-parsing',
    feature: 'provider-errors',
    description:
        'AiApiCallError.fromResponse turns provider bodies into message, '
        'type, code, body and isRetryable for the common error shapes.',
    run: (ctx) async {
      AiApiCallError parse(
        int? status,
        Object? body, {
        Map<String, String>? headers,
      }) => AiApiCallError.fromResponse(
        statusCode: status,
        url: 'https://api.acme.test/v1/x',
        body: body,
        responseHeaders: headers,
        provider: 'acme',
      );
      final nested = parse(401, {
        'error': {'message': 'bad key', 'type': 'auth', 'code': 'k1'},
      });
      ctx.expectEquals(nested.message, 'bad key', 'nested message');
      ctx.expectEquals(nested.type, 'auth', 'nested type');
      ctx.expectEquals(nested.code, 'k1', 'nested code');
      ctx.expectEquals(nested.url, 'https://api.acme.test/v1/x', 'url');
      ctx.expect(!nested.isRetryable, '401 not retryable');
      final status = parse(400, {
        'error': {'message': 'm', 'status': 'INVALID_ARGUMENT'},
      });
      ctx.expectEquals(
        status.type,
        'INVALID_ARGUMENT',
        'Google-style status as type',
      );
      ctx.expectEquals(
        parse(500, {'error': 'flat string'}).message,
        'flat string',
        'error string',
      );
      ctx.expectEquals(
        parse(500, {'message': 'top level'}).message,
        'top level',
        'top-level message',
      );
      final bytes = parse(
        429,
        utf8.encode('{"error":{"message":"slow down"}}'),
      );
      ctx.expectEquals(bytes.message, 'slow down', 'byte body');
      ctx.expectEquals(
        parse(502, 'Bad Gateway').message,
        'Bad Gateway',
        'plain text body',
      );
      ctx.expectEquals(
        parse(502, 'Bad Gateway').responseBody,
        'Bad Gateway',
        'raw body kept',
      );
      ctx.expectEquals(
        parse(500, '').message,
        'acme API error (500)',
        'empty body fallback',
      );
      ctx.expectEquals(
        parse(null, null).message,
        'acme API error',
        'no status fallback',
      );
      final headers = parse(429, '{}', headers: {'retry-after': '3'});
      ctx.expectEquals(headers.responseHeaders, {
        'retry-after': '3',
      }, 'headers kept');
      final retryable = <int, bool>{
        for (final code in [
          400,
          401,
          403,
          404,
          408,
          409,
          422,
          429,
          500,
          502,
          503,
        ])
          code: parse(code, '{}').isRetryable,
      };
      ctx.observe('retryable', retryable);
      ctx.expectEquals(retryable, {
        400: false,
        401: false,
        403: false,
        404: false,
        408: true,
        409: true,
        422: false,
        429: true,
        500: true,
        502: true,
        503: true,
      }, 'retryable status table');
      ctx.expect(!parse(null, null).isRetryable, 'no status is not retryable');
      ctx.expect(AiApiCallError.isInstance(nested), 'isInstance');
      ctx.expect(
        !AiApiCallError.isInstance(StateError('x')),
        'isInstance negative',
      );
    },
  ),
  Check(
    id: 'http-helpers',
    feature: 'provider-http-helpers',
    description:
        'createProviderDio, providerEndpoint, apiErrorFromDioException and '
        'sseDataLines work against a real HTTP server the way a provider '
        'adapter uses them.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        switch (request.path) {
          case '/v1/ok':
            return FixtureResponse.json({'hello': 'world'});
          case '/v1/limited':
            return FixtureResponse.json(
              {
                'error': {'message': 'Rate limited.', 'type': 'rate_limit'},
              },
              status: 429,
              headers: {'retry-after': '2'},
            );
          case '/v1/stream':
            // Raw bytes: FixtureResponse.sse cannot emit comment lines.
            return FixtureResponse.text(
              'event: message\ndata: {"n":1}\n\n'
              ': comment line\n\n'
              'data: multi\ndata: line\n\n'
              'data: [DONE]\n\n',
              contentType: 'text/event-stream',
            );
        }
        return FixtureResponse.text('missing', status: 404);
      });
      ctx.expectEquals(
        providerEndpoint('https://api.acme.test/v1/', 'chat'),
        'https://api.acme.test/v1/chat',
        'providerEndpoint trims the trailing slash',
      );
      ctx.expectEquals(
        providerEndpoint('https://api.acme.test/v1', '/chat'),
        'https://api.acme.test/v1/chat',
        'providerEndpoint adds one slash',
      );
      final dio = createProviderDio(
        baseUrl: '${server.url('/v1')}/',
        headers: {'x-acme-key': 'k'},
      );
      ctx.onCleanup(() async => dio.close(force: true));
      ctx.expectEquals(
        dio.options.baseUrl,
        server.url('/v1'),
        'baseUrl trimmed',
      );
      final ok = await dio.get<Map<String, dynamic>>('/ok');
      ctx.expectEquals(ok.data, {'hello': 'world'}, 'JSON response decoded');
      ctx.expectEquals(
        ctx.requestsTo(server, '/v1/ok').single.headers['x-acme-key'],
        'k',
        'default header sent',
      );

      DioException? failure;
      try {
        await dio.get<Map<String, dynamic>>('/limited');
      } on DioException catch (error) {
        failure = error;
      }
      ctx.expect(failure != null, '429 should raise DioException');
      final mapped = await apiErrorFromDioException(failure!, provider: 'acme');
      ctx.expect(mapped is AiApiCallError, 'mapped to ${mapped.runtimeType}');
      mapped as AiApiCallError;
      ctx.observe('mapped', {
        'status': mapped.statusCode,
        'message': mapped.message,
        'headers': mapped.responseHeaders,
        'retryable': mapped.isRetryable,
      });
      ctx.expectEquals(mapped.statusCode, 429, 'status');
      ctx.expectEquals(mapped.message, 'Rate limited.', 'message');
      ctx.expectEquals(mapped.type, 'rate_limit', 'type');
      ctx.expect(mapped.isRetryable, '429 retryable');
      ctx.expectEquals(
        mapped.responseHeaders?['retry-after'],
        '2',
        'retry-after kept',
      );
      ctx.expect(
        (mapped.url ?? '').endsWith('/v1/limited'),
        'url ${mapped.url}',
      );

      final cancelToken = CancelToken()..cancel('stop');
      DioException? cancelled;
      try {
        await dio.get<Map<String, dynamic>>('/ok', cancelToken: cancelToken);
      } on DioException catch (error) {
        cancelled = error;
      }
      ctx.expect(
        await apiErrorFromDioException(cancelled!, provider: 'acme')
            is AiOperationCancelledError,
        'cancelled request maps to AiOperationCancelledError',
      );

      final response = await dio.get<ResponseBody>(
        '/stream',
        options: Options(responseType: ResponseType.stream),
      );
      final payloads = await sseDataLines(response.data!.stream).toList();
      ctx.observe('ssePayloads', payloads);
      ctx.expectEquals(payloads, [
        '{"n":1}',
        'multi\nline',
        '[DONE]',
      ], 'sseDataLines payloads (comments and event names skipped)');
    },
  ),
  Check(
    id: 'shared-value-types',
    feature: 'provider-shared-types',
    description:
        'Shared value types behave as documented: all 22 stream part types, '
        'data content helpers, JSON helpers and ProviderCapabilityDescriptor '
        'defaults.',
    run: (ctx) async {
      const toolCall = LanguageModelV4ToolCallPart(
        toolCallId: 'c',
        toolName: 't',
        input: {},
      );
      final parts = <LanguageModelV4StreamPart>[
        const StreamPartTextStart(id: 'a'),
        const StreamPartTextDelta(id: 'a', delta: 'x'),
        const StreamPartTextEnd(id: 'a'),
        const StreamPartReasoningStart(id: 'b'),
        const StreamPartReasoningDelta(id: 'b', delta: 'x'),
        const StreamPartReasoningEnd(id: 'b'),
        const StreamPartSource(
          source: LanguageModelV4SourcePart(id: 's', url: 'https://x.test'),
        ),
        const StreamPartDocumentSource(
          source: LanguageModelV4DocumentSourcePart(
            id: 'd',
            mediaType: 'application/pdf',
            title: 'Doc',
          ),
        ),
        const StreamPartFile(
          file: LanguageModelV4FilePart(
            data: DataContentBase64('QQ=='),
            mediaType: 'text/plain',
          ),
        ),
        const StreamPartReasoningFile(
          file: LanguageModelV4ReasoningFilePart(
            data: DataContentBase64('QQ=='),
            mediaType: 'text/plain',
          ),
        ),
        const StreamPartOpaque(
          opaque: LanguageModelV4OpaquePart(provider: 'acme', raw: {'k': 1}),
        ),
        const StreamPartToolInputStart(id: 'i', toolName: 't'),
        const StreamPartToolInputDelta(id: 'i', delta: '{}'),
        const StreamPartToolInputEnd(id: 'i'),
        const StreamPartToolCall(toolCall: toolCall),
        const StreamPartToolResult(
          toolResult: LanguageModelV4ToolResultPart(
            toolCallId: 'c',
            toolName: 't',
            output: ToolResultOutputText('done'),
          ),
        ),
        const StreamPartToolApprovalRequest(
          approvalRequest: LanguageModelV4ToolApprovalRequestPart(
            approvalId: 'ap',
            toolCall: toolCall,
          ),
        ),
        const StreamPartStreamStart(),
        StreamPartResponseMetadata(
          metadata: LanguageModelV4ResponseMetadata(id: 'r'),
        ),
        const StreamPartRaw(rawValue: {'raw': true}),
        const StreamPartError(error: 'boom'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ];
      // An exhaustive switch over the sealed type: adding or removing a part
      // type without updating this list fails the build.
      String nameOf(LanguageModelV4StreamPart part) => switch (part) {
        StreamPartTextStart() => 'text-start',
        StreamPartTextDelta() => 'text-delta',
        StreamPartTextEnd() => 'text-end',
        StreamPartReasoningStart() => 'reasoning-start',
        StreamPartReasoningDelta() => 'reasoning-delta',
        StreamPartReasoningEnd() => 'reasoning-end',
        StreamPartSource() => 'source',
        StreamPartDocumentSource() => 'document-source',
        StreamPartFile() => 'file',
        StreamPartReasoningFile() => 'reasoning-file',
        StreamPartOpaque() => 'opaque',
        StreamPartToolInputStart() => 'tool-input-start',
        StreamPartToolInputDelta() => 'tool-input-delta',
        StreamPartToolInputEnd() => 'tool-input-end',
        StreamPartToolCall() => 'tool-call',
        StreamPartToolResult() => 'tool-result',
        StreamPartToolApprovalRequest() => 'tool-approval-request',
        StreamPartStreamStart() => 'stream-start',
        StreamPartResponseMetadata() => 'response-metadata',
        StreamPartRaw() => 'raw',
        StreamPartError() => 'error',
        StreamPartFinish() => 'finish',
      };
      final names = parts.map(nameOf).toSet();
      ctx.observe('streamPartTypes', names.toList());
      ctx.expectEquals(
        const StreamPartFinish(
          finishReason: LanguageModelV4FinishReason.stop,
        ).usage.inputTokens.total,
        null,
        'default usage is empty',
      );
      ctx.expect(
        const LanguageModelV4ToolResultPart(
          toolCallId: 'c',
          toolName: 't',
          output: ToolResultOutputErrorText('failed'),
        ).isError,
        'error output marks the tool result as an error',
      );
      ctx.expect(
        const LanguageModelV4ToolResultPart(
          toolCallId: 'c',
          toolName: 't',
          output: ToolResultOutputExecutionDenied(),
        ).isError,
        'denied execution marks the tool result as an error',
      );

      ctx.expectEquals(
        dataContentToBase64(DataContentBytes(Uint8List.fromList([104, 105]))),
        'aGk=',
        'bytes to base64',
      );
      ctx.expectEquals(
        dataContentToBase64(const DataContentBase64('aGk=')),
        'aGk=',
        'base64 passthrough',
      );
      ctx.expectEquals(
        dataContentToBase64(DataContentUrl(Uri.parse('https://x.test/a'))),
        null,
        'URL has no base64',
      );
      ctx.expectThrowsSync<UnsupportedError>(
        () => dataContentToBase64(
          const DataContentProviderReference(namespace: 'acme', id: 'f1'),
        ),
        'provider reference needs a provider serializer',
      );

      ctx.expectEquals(intOrNull(7), 7, 'intOrNull int');
      ctx.expectEquals(intOrNull(7.9), 7, 'intOrNull double');
      ctx.expectEquals(intOrNull('12'), 12, 'intOrNull string');
      ctx.expectEquals(intOrNull('x'), null, 'intOrNull garbage');
      ctx.expectEquals(safeParseJson('{"a":1}'), {
        'a': 1,
      }, 'safeParseJson object');
      ctx.expectEquals(
        safeParseJson('not json'),
        'not json',
        'safeParseJson fallback',
      );
      ctx.expect(prefixedId('call').startsWith('call-'), 'prefixedId prefix');

      final descriptor = ProviderCapabilityDescriptor(
        provider: 'acme',
        modelId: 'acme-embed-1',
        apiSurface: 'embeddings',
        source: Uri.parse('https://docs.acme.test/embeddings'),
        verifiedOn: DateTime.utc(2026, 1, 1),
        maxEmbeddingsPerCall: 96,
      );
      ctx.expectEquals(
        descriptor.lifecycle,
        ProviderCapabilityLifecycle.stable,
        'default lifecycle',
      );
      ctx.expectEquals(
        descriptor.confidence,
        ProviderCapabilityConfidence.catalog,
        'default confidence',
      );
      ctx.expectEquals(
        descriptor.maxEmbeddingsPerCall,
        96,
        'maxEmbeddingsPerCall',
      );
      ctx.expectEquals(descriptor.features.length, 0, 'default features empty');
    },
  ),
]);

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
