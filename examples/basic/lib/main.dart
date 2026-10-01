/// AI SDK Dart — v3 Feature Tour
///
/// A concise walk through the v3 public contract. Each demo is short and
/// self-contained; run them all, or a single one by number:
///
///   dart run lib/main.dart        # run every demo
///   dart run lib/main.dart 5      # run only demo 5
///
/// See README.md for the full demo list and the APIs each one exercises.
///
/// Prerequisites:
///   Pass the key with --define=OPENAI_API_KEY=... or through
///   `make run-basic`. Demos that need it print a skip line and return
///   instead of crashing when it is absent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

void header(String title) {
  final bar = '─' * (title.length + 4);
  print('\n┌$bar┐');
  print('│  $title  │');
  print('└$bar┘');
}

/// Returns the OpenAI key, or prints a skip line and returns null.
String? requireOpenAiKey() {
  const key = String.fromEnvironment('OPENAI_API_KEY');
  if (key.isEmpty) {
    print(
      '  ⏭ skipped: pass --define=OPENAI_API_KEY=sk-... (or use make run-basic) to run this demo.',
    );
    return null;
  }
  return key;
}

// ─── 1. generateText — instructions + aggregate usage vs finalStep.usage ────

Future<void> demo1GenerateText() async {
  header('1 · generateText (instructions, aggregate usage)');
  if (requireOpenAiKey() == null) return;

  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    instructions: 'Answer in one short sentence.',
    prompt: 'Name three planets in our solar system.',
  );

  print('Text          : ${result.text}');
  print('Steps         : ${result.steps.length}');
  print('Usage (all)   : ${result.usage}');
  print('Usage (final) : ${result.finalStep.usage}');
}

// ─── 2. streamText — canonical event stream ──────────────────────────────────

Future<void> demo2StreamText() async {
  header('2 · streamText (canonical stream events)');
  if (requireOpenAiKey() == null) return;

  final result = await streamText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Count from 1 to 5, one number per line.',
  );

  // `stream` is the exhaustive canonical event stream; switch over the
  // event types you care about. `providerStream` exposes raw provider parts
  // for adapters/diagnostics — most apps only need `stream`.
  await for (final event in result.stream) {
    switch (event) {
      case StreamTextTextDeltaEvent(:final delta):
        stdout.write(delta);
      case StreamTextFinishEvent<Object?>(:final finishReason):
        print('\n[finished: $finishReason]');
      case _:
        break;
    }
  }
}

// ─── 3. Canonical lifecycle callbacks ───────────────────────────────────────

Future<void> demo3LifecycleCallbacks() async {
  header('3 · Lifecycle callbacks (onStart…onEnd, tool execution)');
  if (requireOpenAiKey() == null) return;

  Map<String, String> fakeWeather(String city) => switch (city.toLowerCase()) {
    'london' => {'condition': 'Rainy', 'tempC': '12'},
    'tokyo' => {'condition': 'Sunny', 'tempC': '22'},
    _ => {'condition': 'Unknown', 'tempC': '?'},
  };

  await generateText(
    model: openai('gpt-4.1-mini'),
    instructions: 'Use the weather tool for every city mentioned.',
    prompt: 'What is the weather in London and Tokyo?',
    maxSteps: 4,
    tools: {
      'getWeather': tool<Map<String, dynamic>, String>(
        description: 'Get current weather for a city.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          },
          fromJson: (json) => json,
        ),
        execute: (input, _) async {
          final w = fakeWeather(input['city'] as String);
          return '${w['condition']}, ${w['tempC']}°C';
        },
      ),
    },
    onStart: (_) => print('  onStart'),
    onStepStart: (event) => print('  onStepStart  step=${event.stepNumber}'),
    onToolExecutionStart: (event) =>
        print('  onToolExecutionStart  ${event.toolCall.toolName}'),
    onToolExecutionEnd: (event) => print(
      '  onToolExecutionEnd    ${event.toolCall.toolName} '
      '(${event.durationMs}ms, success=${event.success})',
    ),
    onStepEnd: (event) => print('  onStepEnd    step=${event.stepNumber}'),
    onEnd: (event) => print('  onEnd        text=${event.text}'),
  );
}

// ─── 4. Multi-turn history ───────────────────────────────────────────────────

