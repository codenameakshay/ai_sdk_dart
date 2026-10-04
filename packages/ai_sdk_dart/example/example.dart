// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// The v3 public-contract showcase for `ai_sdk_dart`.
///
/// Runs real requests against OpenAI, so it needs a key:
///
/// ```sh
/// dart run --define=OPENAI_API_KEY=sk-... example/example.dart
/// ```
///
/// For a keyless, offline walk-through of the same contracts (canonical
/// stream/callbacks, `toolWithContext` + approval, body inclusion, provider
/// file references), see `example/migration/v3_contracts.dart` and
/// `example/migration/v3_generation.dart`, which run as part of the test
/// suite without any network access.
Future<void> main() async {
  final apiKey = const String.fromEnvironment('OPENAI_API_KEY');
  if (apiKey.isEmpty) {
    throw StateError(
      'Pass a key with --define=OPENAI_API_KEY=sk-... to run this example.',
    );
  }
  await runExamples(OpenAIProvider(apiKey: apiKey));
}

Future<void> runExamples(OpenAIProvider provider) async {
  try {
    final model = provider('gpt-4.1-mini');
    await _instructionsAndUsage(model);
    await _streamingCanonicalEvents(model);
    await _canonicalCallbacksAndAggregate(model);
    await _responseMessagesReuse(model);
    await _toolWithContextAndApproval(model);
    await _maxToolConcurrency(model);
    await _cancellationAndTimeout(model);
    await _bodyInclusionPolicy(model);
  } finally {
    provider.dispose();
  }
}

// ---------------------------------------------------------------------------
// 1. `instructions` — the canonical top-level instruction
// ---------------------------------------------------------------------------

Future<void> _instructionsAndUsage(LanguageModelV4 model) async {
  print('── instructions ──────────────────────────────────────────');

  final result = await generateText(
    model: model,
    instructions: 'Reply in exactly one short sentence.',
    prompt: 'Why is the sky blue?',
  );

  print('text : ${result.text}');
  print('usage: ${result.usage}');
  print('');
}

// ---------------------------------------------------------------------------
// 2. `result.stream` — the exhaustive canonical event stream
// ---------------------------------------------------------------------------

Future<void> _streamingCanonicalEvents(LanguageModelV4 model) async {
  print('── result.stream ─────────────────────────────────────────');

  final result = await streamText(
    model: model,
    prompt: 'Count from one to three.',
  );

  stdout.write('text: ');
  await for (final event in result.stream) {
    switch (event) {
      case StreamTextTextDeltaEvent(:final delta):
        stdout.write(delta);
      case StreamTextFinishEvent(:final finishReason):
        print('\nfinishReason: $finishReason');
      default:
        break;
    }
  }
  print('');
}

// ---------------------------------------------------------------------------
// 3. Canonical lifecycle callbacks + aggregate usage / finalStep
// ---------------------------------------------------------------------------

Future<void> _canonicalCallbacksAndAggregate(LanguageModelV4 model) async {
  print('── canonical callbacks + aggregate/finalStep ────────────────');

  final result = await generateText(
    model: model,
    instructions: 'Use the calculator tool for any arithmetic.',
    prompt: 'What is 21 plus 21, then double that result?',
    maxSteps: 4,
    tools: {
      'calculate': tool<Map<String, dynamic>, num>(
        description: 'Evaluate a simple two-operand arithmetic expression.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'a': {'type': 'number'},
              'op': {
                'type': 'string',
                'enum': ['add', 'multiply'],
              },
              'b': {'type': 'number'},
            },
            'required': ['a', 'op', 'b'],
          },
          fromJson: (json) => json,
        ),
        execute: (input, _) async {
          final a = (input['a'] as num).toDouble();
          final b = (input['b'] as num).toDouble();
          return input['op'] == 'add' ? a + b : a * b;
        },
      ),
    },
    onStart: (event) => print('start: ${event.model.modelId}'),
    onStepStart: (event) => print('stepStart: #${event.stepNumber}'),
    onToolExecutionStart: (event) =>
        print('toolStart: ${event.toolCall.toolName}'),
    onToolExecutionEnd: (event) =>
        print('toolEnd: ${event.toolCall.toolName} -> ${event.output}'),
    onStepEnd: (event) => print('stepEnd: #${event.stepNumber}'),
    onEnd: (event) => print('end: ${event.finishReason}'),
  );

  // `usage`/`content`/`toolCalls` aggregate every step; `text` and
  // `finalStep` describe only the last step.
  print('aggregate usage : ${result.usage}');
  print('final-step usage: ${result.finalStep.usage}');
  print('final text      : ${result.text}');
  print('');
}

// ---------------------------------------------------------------------------
// 4. Reusing `responseMessages` as history for a follow-up call
// ---------------------------------------------------------------------------

