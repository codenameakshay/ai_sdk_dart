import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A no-network example of the v3 public contract and migration aliases.
Future<void> main() async {
  final model = MockLanguageModelV4(response: [mockText('READY')]);

  final streamed = await streamText(
    model: model,
    prompt: 'Say READY.',
    bodyInclusion: const BodyInclusionPolicy.all(),
  );
  if (!identical(streamed.stream, streamed.fullStream)) {
    throw StateError('fullStream must alias the canonical stream');
  }
  await streamed.text;
  final providerEvents = streamed.providerStream;
  providerEvents.listen((_) {});

  final tenantTool = toolWithContext<Map<String, dynamic>, String, String>(
    context: 'tenant-1',
    description: 'Reads a tenant-scoped value.',
    inputSchema: Schema<Map<String, dynamic>>(
      jsonSchema: const {'type': 'object'},
      fromJson: (json) => json,
    ),
    execute: (input, tenant, _) async => '$tenant:${input['value']}',
  );
  final approved = await generateText(
    model: model,
    prompt: 'Use the tenant tool.',
    tools: {'tenant': tenantTool},
    approvalPolicy: ToolApprovalPolicy.always,
    runtimeContext: const {'requestId': 'request-1'},
    bodyInclusion: const BodyInclusionPolicy.none(),
  );

  const providerFile = LanguageModelV4FilePart(
    data: DataContentProviderReference(namespace: 'openai', id: 'file-1'),
    mediaType: 'application/pdf',
    filename: 'contract.pdf',
  );
  if (providerFile.data case DataContentProviderReference(:final namespace)) {
    if (namespace != 'openai') {
      throw StateError('provider file references must retain their namespace');
    }
  } else {
    throw StateError('provider file references must retain their type');
  }
  if (approved.text != 'READY') {
    throw StateError('contract example did not complete');
  }

  final finalStep = approved.finalStep;
  final aggregateReasoning = approved.reasoning;
  if (finalStep.text != approved.text ||
      aggregateReasoning.any((part) => part.text.isEmpty)) {
    throw StateError('final-step contract example did not complete');
  }
}