Future<void> demo4MultiTurnHistory() async {
  header('4 · Multi-turn history (responseMessages -> ModelMessage)');
  if (requireOpenAiKey() == null) return;

  final model = openai('gpt-4.1-mini');
  final history = [
    const ModelMessage(role: ModelMessageRole.user, content: 'My name is Ada.'),
  ];

  final first = await generateText(model: model, messages: history);
  print('Turn 1 : ${first.text}');

  // Append only the newly generated messages — `responseMessages` no longer
  // echoes the supplied history back.
  history.addAll(first.responseMessages.map(ModelMessage.fromProvider));
  history.add(
    const ModelMessage(
      role: ModelMessageRole.user,
      content: 'What is my name?',
    ),
  );

  final second = await generateText(model: model, messages: history);
  print('Turn 2 : ${second.text}');
}

// ─── 5. Tools v3 — context, concurrency, approval ────────────────────────────

Future<void> demo5ToolsV3() async {
  header('5 · Tools v3 (toolWithContext, concurrency, approval)');
  if (requireOpenAiKey() == null) return;

  // Typed application context stays out of provider messages/persistence.
  final lookup = toolWithContext<Map<String, dynamic>, String, String>(
    description: 'Reads a tenant-scoped record.',
    context: 'tenant-42',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'key': {'type': 'string'},
        },
        'required': ['key'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, tenant, _) async => '$tenant:${input['key']}',
  );

  final agent = ToolLoopAgent(
    model: openai('gpt-4.1-mini'),
    tools: {'lookup': lookup},
    maxSteps: 3,
    maxToolConcurrency: 2,
    approvalPolicy: ToolApprovalPolicy.always,
  );
  const userTurn = ModelMessage(
    role: ModelMessageRole.user,
    content: 'Look up the record for key "quota".',
  );
  final pending = await agent.generate(messages: [userTurn]);
  if (pending.toolApprovalRequests.isEmpty) {
    print('No approval requested (model may not have called the tool).');
    return;
  }
  for (final request in pending.toolApprovalRequests) {
    print(
      'Pending approval for ${request.toolCall.toolName}'
      '(${request.toolCall.input})',
    );
  }

  // Persist the paused turn without the client-only approval request parts.
  final replay = ToolApprovalReplay(
    messages: [
      for (final step in pending.steps) ...[
        ModelMessage.parts(
          role: ModelMessageRole.assistant,
          parts: [
            for (final part in step.content)
              if (part is! LanguageModelV4ToolApprovalRequestPart) part,
          ],
        ),
        if (step.toolResults.isNotEmpty)
          ModelMessage.parts(
            role: ModelMessageRole.tool,
            parts: step.toolResults,
          ),
      ],
    ],
    requests: pending.toolApprovalRequests,
  );

  // Each response binds to the exact call ID, arguments and policy revision;
  // a changed call keeps the approval pending instead of executing it.
  final resumed = await agent.resume(
    replay: replay,
    messages: [userTurn],
    toolApprovalResponses: [
      for (final request in replay.requests)
        LanguageModelV4ToolApprovalResponse(
          approvalId: request.approvalId,
          approved: true,
          toolCallId: request.toolCall.toolCallId,
          toolName: request.toolCall.toolName,
          argumentsFingerprint: request.argumentsFingerprint,
          policyRevision: request.policyRevision,
        ),
    ],
  );
  print('Resumed : ${await resumed.text}');
}

// ─── 6. Cancellation and deadlines ───────────────────────────────────────────

Future<void> demo6CancellationAndDeadlines() async {
  header('6 · Cancellation and deadlines');
  if (requireOpenAiKey() == null) return;

  final token = CancellationToken();
  final streamFuture = streamText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Write a long paragraph about the ocean.',
    abortSignal: token,
  );
  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 50), token.cancel),
  );
  try {
    final result = await streamFuture;
    await result.text;
  } on AiOperationCancelledError {
    print('Stream cancelled mid-flight, as expected.');
  }

  try {
    await generateText(
      model: openai('gpt-4.1-mini'),
      prompt: 'Say hello.',
      timeout: const TimeoutConfiguration(total: Duration(seconds: 30)),
    );
  } on TimeoutException {
    print('Deadline exceeded.');
  }
}

// ─── 7. Structured output — decoderOnly vs validatedJsonSchema ──────────────