Future<void> _responseMessagesReuse(LanguageModelV4 model) async {
  print('── responseMessages reuse ────────────────────────────────');

  final first = await generateText(
    model: model,
    prompt: 'My favorite color is teal. Remember that.',
  );

  final history = [
    const ModelMessage(
      role: ModelMessageRole.user,
      content: 'My favorite color is teal. Remember that.',
    ),
    // `responseMessages` holds only the turns generated by this call —
    // append once to the caller's own history.
    ...first.responseMessages.map(ModelMessage.fromProvider),
    const ModelMessage(
      role: ModelMessageRole.user,
      content: 'What is my favorite color?',
    ),
  ];

  final second = await generateText(model: model, messages: history);
  print('follow-up: ${second.text}');
  print('');
}

// ---------------------------------------------------------------------------
// 5. `toolWithContext` + `approvalPolicy`
// ---------------------------------------------------------------------------

Future<void> _toolWithContextAndApproval(LanguageModelV4 model) async {
  print('── toolWithContext + approvalPolicy ──────────────────────');

  final deleteNote = toolWithContext<Map<String, dynamic>, String, String>(
    description: 'Delete a note by title for the current tenant.',
    context: 'tenant-42',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
      },
      fromJson: (json) => json,
    ),
    execute: (input, tenant, _) async =>
        'Deleted "${input['title']}" for $tenant',
  );

  final agent = ToolLoopAgent(
    model: model,
    tools: {'deleteNote': deleteNote},
    maxSteps: 2,
    approvalPolicy: ToolApprovalPolicy.always,
  );
  const userTurn = ModelMessage(
    role: ModelMessageRole.user,
    content: 'Delete the note titled "old todo".',
  );
  final result = await agent.generate(messages: [userTurn]);

  if (result.toolApprovalRequests.isEmpty) {
    // The model chose not to call the tool this time.
    print('no approval requested: ${result.text}');
    print('');
    return;
  }

  // An approval request is not an executed result. Persist the paused turn
  // without the client-only approval request parts, then resume it.
  final replay = ToolApprovalReplay(
    messages: [
      for (final step in result.steps) ...[
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
    requests: result.toolApprovalRequests,
  );

  // Each response binds to the exact call ID, arguments and policy revision.
  final approved = await agent.resume(
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
  print('after approval: ${await approved.text}');
  print('');
}

// ---------------------------------------------------------------------------
// 6. `maxToolConcurrency`
// ---------------------------------------------------------------------------

Future<void> _maxToolConcurrency(LanguageModelV4 model) async {
  print('── maxToolConcurrency ────────────────────────────────────');

  Tool<Map<String, dynamic>, String> weatherTool(String label) =>
      tool<Map<String, dynamic>, String>(
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
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return '$label: sunny in ${input['city']}';
        },
      );

  final result = await generateText(
    model: model,
    instructions:
        'Call getWeatherA and getWeatherB in the same step, each once.',
    prompt: 'What is the weather in Paris and in Tokyo?',
    maxSteps: 3,
    // Admits up to two tool calls from the same step at once, instead of
    // the default serial (1-at-a-time) execution.
    maxToolConcurrency: 2,
    tools: {'getWeatherA': weatherTool('A'), 'getWeatherB': weatherTool('B')},
  );
  print('text: ${result.text}');
  print('');
}

// ---------------------------------------------------------------------------
// 7. `CancellationToken` + `TimeoutConfiguration`
// ---------------------------------------------------------------------------

Future<void> _cancellationAndTimeout(LanguageModelV4 model) async {
  print('── CancellationToken + TimeoutConfiguration ──────────────');

  final cancellation = CancellationToken();
  Timer(const Duration(milliseconds: 1), cancellation.cancel);
  try {
    await generateText(
      model: model,
      prompt: 'Write a long story about a dragon.',
      abortSignal: cancellation,
    );
  } on AiOperationCancelledError {
    print('cancelled before the model responded, as expected');
  }

  try {
    await generateText(
      model: model,
      prompt: 'Write a long story about a dragon.',
      timeout: const TimeoutConfiguration(total: Duration(milliseconds: 1)),
    );
  } on TimeoutException {
    print('total deadline elapsed before completion, as expected');
  }
  print('');
}

// ---------------------------------------------------------------------------
// 8. `BodyInclusionPolicy`
// ---------------------------------------------------------------------------

Future<void> _bodyInclusionPolicy(LanguageModelV4 model) async {
  print('── BodyInclusionPolicy ───────────────────────────────────');

  // Default: request/response bodies and raw chunks are omitted.
  final lean = await generateText(model: model, prompt: 'Say hi.');
  print('default responseInfo.body: ${lean.responseInfo.body}');

  // Explicit opt-in retains the raw provider payloads on the result.
  final full = await generateText(
    model: model,
    prompt: 'Say hi.',
    bodyInclusion: const BodyInclusionPolicy.all(),
  );
  print(
    'opted-in responseInfo.body != null: ${full.responseInfo.body != null}',
  );
  print('');
}
