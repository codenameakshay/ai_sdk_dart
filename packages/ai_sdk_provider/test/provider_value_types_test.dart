import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('provider value types', () {
    test('language model contracts expose configured values', () {
      final prompt = LanguageModelV3Prompt(
        system: 'system',
        messages: [
          LanguageModelV3Message(
            role: LanguageModelV3Role.user,
            content: const [LanguageModelV3TextPart(text: 'hello')],
          ),
        ],
      );
      final tool = LanguageModelV3FunctionTool(
        name: 'lookup',
        description: 'Finds records',
        strict: true,
        inputSchema: {'type': 'object'},
        inputExamples: const [
          {'query': 'widgets'},
        ],
      );
      final providerTool = LanguageModelV3ProviderDefinedTool(
        id: 'provider.lookup',
        name: 'lookup',
        description: 'Provider-defined lookup',
        args: const {'region': 'us'},
      );
      final toolChoice = const ToolChoiceSpecific(toolName: 'lookup');
      final options = LanguageModelV3CallOptions(
        prompt: prompt,
        tools: [tool],
        providerDefinedTools: [providerTool],
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
        outputSchema: const {'type': 'object'},
      );
      final imageBytes = Uint8List.fromList([1, 2, 3]);
      final imageData = DataContentBytes(imageBytes);
      final base64Data = const DataContentBase64('AQID');
      final urlData = DataContentUrl(Uri.parse('https://example.com/file.bin'));
      final source = const LanguageModelV3SourcePart(
        id: 'src-1',
        url: 'https://example.com',
        title: 'Example',
        providerMetadata: {'openai': true},
      );
      final filePart = LanguageModelV3FilePart(
        data: imageData,
        mediaType: 'application/pdf',
        filename: 'doc.pdf',
        providerOptions: const {'kind': 'file'},
      );
      final toolCall = const LanguageModelV3ToolCallPart(
        toolCallId: 'call-1',
        toolName: 'lookup',
        input: {'query': 'widgets'},
        providerOptions: {'strict': true},
      );
      final toolApprovalRequest = LanguageModelV3ToolApprovalRequestPart(
        approvalId: 'approval-1',
        toolCall: toolCall,
      );
      final toolResult = const LanguageModelV3ToolResultPart(
        toolCallId: 'call-1',
        toolName: 'lookup',
        output: ToolResultOutputText('done'),
        isError: true,
        providerOptions: {'fromCache': false},
      );
      final contentOutput = ToolResultOutputContent([
        const LanguageModelV3TextPart(text: 'nested'),
      ]);
      final responseMetadata = LanguageModelV3ResponseMetadata(
        id: 'resp-1',
        modelId: 'model-1',
        timestamp: DateTime.utc(2026, 8, 10),
        headers: const {'x-response': '1'},
        body: const {'ok': true},
        requestBody: const {'messages': 1},
      );
      final usage = const LanguageModelV3Usage(
        inputTokens: 10,
        outputTokens: 5,
        totalTokens: 15,
        inputTokenDetails: LanguageModelV3InputTokenDetails(
          noCacheTokens: 4,
          cacheReadTokens: 3,
          cacheWriteTokens: 3,
        ),
        outputTokenDetails: LanguageModelV3OutputTokenDetails(
          textTokens: 4,
          reasoningTokens: 1,
        ),
        raw: {'provider': 'openai'},
      );
      final generateResult = LanguageModelV3GenerateResult(
        content: [
          const LanguageModelV3TextPart(
            text: 'hello',
            providerOptions: {'tone': 'neutral'},
          ),
          LanguageModelV3ImagePart(
            image: base64Data,
            mediaType: 'image/png',
            providerOptions: const {'detail': 'high'},
          ),
          filePart,
          const LanguageModelV3ReasoningPart(
            text: 'think',
            signature: 'sig',
            providerOptions: {'hidden': false},
          ),
          LanguageModelV3RedactedReasoningPart(
            data: Uint8List.fromList([9, 9]),
            providerOptions: const {'redacted': true},
          ),
          toolCall,
          toolApprovalRequest,
          toolResult,
          source,
          const LanguageModelV3ToolApprovalResponse(
            approvalId: 'approval-1',
            approved: false,
            reason: 'denied',
          ),
        ],
        finishReason: LanguageModelV3FinishReason.toolCalls,
        rawFinishReason: 'tool_calls',
        usage: usage,
        warnings: const ['warn'],
        response: responseMetadata,
        providerMetadata: const {
          'openai': {'id': 'resp-1'},
        },
      );
      final streamResult = LanguageModelV3StreamResult(
        stream: Stream<LanguageModelV3StreamPart>.fromIterable([
          const StreamPartTextStart(id: 'text-1'),
          const StreamPartTextDelta(id: 'text-1', delta: 'hel'),
          const StreamPartTextEnd(id: 'text-1'),
          const StreamPartReasoningDelta(delta: 'thinking'),
          StreamPartSource(source: source),
          StreamPartFile(file: filePart),
          const StreamPartToolCallStart(
            toolCallId: 'call-1',
            toolName: 'lookup',
          ),
          const StreamPartToolCallDelta(
            toolCallId: 'call-1',
            toolName: 'lookup',
            argsTextDelta: '{"query":',
          ),
          const StreamPartToolCallEnd(
            toolCallId: 'call-1',
            toolName: 'lookup',
            input: {'query': 'widgets'},
          ),
          const StreamPartError(error: 'boom'),
          StreamPartFinish(
            finishReason: LanguageModelV3FinishReason.stop,
            rawFinishReason: 'stop',
            usage: usage,
            providerMetadata: const {
              'openai': {'cached': false},
            },
          ),
        ]),
        rawResponse: const {'raw': true},
      );

      expect(options.prompt.system, 'system');
      expect(options.tools.single.name, 'lookup');
      expect(options.providerDefinedTools.single.id, 'provider.lookup');
      expect((options.toolChoice as ToolChoiceSpecific).toolName, 'lookup');
      expect(options.maxOutputTokens, 64);
      expect(options.stopSequences, ['STOP']);
      expect(options.providerOptions?['openai']?['reasoningEffort'], 'medium');
      expect(options.outputSchema?['type'], 'object');

      expect(imageData.bytes, same(imageBytes));
      expect(base64Data.base64, 'AQID');
      expect(urlData.url.host, 'example.com');

      final imagePart = generateResult.content[1] as LanguageModelV3ImagePart;
      expect(imagePart.mediaType, 'image/png');
      expect(imagePart.providerOptions?['detail'], 'high');
      expect(filePart.filename, 'doc.pdf');
      expect(toolCall.providerOptions?['strict'], true);
      expect(toolApprovalRequest.toolCall.toolName, 'lookup');
      expect((toolResult.output as ToolResultOutputText).text, 'done');
      expect(
        (contentOutput.parts.single as LanguageModelV3TextPart).text,
        'nested',
      );
      expect(source.providerMetadata?['openai'], true);

      expect(
        generateResult.finishReason,
        LanguageModelV3FinishReason.toolCalls,
      );
      expect(generateResult.rawFinishReason, 'tool_calls');
      expect(generateResult.usage?.totalTokens, 15);
      expect(generateResult.response?.headers?['x-response'], '1');
      expect(generateResult.providerMetadata?['openai']?['id'], 'resp-1');
      expect(
        usage.toString(),
        'LanguageModelV3Usage(input: 10, output: 5, total: 15)',
      );
      expect(usage.inputTokenDetails?.cacheReadTokens, 3);
      expect(usage.outputTokenDetails?.reasoningTokens, 1);

      expect(streamResult.rawResponse, {'raw': true});
      expect(
        streamResult.stream,
        emitsInOrder([
          isA<StreamPartTextStart>(),
          isA<StreamPartTextDelta>(),
          isA<StreamPartTextEnd>(),
          isA<StreamPartReasoningDelta>(),
          isA<StreamPartSource>(),
          isA<StreamPartFile>(),
          isA<StreamPartToolCallStart>(),
          isA<StreamPartToolCallDelta>(),
          isA<StreamPartToolCallEnd>(),
          isA<StreamPartError>(),
          isA<StreamPartFinish>(),
          emitsDone,
        ]),
      );

      expect(const ToolChoiceAuto(), isA<LanguageModelV3ToolChoice>());
      expect(const ToolChoiceNone(), isA<LanguageModelV3ToolChoice>());
      expect(const ToolChoiceRequired(), isA<LanguageModelV3ToolChoice>());
      expect(
        LanguageModelV3FinishReason.values,
        containsAll([
          LanguageModelV3FinishReason.stop,
          LanguageModelV3FinishReason.length,
          LanguageModelV3FinishReason.contentFilter,
          LanguageModelV3FinishReason.toolCalls,
          LanguageModelV3FinishReason.error,
          LanguageModelV3FinishReason.other,
          LanguageModelV3FinishReason.unknown,
        ]),
      );
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
        response: const LanguageModelV3ResponseMetadata(id: 'resp'),
        usage: const LanguageModelV3Usage(totalTokens: 1),
        cause: const FormatException('bad json'),
      );
      final repairError = const AiToolCallRepairError(
        message: 'repair failed',
        toolName: 'lookup',
        cause: 'invalid schema',
        repairAttempts: 2,
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
      );
      final downloadError = const AiDownloadError(
        message: 'download failed',
        url: 'https://example.com/audio.wav',
        statusCode: 404,
        cause: 'not found',
      );

      expect(cancelled.message, 'Operation cancelled.');
      expect(AiOperationCancelledError.isInstance(cancelled), isTrue);
      expect(AiOperationCancelledError.isInstance(noSuchTool), isFalse);
      expect(noSuchTool.toString(), 'AiNoSuchToolError: missing tool');
      expect(invalidInput.message, 'bad input');
      expect(noContent.message, 'empty');

      expect(noObject.text, '{}');
      expect(noObject.response?.id, 'resp');
      expect(noObject.usage?.totalTokens, 1);
      expect(noObject.cause, isA<FormatException>());
      expect(AiNoObjectGeneratedError.isInstance(noObject), isTrue);

      expect(repairError.toolName, 'lookup');
      expect(repairError.repairAttempts, 2);
      expect(AiToolCallRepairError.isInstance(repairError), isTrue);

      expect(noImage.cause, 'timeout');
      expect(AiNoImageGeneratedError.isInstance(noImage), isTrue);
      expect(noSpeech.cause, 'timeout');
      expect(AiNoSpeechGeneratedError.isInstance(noSpeech), isTrue);
      expect(noTranscript.cause, 'timeout');
      expect(AiNoTranscriptGeneratedError.isInstance(noTranscript), isTrue);

      expect(retryError.attempts, 3);
      expect(retryError.lastError, 'boom');
      expect(AiRetryError.isInstance(retryError), isTrue);

      expect(downloadError.url, 'https://example.com/audio.wav');
      expect(downloadError.statusCode, 404);
      expect(downloadError.cause, 'not found');
      expect(AiDownloadError.isInstance(downloadError), isTrue);
    });
  });
}