Future<void> demo7StructuredOutput() async {
  header('7 · Structured output (Schema.decoderOnly vs validatedJsonSchema)');

  const jsonSchema = {
    'type': 'object',
    'properties': {
      'capital': {'type': 'string'},
      'population': {'type': 'number'},
    },
    'required': ['capital', 'population'],
  };

  // No runtime validation: the decoder alone determines acceptance.
  final decoderOnly = Schema<Map<String, dynamic>>.decoderOnly(
    jsonSchema: jsonSchema,
    fromJson: (json) => json,
  );

  // Validates against the JSON Schema before the decoder ever runs.
  final validated = validatedJsonSchema<Map<String, dynamic>>(
    schema: jsonSchema,
    fromJson: (json) => json,
  );

  const malformed = {'capital': 42};
  print('decoderOnly accepted: ${decoderOnly.fromJson(malformed)}');
  try {
    validated.fromJson(malformed);
  } on SchemaValidationException catch (e) {
    print('validatedJsonSchema rejected: $e');
  }

  if (requireOpenAiKey() == null) return;

  final result = await generateText<Map<String, dynamic>>(
    model: openai('gpt-4.1-mini'),
    prompt: 'Capital and approximate population of France?',
    output: Output.object(schema: validated),
  );
  print('Validated object : ${result.output}');
}

// ─── 8. streamObject — partial snapshots + patchStream ──────────────────────

Future<void> demo8StreamObject() async {
  header('8 · streamObject (partial snapshots + patchStream)');
  if (requireOpenAiKey() == null) return;

  final schema = validatedJsonSchema<Map<String, dynamic>>(
    schema: const {
      'type': 'object',
      'properties': {
        'title': {'type': 'string'},
        'steps': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'required': ['title', 'steps'],
    },
    fromJson: (json) => json,
  );

  final result = await streamObject(
    model: openai('gpt-4.1-mini'),
    schema: schema,
    prompt: 'Give me a 3-step recipe title and steps for toast.',
  );

  // Snapshots are immutable JSON maps and may be incomplete — do not treat
  // them as a finished domain object. `patchStream` and `partialObjectStream`
  // are companion broadcast streams from the same pass, so subscribe to both
  // before awaiting either — draining one to completion first would miss
  // events already emitted on the other.
  final partials = result.partialObjectStream.listen(
    (partial) => print('  partial: $partial'),
    onError: (Object _) {},
  );
  final patches = result.patchStream.listen(
    (patch) =>
        print('  patch  : ${patch.map((p) => '${p.op} ${p.path}').join(', ')}'),
    onError: (Object _) {},
  );
  try {
    final object = await result.object;
    print('Final validated object: $object');
  } finally {
    await partials.cancel();
    await patches.cancel();
  }
}

// ─── 9. embedMany — batching and parallelism ─────────────────────────────────

Future<void> demo9EmbedMany() async {
  header('9 · embedMany (maxEmbeddingsPerCall, maxParallelCalls)');
  if (requireOpenAiKey() == null) return;

  final values = [
    'a cat sitting on a mat',
    'a dog running in a park',
    'a cat playing with yarn',
  ];
  final result = await embedMany(
    model: openai.embedding('text-embedding-3-small'),
    values: values,
    maxEmbeddingsPerCall: 2,
    maxParallelCalls: 2,
  );

  // Order is preserved even though requests may complete out of order.
  for (var i = 0; i < result.embeddings.length; i++) {
    if (result.embeddings[i].value != values[i]) {
      throw StateError('embedMany did not preserve input order');
    }
  }
  final cat = result.embeddings[0].embedding;
  final catFriend = result.embeddings[2].embedding;
  print(
    'cat ↔ cat-friend similarity: '
    '${cosineSimilarity(cat, catFriend).toStringAsFixed(4)}',
  );
  print('Usage: ${result.usage}');
}

// ─── 10. OpenAI Responses API + hosted web search ────────────────────────────

Future<void> demo10ResponsesApiWebSearch() async {
  header('10 · OpenAI Responses API (hosted web search)');
  if (requireOpenAiKey() == null) return;

  final result = await generateText(
    model: openai.responses('gpt-4.1-mini'),
    prompt: 'What is the latest stable Dart SDK version? Cite your sources.',
    providerDefinedTools: [OpenAIWebSearchTool()],
  );
  print('Text    : ${result.text}');
  for (final source in result.sources) {
    print('Source  : ${source.title ?? source.url} (${source.url})');
  }
}

// ─── 11. Reasoning ────────────────────────────────────────────────────────────

Future<void> demo11Reasoning() async {
  header('11 · Reasoning (final-step output)');
  if (requireOpenAiKey() == null) return;

  final result = await generateText(
    model: openai('o4-mini'),
    prompt: 'Solve: a train travels 60km in 45 minutes. What is its speed?',
    reasoning: LanguageModelV4Reasoning.medium,
    maxSteps: 2,
  );
  print('Answer               : ${result.text}');
  print('Final-step reasoning : ${result.reasoning.length} part(s)');
}

// ─── 12. Body inclusion policy ────────────────────────────────────────────────

Future<void> demo12BodyInclusion() async {
  header('12 · Body inclusion (opt-in only)');
  if (requireOpenAiKey() == null) return;

  final model = openai('gpt-4.1-mini');
  final omitted = await generateText(model: model, prompt: 'Say hi.');
  print('Default request body : ${omitted.request.body}');

  final included = await generateText(
    model: model,
    prompt: 'Say hi.',
    bodyInclusion: const BodyInclusionPolicy.all(),
  );
  print('Opted-in request body present: ${included.request.body != null}');
}

// ─── 13. Conversation persistence ────────────────────────────────────────────

Future<void> demo13ConversationPersistence() async {
  header('13 · Conversation persistence (ConversationCodec)');
  if (requireOpenAiKey() == null) return;

  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Say hello in five words or fewer.',
  );

  final conversation = Conversation(
    id: 'demo-conversation',
    messages: [
      ConversationMessage(
        id: 'message-user',
        role: ConversationRole.user,
        parts: [
          TextPart(id: 'part-user', text: 'Say hello in five words or fewer.'),
        ],
      ),
      ConversationMessage(
        id: 'message-assistant',
        role: ConversationRole.assistant,
        parts: [TextPart(id: 'part-assistant', text: result.text)],
      ),
    ],
  );

  final wire = jsonEncode(ConversationCodec.encode(conversation));
  final restored = ConversationCodec.decode(
    jsonDecode(wire) as Map<String, dynamic>,
  );
  print('Round-tripped: ${restored == conversation}');
  print('Wire bytes   : ${wire.length}');
}

