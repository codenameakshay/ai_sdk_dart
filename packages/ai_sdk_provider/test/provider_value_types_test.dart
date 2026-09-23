import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('provider value types', () {
    test(
      'language model base contract supplies default specification values',
      () async {
        final model = _FakeLanguageModel();

        expect(model.specificationVersion, 'v4');
        expect(model.provider, 'fake');
        expect(model.modelId, 'fake-model');
        expect(await model.supportedUrls, isEmpty);
      },
    );

    test('language model contracts expose configured values', () {
      final prompt = LanguageModelV4Prompt(
        system: 'system',
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.user,
            content: const [LanguageModelV4TextPart(text: 'hello')],
          ),
        ],
      );
      final tool = LanguageModelV4FunctionTool(
        name: 'lookup',
        description: 'Finds records',
        strict: true,
        inputSchema: {'type': 'object'},
        inputExamples: const [
          {'query': 'widgets'},
        ],
      );
      final providerTool = LanguageModelV4ProviderDefinedTool(
        id: 'provider.lookup',
        name: 'lookup',
        description: 'Provider-defined lookup',
        args: const {'region': 'us'},
      );
      final toolChoice = const ToolChoiceSpecific(toolName: 'lookup');
      final options = LanguageModelV4CallOptions(
        prompt: prompt,
        tools: [tool, providerTool],
        toolChoice: toolChoice,
        maxOutputTokens: 64,
        temperature: 0.7,
        topP: 0.8,
        topK: 40,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        stopSequences: const ['STOP'],
        seed: 7,
        headers: const {'x-test': '1'},
        providerOptions: const {
          'openai': {'reasoningEffort': 'medium'},
        },
        responseFormat: const LanguageModelV4JsonResponseFormat(
          schema: {'type': 'object'},
        ),
      );
      final imageBytes = Uint8List.fromList([1, 2, 3]);
      final imageData = DataContentBytes(imageBytes);
      final base64Data = const DataContentBase64('AQID');
      final urlData = DataContentUrl(Uri.parse('https://example.com/file.bin'));
      final source = const LanguageModelV4SourcePart(
        id: 'src-1',
        url: 'https://example.com',
        title: 'Example',
        providerMetadata: {'openai': true},
      );
      final filePart = LanguageModelV4FilePart(
        data: imageData,
        mediaType: 'application/pdf',
        filename: 'doc.pdf',
        providerOptions: const {'kind': 'file'},
      );
      final toolCall = const LanguageModelV4ToolCallPart(
        toolCallId: 'call-1',
        toolName: 'lookup',
        input: {'query': 'widgets'},
        providerOptions: {'strict': true},
      );
      final toolApprovalRequest = LanguageModelV4ToolApprovalRequestPart(
        approvalId: 'approval-1',
        toolCall: toolCall,
      );
      final toolResult = const LanguageModelV4ToolResultPart(
        toolCallId: 'call-1',
        toolName: 'lookup',
        output: ToolResultOutputText('done'),
        isError: true,
        providerOptions: {'fromCache': false},
      );
      final contentOutput = ToolResultOutputContent([
        const LanguageModelV4TextPart(text: 'nested'),
      ]);
      const requestMetadata = LanguageModelV4RequestMetadata(
        body: {'messages': 1},
      );
      final responseMetadata = LanguageModelV4ResponseMetadata(
        id: 'resp-1',
        modelId: 'model-1',
        timestamp: DateTime.utc(2026, 8, 10),
        headers: const {'x-response': '1'},
        body: const {'ok': true},
      );
      final usage = const LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(
          total: 10,
          noCache: 4,
          cacheRead: 3,
          cacheWrite: 3,
        ),
        outputTokens: LanguageModelV4OutputTokenUsage(
          total: 5,
          text: 4,
          reasoning: 1,
        ),
        raw: {'provider': 'openai'},
      );
      final generateResult = LanguageModelV4GenerateResult(
        content: [
          const LanguageModelV4TextPart(
            text: 'hello',
            providerOptions: {'tone': 'neutral'},
          ),
          LanguageModelV4ImagePart(
            image: base64Data,
            mediaType: 'image/png',
            providerOptions: const {'detail': 'high'},
          ),
          filePart,
          const LanguageModelV4ReasoningPart(
            text: 'think',
            signature: 'sig',
            providerOptions: {'hidden': false},
          ),
          LanguageModelV4RedactedReasoningPart(
            data: Uint8List.fromList([9, 9]),
            providerOptions: const {'redacted': true},
          ),
          toolCall,
          toolApprovalRequest,
          toolResult,
          source,
          const LanguageModelV4ToolApprovalResponse(
            approvalId: 'approval-1',
            approved: false,
            reason: 'denied',
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
        rawFinishReason: 'tool_calls',
        usage: usage,
        warnings: const [
          LanguageModelV4UnsupportedWarning(
            feature: 'topK',
            details: 'Provider ignored topK.',
          ),
          LanguageModelV4OtherWarning(message: 'warn'),
        ],
        request: requestMetadata,
        response: responseMetadata,
        providerMetadata: const {
          'openai': {'id': 'resp-1'},
        },
      );
      final streamResult = LanguageModelV4StreamResult(
        stream: Stream<LanguageModelV4StreamPart>.fromIterable([
          StreamPartStreamStart(
            warnings: [LanguageModelV4CompatibilityWarning(feature: 'urls')],
          ),
          const StreamPartTextStart(id: 'text-1'),
          const StreamPartTextDelta(id: 'text-1', delta: 'hel'),
          const StreamPartTextEnd(id: 'text-1'),
          StreamPartReasoningStart(id: 'reasoning-1'),
          const StreamPartReasoningDelta(id: 'reasoning-1', delta: 'thinking'),
          StreamPartReasoningEnd(id: 'reasoning-1'),
          StreamPartSource(source: source),
          StreamPartFile(file: filePart),
          const StreamPartToolInputStart(id: 'call-1', toolName: 'lookup'),
          const StreamPartToolInputDelta(id: 'call-1', delta: '{"query":'),
          const StreamPartToolInputEnd(id: 'call-1'),
          const StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'call-1',
              toolName: 'lookup',
              input: {'query': 'widgets'},
            ),
          ),
          StreamPartToolResult(toolResult: toolResult, preliminary: true),
          StreamPartToolApprovalRequest(approvalRequest: toolApprovalRequest),
          StreamPartResponseMetadata(metadata: responseMetadata),
          StreamPartRaw(rawValue: {'chunk': 1}),
          const StreamPartError(error: 'boom'),
          StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
            rawFinishReason: 'stop',
            usage: usage,
            providerMetadata: const {
              'openai': {'cached': false},
            },
          ),
        ]),
        warnings: const [
          LanguageModelV4DeprecatedWarning(
            setting: 'legacy-mode',
            message: 'Use the default mode.',
          ),
        ],
        request: requestMetadata,
        response: responseMetadata,
      );

      expect(options.prompt.system, 'system');
      expect(options.functionTools.single.name, 'lookup');
      expect(options.providerTools.single.id, 'provider.lookup');
      expect((options.toolChoice as ToolChoiceSpecific).toolName, 'lookup');
      expect(options.maxOutputTokens, 64);
      expect(options.stopSequences, ['STOP']);
      expect(options.providerOptions?['openai']?['reasoningEffort'], 'medium');
      expect(
        (options.responseFormat as LanguageModelV4JsonResponseFormat)
            .schema?['type'],
        'object',
      );
      expect(
        LanguageModelV4TextResponseFormat(),
        isA<LanguageModelV4ResponseFormat>(),
      );

      expect(imageData.bytes, same(imageBytes));
      expect(base64Data.base64, 'AQID');
      expect(urlData.url.host, 'example.com');

      final imagePart = generateResult.content[1] as LanguageModelV4ImagePart;
      expect(imagePart.mediaType, 'image/png');
      expect(imagePart.providerOptions?['detail'], 'high');
      expect(filePart.filename, 'doc.pdf');
      expect(toolCall.providerOptions?['strict'], true);
      expect(toolApprovalRequest.toolCall.toolName, 'lookup');
      expect((toolResult.output as ToolResultOutputText).text, 'done');
      expect(
        (contentOutput.parts.single as LanguageModelV4TextPart).text,
        'nested',
      );
      expect(source.providerMetadata?['openai'], true);

      expect(
        generateResult.finishReason,
        LanguageModelV4FinishReason.toolCalls,
      );
      expect(generateResult.rawFinishReason, 'tool_calls');
      expect(generateResult.usage.inputTokens.total, 10);
      expect(generateResult.usage.outputTokens.total, 5);
      expect(generateResult.request?.body, {'messages': 1});
      expect(generateResult.response?.headers?['x-response'], '1');
      expect(generateResult.providerMetadata?['openai']?['id'], 'resp-1');
      expect(usage.toString(), 'LanguageModelV4Usage(input: 10, output: 5)');
      expect(usage.inputTokens.cacheRead, 3);
      expect(usage.outputTokens.reasoning, 1);
      expect(
        (generateResult.warnings.first as LanguageModelV4UnsupportedWarning)
            .feature,
        'topK',
      );

      expect(streamResult.request?.body, {'messages': 1});
      expect(streamResult.response?.headers?['x-response'], '1');
      expect(streamResult.warnings, hasLength(1));
      expectLater(
        streamResult.stream,
        emitsInOrder([
          isA<StreamPartStreamStart>(),
          isA<StreamPartTextStart>(),
          isA<StreamPartTextDelta>(),
          isA<StreamPartTextEnd>(),
          isA<StreamPartReasoningStart>(),
          isA<StreamPartReasoningDelta>(),
          isA<StreamPartReasoningEnd>(),
          isA<StreamPartSource>(),
          isA<StreamPartFile>(),
          isA<StreamPartToolInputStart>(),
          isA<StreamPartToolInputDelta>(),
          isA<StreamPartToolInputEnd>(),
          isA<StreamPartToolCall>(),
          isA<StreamPartToolResult>(),
          isA<StreamPartToolApprovalRequest>(),
          isA<StreamPartResponseMetadata>(),
          isA<StreamPartRaw>(),
          isA<StreamPartError>(),
          predicate<StreamPartFinish>((part) {
            return part.finishReason == LanguageModelV4FinishReason.stop &&
                part.usage.outputTokens.total == 5;
          }),
          emitsDone,
        ]),
      );

      expect(const ToolChoiceAuto(), isA<LanguageModelV4ToolChoice>());
      expect(const ToolChoiceNone(), isA<LanguageModelV4ToolChoice>());
      expect(const ToolChoiceRequired(), isA<LanguageModelV4ToolChoice>());
      expect(
        LanguageModelV4FinishReason.values,
        containsAll([
          LanguageModelV4FinishReason.stop,
          LanguageModelV4FinishReason.length,
          LanguageModelV4FinishReason.contentFilter,
          LanguageModelV4FinishReason.toolCalls,
          LanguageModelV4FinishReason.error,
          LanguageModelV4FinishReason.other,
          LanguageModelV4FinishReason.unknown,
        ]),
      );
    });

    test('warning variants expose stable types and payloads', () {
      final unsupported = LanguageModelV4UnsupportedWarning(
        feature: 'logprobs',
        details: 'Provider does not support logprobs.',
      );
      final compatibility = LanguageModelV4CompatibilityWarning(
        feature: 'sources',
        details: 'Provider may omit source URLs.',
      );
      final deprecated = LanguageModelV4DeprecatedWarning(
        setting: 'legacy-mode',
        message: 'Use the default mode.',
      );
      final other = LanguageModelV4OtherWarning(message: 'Heads up.');

      expect(unsupported.type, 'unsupported');
      expect(unsupported.feature, 'logprobs');
      expect(unsupported.details, 'Provider does not support logprobs.');

      expect(compatibility.type, 'compatibility');
      expect(compatibility.feature, 'sources');
      expect(compatibility.details, 'Provider may omit source URLs.');

      expect(deprecated.type, 'deprecated');
      expect(deprecated.setting, 'legacy-mode');
      expect(deprecated.message, 'Use the default mode.');

      expect(other.type, 'other');
      expect(other.message, 'Heads up.');
    });

    test(
      'preserves opaque, document, reasoning-file, and provider references',
      () {
        const opaque = LanguageModelV4OpaquePart(
          provider: 'fake',
          raw: {'kind': 'response.item'},
        );
        const document = LanguageModelV4DocumentSourcePart(
          id: 'doc-1',
          mediaType: 'application/pdf',
          title: 'Guide',
          filename: 'guide.pdf',
        );
        final reasoningFile = LanguageModelV4ReasoningFilePart(
          data: DataContentBytes(Uint8List.fromList([4, 5])),
          mediaType: 'application/pdf',
          filename: 'trace.pdf',
        );
        const toolResult = LanguageModelV4ToolResultPart(
          toolCallId: 'call-1',
          toolName: 'lookup',
          output: ToolResultOutputErrorText('failed'),
        );
        const jsonOutput = ToolResultOutputJson({'ok': true});
        const errorJsonOutput = ToolResultOutputErrorJson({'error': 'failed'});
        const urlSource = LanguageModelV4SourcePart(
          id: 'url-1',
          url: 'https://example.com',
        );

        expect(opaque.provider, 'fake');
        expect(opaque.raw, {'kind': 'response.item'});
        expect(document.sourceType, 'document');
        expect(document.filename, 'guide.pdf');
        expect(reasoningFile.mediaType, 'application/pdf');
        expect(reasoningFile.filename, 'trace.pdf');
        expect(reasoningFile.data, isA<DataContentBytes>());
        expect(toolResult.isError, isTrue);
        expect(jsonOutput.value, {'ok': true});
        expect(errorJsonOutput.value, {'error': 'failed'});
        expect(urlSource.sourceType, 'url');
        expect(
          const ToolResultOutputExecutionDenied().reason,
          'Tool call execution denied.',
        );
        expect(
          const ToolResultOutputExecutionDenied(
            'blocked',
            'approval-1',
          ).approvalId,
          'approval-1',
        );

        final streamParts = <LanguageModelV4StreamPart>[
          StreamPartDocumentSource(source: document),
          StreamPartReasoningFile(file: reasoningFile),
          const StreamPartOpaque(opaque: opaque),
        ];
        expect(streamParts[0], isA<StreamPartDocumentSource>());
        expect(streamParts[1], isA<StreamPartReasoningFile>());
        expect((streamParts[2] as StreamPartOpaque).opaque.provider, 'fake');
      },
    );

    test('provider-owned data references require an adapter serializer', () {
      const reference = DataContentProviderReference(
        namespace: 'fake',
        id: 'asset-1',
      );
      expect(reference.namespace, 'fake');
      expect(reference.id, 'asset-1');
      expect(
        () => dataContentToBase64(reference),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('capability descriptors retain evidence and lifecycle metadata', () {
      final descriptor = ProviderCapabilityDescriptor(
        provider: 'fake',
        modelId: 'fake-model',
        apiSurface: 'chat',
        source: Uri.parse('https://example.com/capabilities'),
        verifiedOn: DateTime.utc(2026, 8, 10),
        maxEmbeddingsPerCall: 128,
        supportsParallelCalls: true,
        features: const {'tools', 'vision'},
        feature: 'reasoning',
        lifecycle: ProviderCapabilityLifecycle.preview,
        confidence: ProviderCapabilityConfidence.fixture,
        evidenceId: 'fixture-1',
      );

      expect(descriptor.provider, 'fake');
      expect(descriptor.modelId, 'fake-model');
      expect(descriptor.maxEmbeddingsPerCall, 128);
      expect(descriptor.supportsParallelCalls, isTrue);
      expect(descriptor.features, containsAll(['tools', 'vision']));
      expect(descriptor.feature, 'reasoning');
      expect(descriptor.lifecycle, ProviderCapabilityLifecycle.preview);
      expect(descriptor.confidence, ProviderCapabilityConfidence.fixture);
      expect(descriptor.evidenceId, 'fixture-1');
    });

    test(
      'embedding, image, speech, transcription, and rerank types retain data',
      () {
        final embeddingOptions = EmbeddingModelV2CallOptions<String>(
          values: const ['one', 'two'],
          headers: const {'x-embed': '1'},
          providerOptions: const {
            'openai': {'dimensions': 3},
          },
        );
        final embeddingResult = EmbeddingModelV2GenerateResult<String>(
          embeddings: const [
            EmbeddingModelV2Embedding(value: 'one', embedding: [1, 2, 3]),
          ],
          usage: const EmbeddingModelV2Usage(tokens: 12),
          warnings: const ['warn'],
          providerMetadata: const {
            'openai': {'cached': true},
          },
        );
        final promptObject = GenerateImagePrompt(
          images: [
            DataContentBytes(Uint8List.fromList([7, 8])),
          ],
          text: 'paint',
          mask: const DataContentBase64('Bwg='),
        );
        final imageOptions = ImageModelV3CallOptions(
          prompt: 'paint',
          promptObject: promptObject,
          n: 2,
          size: '1024x1024',
          aspectRatio: '1:1',
          seed: 42,
          headers: const {'x-image': '1'},
          providerOptions: const {
            'openai': {'quality': 'high'},
          },
        );
        final imageResult = ImageModelV3GenerateResult(
          images: [
            GeneratedImage(
              bytes: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
          ],
          usage: const ImageModelV3Usage(imagesGenerated: 1),
          warnings: const ['warn'],
          providerMetadata: const {
            'openai': {'seed': 42},
          },
          responses: [
            ImageModelV3ResponseMetadata(
              timestamp: DateTime.utc(2026, 8, 10, 12),
              modelId: 'image-1',
              headers: const {'x-image-response': '1'},
            ),
          ],
        );
        final speechOptions = SpeechModelV1CallOptions(
          text: 'hello',
          voice: 'alloy',
          format: 'mp3',
          speed: 1.2,
          headers: const {'x-speech': '1'},
          providerOptions: const {
            'openai': {'voice': 'alloy'},
          },
        );
        final speechResult = SpeechModelV1GenerateResult(
          audio: Uint8List.fromList([1, 2]),
          mediaType: 'audio/mpeg',
        );
        final transcriptionOptions = TranscriptionModelV1CallOptions(
          audio: Uint8List.fromList([9, 8]),
          audioMediaType: 'audio/wav',
          language: 'en',
          prompt: 'transcribe this',
          headers: const {'x-transcribe': '1'},
          providerOptions: const {
            'openai': {'temperature': 0},
          },
        );
        final transcriptionResult = const TranscriptionModelV1GenerateResult(
          text: 'hello world',
        );
        final rerankOptions = RerankModelV1CallOptions(
          query: 'hello',
          documents: const ['b', 'a'],
          topN: 1,
          headers: const {'x-rerank': '1'},
          providerOptions: const {
            'cohere': {'returnDocuments': true},
          },
        );
        final rerankResult = const RerankModelV1Result(
          documents: [
            RerankDocument(index: 1, document: 'a', relevanceScore: 0.9),
          ],
        );

        expect(embeddingOptions.values, ['one', 'two']);
        expect(embeddingOptions.headers?['x-embed'], '1');
        expect(embeddingResult.embeddings.single.embedding, [1, 2, 3]);
        expect(embeddingResult.usage?.tokens, 12);
        expect(embeddingResult.providerMetadata?['openai']?['cached'], true);

        expect(promptObject.text, 'paint');
        expect(promptObject.mask, isA<DataContentBase64>());
        expect(
          imageOptions.promptObject?.images.single,
          isA<DataContentBytes>(),
        );
        expect(imageOptions.aspectRatio, '1:1');
        expect(imageResult.images.single.mediaType, 'image/png');
        expect(imageResult.usage?.imagesGenerated, 1);
        expect(imageResult.responses.single.modelId, 'image-1');

        expect(speechOptions.voice, 'alloy');
        expect(speechOptions.speed, 1.2);
        expect(speechResult.audio, hasLength(2));
        expect(speechResult.mediaType, 'audio/mpeg');

        expect(transcriptionOptions.audioMediaType, 'audio/wav');
        expect(transcriptionOptions.language, 'en');
        expect(transcriptionResult.text, 'hello world');

        expect(rerankOptions.documents, ['b', 'a']);
        expect(rerankOptions.topN, 1);
        expect(rerankResult.documents.single.relevanceScore, 0.9);

        expect(
          providerEndpoint('https://example.com/', 'v1/chat'),
          'https://example.com/v1/chat',
        );
        expect(
          providerEndpoint('https://example.com/base', '/v1/chat'),
          'https://example.com/base/v1/chat',
        );
      },
    );

    test('shared error types preserve their payloads', () {
      final cancelled = const AiOperationCancelledError();
      final noSuchTool = const AiNoSuchToolError('missing tool');
      final invalidInput = const AiInvalidToolInputError('bad input');
      final noContent = const AiNoContentGeneratedError('empty');
      final noObject = AiNoObjectGeneratedError(
        message: 'no object',
        text: '{}',
        response: const LanguageModelV4ResponseMetadata(id: 'resp'),
        usage: const LanguageModelV4Usage(
          outputTokens: LanguageModelV4OutputTokenUsage(total: 1),
        ),
        cause: const FormatException('bad json'),
      );
      final noImage = const AiNoImageGeneratedError(
        message: 'no image',
        cause: 'timeout',
      );
      final noSpeech = const AiNoSpeechGeneratedError(
        message: 'no speech',
        cause: 'timeout',
      );
      final noTranscript = const AiNoTranscriptGeneratedError(
        message: 'no transcript',
        cause: 'timeout',
      );
      final retryError = const AiRetryError(
        message: 'retries exhausted',
        attempts: 3,
        lastError: 'boom',
        errors: ['first', 'second', 'boom'],
      );
      final invalidEmbedding = const AiInvalidEmbeddingResponseError(
        'embedding count mismatch',
        expectedCount: 2,
        actualCount: 1,
        index: 1,
      );

      expect(cancelled.message, 'Operation cancelled.');
      expect(AiOperationCancelledError.isInstance(cancelled), isTrue);
      expect(AiOperationCancelledError.isInstance(noSuchTool), isFalse);
      expect(noSuchTool.toString(), 'AiNoSuchToolError: missing tool');
      expect(invalidInput.message, 'bad input');
      expect(noContent.message, 'empty');
      expect(invalidEmbedding.expectedCount, 2);
      expect(invalidEmbedding.actualCount, 1);
      expect(invalidEmbedding.index, 1);

      expect(noObject.text, '{}');
      expect(noObject.response?.id, 'resp');
      expect(noObject.usage?.outputTokens.total, 1);
      expect(noObject.cause, isA<FormatException>());
      expect(AiNoObjectGeneratedError.isInstance(noObject), isTrue);

      expect(noImage.cause, 'timeout');
      expect(AiNoImageGeneratedError.isInstance(noImage), isTrue);
      expect(noSpeech.cause, 'timeout');
      expect(AiNoSpeechGeneratedError.isInstance(noSpeech), isTrue);
      expect(noTranscript.cause, 'timeout');
      expect(AiNoTranscriptGeneratedError.isInstance(noTranscript), isTrue);

      expect(retryError.attempts, 3);
      expect(retryError.lastError, 'boom');
      expect(retryError.errors, ['first', 'second', 'boom']);
      expect(AiRetryError.isInstance(retryError), isTrue);
    });
  });
}

class _FakeLanguageModel extends LanguageModelV4 {
  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-model';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}