// ─── 14. Middleware ───────────────────────────────────────────────────────────

Future<void> demo14Middleware() async {
  header('14 · Middleware (defaultSettings + extractReasoning)');
  if (requireOpenAiKey() == null) return;

  final model = wrapLanguageModel(
    model: openai('gpt-4.1-mini'),
    middleware: [
      defaultSettingsMiddleware(temperature: 0.2),
      extractReasoningMiddleware(tagName: 'think'),
    ],
  );

  final result = await generateText(
    model: model,
    instructions: 'Show your work briefly, then give the final answer.',
    prompt: 'What is 17 × 23?',
  );
  print('Text      : ${result.text}');
  if (result.reasoning.isNotEmpty) {
    print('Reasoning : ${result.reasoningText}');
  }
}

// ─── 15. Provider registry ───────────────────────────────────────────────────

Future<void> demo15Registry() async {
  header('15 · Provider registry');
  if (requireOpenAiKey() == null) return;

  final registry = createProviderRegistry({
    'openai': RegistrableProvider(
      languageModelFactory: openai.call,
      embeddingModelFactory: openai.embedding,
    ),
  });

  final result = await generateText(
    model: registry.languageModel('openai:gpt-4.1-mini'),
    prompt: 'Say "registry works!" in exactly three words.',
  );
  print('Response : ${result.text}');
}

// ─── entry point ────────────────────────────────────────────────────────────

final _demos = <int, (String, Future<void> Function())>{
  1: ('generateText', demo1GenerateText),
  2: ('streamText', demo2StreamText),
  3: ('Lifecycle callbacks', demo3LifecycleCallbacks),
  4: ('Multi-turn history', demo4MultiTurnHistory),
  5: ('Tools v3', demo5ToolsV3),
  6: ('Cancellation and deadlines', demo6CancellationAndDeadlines),
  7: ('Structured output', demo7StructuredOutput),
  8: ('streamObject', demo8StreamObject),
  9: ('embedMany', demo9EmbedMany),
  10: ('OpenAI Responses API', demo10ResponsesApiWebSearch),
  11: ('Reasoning', demo11Reasoning),
  12: ('Body inclusion', demo12BodyInclusion),
  13: ('Conversation persistence', demo13ConversationPersistence),
  14: ('Middleware', demo14Middleware),
  15: ('Provider registry', demo15Registry),
};

Future<void> main(List<String> args) async {
  final selected = args.isEmpty ? null : int.tryParse(args.first);
  if (args.isNotEmpty && selected == null) {
    print('Usage: dart run lib/main.dart [demo-number]');
    exit(64);
  }

  final toRun = selected == null ? _demos.keys.toList() : [selected];
  try {
    for (final number in toRun) {
      final entry = _demos[number];
      if (entry == null) {
        print('No such demo: $number (valid: 1-${_demos.length})');
        exit(64);
      }
      try {
        await entry.$2();
      } on AiApiCallError catch (e) {
        print('\nAPI error in demo $number: ${e.message}');
      }
    }
  } finally {
    openai.dispose();
  }

  print('\nAll requested demos complete.');
}
