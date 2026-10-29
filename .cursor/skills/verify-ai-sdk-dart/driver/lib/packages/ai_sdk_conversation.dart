// Verification checks for package:ai_sdk_conversation.
// See features/ai_sdk_conversation.md.
//
// The package is a pure persistence model: it has no network and no tool
// execution. The checks drive the public codec the way an app does (build a
// snapshot, store the JSON string, read it back) and one check drives a real
// generateText turn through a fixture server to show the snapshot fits the
// SDK's tool approval flow.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart' as sdk;
import 'package:ai_sdk_provider/ai_sdk_provider.dart' as provider;
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_conversation';

/// Stores [conversation] the way an app does: encode, stringify, parse, decode.
Conversation _persist(Conversation conversation) {
  final stored = jsonEncode(ConversationCodec.encode(conversation));
  return ConversationCodec.decode(jsonDecode(stored) as Map<String, dynamic>);
}

Conversation _fullConversation() => Conversation(
  id: 'conversation-1',
  metadata: {
    'title': 'Everything',
    'tags': ['a', 'b'],
  },
  extra: {'x-app-field': 'kept'},
  messages: [
    ConversationMessage(
      id: 'm-user',
      role: ConversationRole.user,
      parts: [TextPart(id: 'p-user-text', text: 'Delete /tmp/x and cite docs')],
    ),
    ConversationMessage(
      id: 'm-assistant',
      role: ConversationRole.assistant,
      status: ConversationMessageStatus.interrupted,
      metadata: {'model': 'verify'},
      extra: {'x-message-field': 7},
      parts: [
        ReasoningPart(
          id: 'p-reasoning',
          text: 'Thinking.',
          signature: 'sig-opaque-1',
        ),
        RedactedReasoningPart(
          id: 'p-redacted',
          data: Uint8List.fromList([1, 2, 3, 250]),
        ),
        TextPart(
          id: 'p-text',
          text: 'Partial answer',
          providerOptions: {
            'openai': {'itemId': 'msg_1'},
          },
        ),
        SourcePart(
          id: 'p-source',
          uri: 'https://example.test/doc',
          sourceId: 'src-1',
          title: 'Doc',
        ),
        DocumentSourcePart(
          id: 'p-docsource',
          mediaType: 'application/pdf',
          title: 'Spec',
          name: 'spec.pdf',
        ),
        ImagePart(
          id: 'p-image',
          mimeType: 'image/png',
          data: ConversationFileBytes(Uint8List.fromList([137, 80, 78, 71])),
        ),
        FilePart(
          id: 'p-file-uri',
          uri: 'https://example.test/report.pdf',
          mimeType: 'application/pdf',
          name: 'report.pdf',
        ),
        FilePart(
          id: 'p-file-ref',
          mimeType: 'application/pdf',
          data: ConversationFileProviderReference(
            namespace: 'openai',
            id: 'file-abc',
          ),
        ),
        ReasoningFilePart(
          id: 'p-reasoning-file',
          mimeType: 'text/plain',
          uri: 'https://example.test/trace.txt',
        ),
        ToolCallPart(
          id: 'p-call',
          callId: 'call-1',
          name: 'delete',
          arguments: {'path': '/tmp/x', 'force': false, 'n': 1.5},
        ),
        ApprovalPart(
          id: 'p-approval',
          callId: 'call-1',
          status: ApprovalStatus.approved,
          approvalId: 'approval-1',
          toolName: 'delete',
          argumentsFingerprint: 'fp-1',
          policyVersion: 'v1',
        ),
        ToolResultPart(
          id: 'p-result',
          callId: 'call-1',
          output: {
            'ok': true,
            'items': [1, 2, null],
          },
          toolName: 'delete',
          outputKind: 'json',
        ),
        UnknownPart(
          id: 'p-unknown',
          type: 'vendor_widget',
          raw: {
            'id': 'p-unknown',
            'type': 'vendor_widget',
            'payload': {'a': 1},
          },
        ),
      ],
    ),
  ],
);

/// JSON text with object keys sorted, so key order does not matter.
String _canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: _sorted(value[key]),
  },
  List() => [for (final item in value) _sorted(item)],
  _ => value,
};

Object _throwsValidation(void Function() body) {
  try {
    body();
  } on ConversationValidationException catch (error) {
    return error;
  } on ConversationSchemaException catch (error) {
    return error;
  }
  throw CheckFailure('expected a conversation exception, nothing was thrown');
}

final checks = PackageChecks(_package, [
  Check(
    id: 'roundtrip-all-parts',
    feature: 'conv-roundtrip',
    description:
        'A snapshot with every part type survives encode, JSON text, decode '
        'and re-encode with equal value and identical JSON.',
    run: (ctx) async {
      final original = _fullConversation();
      final wire = ConversationCodec.encode(original);
      final text = jsonEncode(wire);
      final restored = ConversationCodec.decode(
        jsonDecode(text) as Map<String, dynamic>,
      );
      ctx.observe('schemaVersion', wire['schemaVersion']);
      ctx.observe('partTypes', [
        for (final part in restored.messages.last.parts) part.type,
      ]);
      ctx.observe('wireBytes', utf8.encode(text).length);
      ctx.expectEquals(wire['schemaVersion'], 1, 'schema version on the wire');
      ctx.expect(restored == original, 'decoded snapshot is not equal');
      ctx.expectEquals(
        jsonEncode(ConversationCodec.encode(restored)),
        text,
        're-encoded JSON',
      );
      ctx.expectEquals(restored.id, 'conversation-1', 'conversation id');
      ctx.expectEquals(restored.messages.length, 2, 'message count');
      ctx.expectEquals(
        restored.messages.last.parts.map((p) => p.runtimeType.toString()),
        [
          'ReasoningPart',
          'RedactedReasoningPart',
          'TextPart',
          'SourcePart',
          'DocumentSourcePart',
          'ImagePart',
          'FilePart',
          'FilePart',
          'ReasoningFilePart',
          'ToolCallPart',
          'ApprovalPart',
          'ToolResultPart',
          'UnknownPart',
        ],
        'decoded part classes in order',
      );
      final reasoning = restored.messages.last.parts.first as ReasoningPart;
      ctx.expectEquals(
        reasoning.signature,
        'sig-opaque-1',
        'opaque reasoning signature',
      );
      final call = restored.messages.last.parts
          .whereType<ToolCallPart>()
          .single;
      ctx.expectEquals(call.arguments, {
        'path': '/tmp/x',
        'force': false,
        'n': 1.5,
      }, 'tool call arguments');
      final result = restored.messages.last.parts
          .whereType<ToolResultPart>()
          .single;
      ctx.expectEquals(result.callId, 'call-1', 'tool result call id');
      ctx.expectEquals(result.output, {
        'ok': true,
        'items': [1, 2, null],
      }, 'tool result output');
    },
  ),
  Check(
    id: 'file-data-forms',
    feature: 'conv-files',
    description:
        'File and image bytes are stored inline as base64 and restore '
        'byte-for-byte; URI and provider-reference files round trip; a part '
        'with both a URI and data is rejected.',
    run: (ctx) async {
      final bytes = Uint8List.fromList(List.generate(64, (i) => (i * 7) % 256));
      final conversation = Conversation(
        id: 'files',
        messages: [
          ConversationMessage(
            id: 'm1',
            role: ConversationRole.user,
            parts: [
              FilePart(
                id: 'f-bytes',
                mimeType: 'application/octet-stream',
                data: ConversationFileBytes(bytes),
              ),
              ImagePart(
                id: 'f-image',
                mimeType: 'image/png',
                data: ConversationFileBytes(bytes),
              ),
              FilePart(
                id: 'f-ref',
                mimeType: 'application/pdf',
                data: ConversationFileProviderReference(
                  namespace: 'google',
                  id: 'files/abc',
                ),
              ),
              FilePart(
                id: 'f-uri',
                mimeType: 'image/jpeg',
                uri: 'https://example.test/a.jpg',
              ),
            ],
          ),
        ],
      );
      final wire = ConversationCodec.encode(conversation);
      final wireParts =
          ((wire['messages'] as List).single as Map)['parts'] as List;
      final byteWire = (wireParts.first as Map)['data'] as Map;
      ctx.observe('bytesWire', byteWire);
      ctx.expectEquals(byteWire['kind'], 'bytes', 'bytes data kind');
      ctx.expectEquals(
        byteWire['base64'],
        base64Encode(bytes),
        'inline base64',
      );
      ctx.expectEquals(
        ((wireParts[2] as Map)['data'] as Map)['kind'],
        'provider_reference',
        'reference data kind',
      );
      final restored = _persist(conversation);
      final restoredParts = restored.messages.single.parts;
      final file = restoredParts[0] as FilePart;
      final image = restoredParts[1] as ImagePart;
      ctx.expectEquals(
        (file.data as ConversationFileBytes).bytes,
        bytes,
        'file bytes after round trip',
      );
      ctx.expectEquals(
        (image.data as ConversationFileBytes).bytes,
        bytes,
        'image bytes after round trip',
      );
      final reference =
          (restoredParts[2] as FilePart).data
              as ConversationFileProviderReference;
      ctx.expectEquals(reference.namespace, 'google', 'reference namespace');
      ctx.expectEquals(reference.id, 'files/abc', 'reference id');
      ctx.expectEquals(
        (restoredParts[3] as FilePart).uri,
        'https://example.test/a.jpg',
        'file uri',
      );
      final both = _throwsValidation(
        () => FilePart(
          id: 'bad',
          mimeType: 'text/plain',
          uri: 'https://example.test/a',
          data: ConversationFileBytes(Uint8List(1)),
        ),
      );
      ctx.observe('uriAndDataError', '$both');
      final badBase64 = _throwsValidation(
        () => ConversationCodec.decode({
          'schemaVersion': 1,
          'id': 'c',
          'messages': [
            {
              'id': 'm',
              'role': 'user',
              'status': 'complete',
              'parts': [
                {
                  'id': 'p',
                  'type': 'file',
                  'mimeType': 'text/plain',
                  'data': {'kind': 'bytes', 'base64': '***not base64***'},
                },
              ],
            },
          ],
        }),
      );
      ctx.observe('badBase64Error', '$badBase64');
      ctx.expect(
        '$badBase64'.contains('invalid base64'),
        'bad base64 error text: $badBase64',
      );
    },
  ),
  Check(
    id: 'schema-version',
    feature: 'conv-version',
    description:
        'Schema version 1 decodes; any other, missing or non-integer version '
        'raises ConversationSchemaException and never a partial snapshot.',
    run: (ctx) async {
      final good = ConversationCodec.encode(
        Conversation(id: 'c', messages: const []),
      );
      ctx.expectEquals(good['schemaVersion'], conversationSchemaVersion, 'v');
      ctx.expectEquals(
        ConversationCodec.decode(good).schemaVersion,
        1,
        'decoded schema version',
      );
      for (final version in <Object?>[2, 0, '1', 1.5, null]) {
        final error = await ctx.expectThrows<ConversationSchemaException>(
          () async =>
              ConversationCodec.decode({...good, 'schemaVersion': version}),
          'version $version',
        );
        ctx.expect(
          error.toString().contains('Unsupported conversation schema version'),
          'unexpected message: $error',
        );
      }
      await ctx.expectThrows<ConversationSchemaException>(
        () async =>
            ConversationCodec.decode({'id': 'c', 'messages': <Object>[]}),
        'missing version',
      );
      await ctx.expectThrows<ConversationSchemaException>(
        () async => Conversation(id: 'c', messages: const [], schemaVersion: 2),
        'constructor with version 2',
      );
    },
  ),
  Check(
    id: 'reject-malformed',
    feature: 'conv-validation',
    description:
        'Duplicate ids, orphan tool results or approvals, empty ids, bad '
        'roles and statuses and non-object input raise '
        'ConversationValidationException with a specific message.',
    run: (ctx) async {
      Map<String, dynamic> wire(
        List<Object> parts, {
        String status = 'complete',
      }) => {
        'schemaVersion': 1,
        'id': 'c',
        'messages': [
          {'id': 'm', 'role': 'assistant', 'status': status, 'parts': parts},
        ],
      };
      Map<String, Object> text(String id) => {
        'id': id,
        'type': 'text',
        'text': 't',
      };
      Map<String, Object> call(String id, String callId) => {
        'id': id,
        'type': 'tool_call',
        'callId': callId,
        'name': 'n',
        'arguments': <String, Object>{},
      };
      final cases = <String, (Map<String, dynamic>, String)>{
        'duplicate part id': (
          wire([text('p'), text('p')]),
          'Duplicate message or part id "p"',
        ),
        'part id equals message id': (
          wire([text('m')]),
          'Duplicate message or part id "m"',
        ),
        'duplicate call id': (
          wire([call('a', 'x'), call('b', 'x')]),
          'Duplicate tool call id "x"',
        ),
        'orphan tool result': (
          wire([
            {
              'id': 'r',
              'type': 'tool_result',
              'callId': 'nope',
              'output': 1,
              'isError': false,
            },
          ]),
          'unknown call id "nope"',
        ),
        'orphan approval': (
          wire([
            {
              'id': 'a',
              'type': 'approval',
              'callId': 'nope',
              'status': 'pending',
            },
          ]),
          'unknown call id "nope"',
        ),
        'pending_approval without a pending approval': (
          wire([text('p')], status: 'pending_approval'),
          'pendingApproval messages require a pending approval part',
        ),
        'unknown status': (wire([text('p')], status: 'sleeping'), 'Invalid'),
        'empty part id': (wire([text(' ')]), 'part id must not be empty'),
        'tool result without isError': (
          wire([
            call('c1', 'x'),
            {'id': 'r', 'type': 'tool_result', 'callId': 'x', 'output': 1},
          ]),
          'isError must be boolean',
        ),
        'part not an object': (wire(['text']), 'Part must be an object'),
        'missing messages': (
          {'schemaVersion': 1, 'id': 'c'},
          'requires id and messages',
        ),
      };
      for (final entry in cases.entries) {
        final error = _throwsValidation(
          () => ConversationCodec.decode(entry.value.$1),
        );
        ctx.observe('${entry.key}.error', '$error');
        ctx.expect(
          error is ConversationValidationException,
          '${entry.key}: wrong class $error',
        );
        ctx.expect(
          '$error'.contains(entry.value.$2),
          '${entry.key}: expected "${entry.value.$2}" in "$error"',
        );
      }
      final emptyId = _throwsValidation(
        () => Conversation(id: '  ', messages: const []),
      );
      ctx.expect('$emptyId'.contains('conversation id'), 'empty id: $emptyId');
    },
  ),
  Check(
    id: 'json-bounds-immutability',
    feature: 'conv-json',
    description:
        'Retained JSON is copied into immutable containers and rejects '
        'cycles, non-finite numbers, non-JSON values, depth above 64 and more '
        'than 10,000 nodes.',
    run: (ctx) async {
      final source = <String, dynamic>{
        'a': [1, 2],
        'b': {'c': 'x'},
      };
      final part = ToolCallPart(
        id: 'p',
        callId: 'c',
        name: 'n',
        arguments: source,
      );
      (source['a'] as List).add(3);
      (source['b'] as Map)['c'] = 'changed';
      ctx.expectEquals(part.arguments, {
        'a': [1, 2],
        'b': {'c': 'x'},
      }, 'arguments are a copy');
      var immutableRejected = 0;
      for (final mutate in <void Function()>[
        () => part.arguments['z'] = 1,
        () => (part.arguments['a'] as List).add(9),
        () => (part.arguments['b'] as Map)['c'] = 'y',
      ]) {
        try {
          mutate();
        } on UnsupportedError {
          immutableRejected++;
        }
      }
      ctx.expectEquals(immutableRejected, 3, 'mutations rejected');

      Map<String, dynamic> deep(int levels) {
        Object value = 1;
        for (var i = 0; i < levels; i++) {
          value = {'n': value};
        }
        return {'root': value};
      }

      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      final bad = <String, (Object?, String)>{
        'cycle': (cyclic, 'Cyclic JSON value'),
        'NaN': ({'v': double.nan}, 'finite'),
        'infinity': ({'v': double.infinity}, 'finite'),
        'non-JSON object': ({'v': DateTime(2026)}, 'Unsupported JSON value'),
        'depth 70': (deep(70), 'too deeply nested'),
        'node count': ({'v': List<int>.filled(10001, 0)}, 'too many nodes'),
      };
      for (final entry in bad.entries) {
        final error = _throwsValidation(
          () => ToolResultPart(id: 'r', callId: 'c', output: entry.value.$1),
        );
        ctx.observe('${entry.key}.error', '$error');
        ctx.expect(
          '$error'.contains(entry.value.$2),
          '${entry.key}: expected "${entry.value.$2}" in "$error"',
        );
      }
      // The documented limit is inclusive: depth 60 and 10,000 nodes pass.
      ToolResultPart(id: 'ok1', callId: 'c', output: deep(60));
      ToolResultPart(id: 'ok2', callId: 'c', output: List<int>.filled(9990, 0));
    },
  ),
  Check(
    id: 'unknown-and-extension-preserved',
    feature: 'conv-extensibility',
    description:
        'Unknown part types and extension fields on the conversation, '
        'messages and parts survive a round trip untouched.',
    run: (ctx) async {
      final wire = <String, dynamic>{
        'schemaVersion': 1,
        'id': 'c',
        'x-conv': {
          'k': [1, 2],
        },
        'messages': [
          {
            'id': 'm',
            'role': 'assistant',
            'status': 'complete',
            'x-message': 'mm',
            'parts': [
              {'id': 'p1', 'type': 'text', 'text': 'hi', 'x-part': true},
              {
                'id': 'p2',
                'type': 'hologram',
                'depth': 3,
                'nested': {
                  'a': [1],
                },
              },
            ],
          },
        ],
      };
      final decoded = ConversationCodec.decode(wire);
      final parts = decoded.messages.single.parts;
      ctx.expectEquals(decoded.extra, {
        'x-conv': {
          'k': [1, 2],
        },
      }, 'conversation extra');
      ctx.expectEquals(decoded.messages.single.extra, {
        'x-message': 'mm',
      }, 'message extra');
      ctx.expectEquals(parts[0].extra, {'x-part': true}, 'part extra');
      ctx.expect(parts[1] is UnknownPart, 'unknown type not preserved');
      ctx.expectEquals(parts[1].type, 'hologram', 'unknown type name');
      final reencoded = ConversationCodec.encode(decoded);
      ctx.expectEquals(
        _canonical(reencoded),
        _canonical(wire),
        'unknown content re-encoded verbatim',
      );
      ctx.observe('reencoded', reencoded);
      // An unknown part whose envelope disagrees with its raw map is refused.
      _throwsValidation(
        () =>
            UnknownPart(id: 'p', type: 'x', raw: {'id': 'other', 'type': 'x'}),
      );
    },
  ),
  Check(
    id: 'interrupted-and-pending-approval',
    feature: 'conv-states',
    description:
        'Interrupted and pending-approval messages survive a round trip, and '
        'pending approval uses the pending_approval wire name.',
    run: (ctx) async {
      final conversation = Conversation(
        id: 'states',
        messages: [
          ConversationMessage(
            id: 'm-int',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.interrupted,
            parts: [TextPart(id: 't1', text: 'Partial')],
          ),
          ConversationMessage(
            id: 'm-pend',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.pendingApproval,
            parts: [
              ToolCallPart(
                id: 'c1',
                callId: 'call-1',
                name: 'delete',
                arguments: {'path': '/tmp/x'},
              ),
              ApprovalPart(
                id: 'a1',
                callId: 'call-1',
                status: ApprovalStatus.pending,
                approvalId: 'approval-1',
              ),
            ],
          ),
          for (final status in [
            ConversationMessageStatus.pending,
            ConversationMessageStatus.streaming,
            ConversationMessageStatus.failed,
          ])
            ConversationMessage(
              id: 'm-${status.name}',
              role: ConversationRole.assistant,
              status: status,
              parts: [TextPart(id: 't-${status.name}', text: status.name)],
            ),
        ],
      );
      final wire = ConversationCodec.encode(conversation);
      final statuses = [
        for (final m in wire['messages'] as List) (m as Map)['status'],
      ];
      ctx.observe('wireStatuses', statuses);
      ctx.expectEquals(statuses, [
        'interrupted',
        'pending_approval',
        'pending',
        'streaming',
        'failed',
      ], 'wire statuses');
      final restored = _persist(conversation);
      ctx.expect(restored == conversation, 'restored snapshot differs');
      ctx.expectEquals(restored.messages.map((m) => m.status.name).toList(), [
        'interrupted',
        'pendingApproval',
        'pending',
        'streaming',
        'failed',
      ], 'restored statuses');
      final approval = restored.messages[1].parts
          .whereType<ApprovalPart>()
          .single;
      ctx.expectEquals(
        approval.status,
        ApprovalStatus.pending,
        'approval status',
      );
    },
  ),
  Check(
    id: 'decode-does-not-execute-tools',
    feature: 'conv-no-exec',
    description:
        'Decoding a snapshot with a pending approval and a recorded tool '
        'call preserves the call and approval without inventing a tool result.',
    run: (ctx) async {
      final stored = jsonEncode(
        ConversationCodec.encode(
          Conversation(
            id: 'pending',
            messages: [
              ConversationMessage(
                id: 'm1',
                role: ConversationRole.assistant,
                status: ConversationMessageStatus.pendingApproval,
                parts: [
                  ToolCallPart(
                    id: 'c1',
                    callId: 'call-1',
                    name: 'delete',
                    arguments: {'path': '/tmp/x'},
                  ),
                  ApprovalPart(
                    id: 'a1',
                    callId: 'call-1',
                    status: ApprovalStatus.pending,
                    approvalId: 'approval-1',
                    policyVersion: 'v1',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      final restored = ConversationCodec.decode(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      final parts = restored.messages.single.parts;
      final call = parts.whereType<ToolCallPart>().single;
      final approval = parts.whereType<ApprovalPart>().single;
      ctx.observe('toolCall', {
        'callId': call.callId,
        'name': call.name,
        'arguments': call.arguments,
      });
      ctx.observe('approvalStatus', approval.status.name);
      ctx.expectEquals(call.callId, 'call-1', 'preserved tool call id');
      ctx.expectEquals(call.name, 'delete', 'preserved tool name');
      ctx.expectEquals(call.arguments, {'path': '/tmp/x'}, 'preserved input');
      ctx.expectEquals(approval.callId, 'call-1', 'approval call id');
      ctx.expectEquals(approval.approvalId, 'approval-1', 'approval id');
      ctx.expectEquals(
        parts.whereType<ToolResultPart>().length,
        0,
        'decode must not invent a tool result',
      );
      ctx.expectEquals(
        approval.status,
        ApprovalStatus.pending,
        'approval stays pending',
      );
      ctx.expectEquals(
        restored.messages.single.status,
        ConversationMessageStatus.pendingApproval,
        'message stays pendingApproval',
      );
    },
  ),
  Check(
    id: 'agent-turn-snapshot-and-resume',
    feature: 'conv-agent-turn',
    description:
        'A ToolLoopAgent turn that stops at a tool approval is saved as a '
        'snapshot, restored from JSON text, and resumed from the restored '
        'data: an approval runs the tool once and a denial never runs it.',
    run: (ctx) async {
      var executions = 0;
      final server = await ctx.server((request) {
        final messages = request.jsonObject['messages'] as List;
        if ((messages.last as Map)['role'] == 'tool') {
          // agent.resume streams; agent.generate does not.
          if (request.jsonObject['stream'] == true) {
            return FixtureResponse.sse([
              _chunk({'role': 'assistant', 'content': ''}),
              _chunk({'content': 'Done.'}),
              _chunk({}, finish: 'stop'),
            ], done: true);
          }
          return FixtureResponse.json(_completion(content: 'Done.'));
        }
        return FixtureResponse.json(
          _completion(
            toolCalls: [
              {
                'id': 'call_verify_1',
                'type': 'function',
                'function': {
                  'name': 'delete',
                  'arguments': jsonEncode({'path': '/tmp/x'}),
                },
              },
            ],
            finishReason: 'tool_calls',
          ),
        );
      });
      final baseUrl = server.url('/v1');
      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      ctx.onCleanup(() async => dio.close(force: true));
      final agent = sdk.ToolLoopAgent(
        model: OpenAICompatibleChatLanguageModel(
          modelId: 'verify-model',
          config: OpenAICompatibleConfig(
            provider: 'verify-compat',
            baseUrl: baseUrl,
            client: dio,
            headers: () => {'Authorization': 'Bearer verify-key'},
          ),
        ),
        maxSteps: 3,
        approvalPolicy: sdk.ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v1',
        tools: {
          'delete': sdk.tool<Map<String, dynamic>, String>(
            description: 'Delete a path.',
            inputSchema: sdk.Schema<Map<String, dynamic>>(
              jsonSchema: const {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
              },
              fromJson: (json) => json,
            ),
            execute: (input, _) async {
              executions++;
              return 'deleted ${input['path']}';
            },
          ),
        },
      );
      final first = await agent.generate(prompt: 'Delete /tmp/x');
      final requests = first.steps.last.toolApprovalRequests;
      ctx.observe('approvalRequestCount', requests.length);
      ctx.observe('executionsAfterFirstTurn', executions);
      ctx.expectEquals(requests.length, 1, 'approval requests');
      ctx.expectEquals(executions, 0, 'executions before approval');
      final request = requests.single;
      // The application assigns ids and builds the snapshot from the turn.
      final saved = Conversation(
        id: 'turn-1',
        messages: [
          ConversationMessage(
            id: 'u1',
            role: ConversationRole.user,
            parts: [TextPart(id: 'u1-text', text: 'Delete /tmp/x')],
          ),
          ConversationMessage(
            id: 'a1',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.pendingApproval,
            parts: [
              ToolCallPart(
                id: 'a1-call',
                callId: request.toolCall.toolCallId,
                name: request.toolCall.toolName,
                arguments: Map<String, dynamic>.from(
                  request.toolCall.input as Map,
                ),
              ),
              ApprovalPart(
                id: 'a1-approval',
                callId: request.toolCall.toolCallId,
                status: ApprovalStatus.pending,
                approvalId: request.approvalId,
                toolName: request.toolCall.toolName,
                argumentsFingerprint: request.argumentsFingerprint,
                policyVersion: request.policyRevision,
              ),
            ],
          ),
        ],
      );
      final restored = _persist(saved);
      ctx.expect(restored == saved, 'restored turn differs from saved turn');
      ctx.expectEquals(executions, 0, 'executions after restore');
      final call = restored.messages.last.parts
          .whereType<ToolCallPart>()
          .single;
      final approval = restored.messages.last.parts
          .whereType<ApprovalPart>()
          .single;
      final restoredCall = provider.LanguageModelV4ToolCallPart(
        toolCallId: call.callId,
        toolName: call.name,
        input: call.arguments,
      );

      Future<String> resume({required bool approved}) async {
        final result = await agent.resume(
          messages: [
            sdk.ModelMessage(
              role: sdk.ModelMessageRole.user,
              content: 'Delete /tmp/x',
            ),
          ],
          replay: sdk.ToolApprovalReplay(
            messages: [
              sdk.ModelMessage.parts(
                role: sdk.ModelMessageRole.assistant,
                parts: [restoredCall],
              ),
            ],
            requests: [
              provider.LanguageModelV4ToolApprovalRequestPart(
                approvalId: approval.approvalId!,
                toolCall: restoredCall,
                argumentsFingerprint: approval.argumentsFingerprint,
                policyRevision: approval.policyVersion,
              ),
            ],
          ),
          toolApprovalResponses: [
            provider.LanguageModelV4ToolApprovalResponse(
              approvalId: approval.approvalId!,
              approved: approved,
              reason: approved ? null : 'User said no',
              toolCallId: call.callId,
              toolName: approval.toolName,
              argumentsFingerprint: approval.argumentsFingerprint,
              policyRevision: approval.policyVersion,
            ),
          ],
        );
        return result.text;
      }

      final deniedText = await resume(approved: false);
      ctx.observe('executionsAfterDenial', executions);
      ctx.expectEquals(executions, 0, 'executions after denial');
      ctx.expectEquals(deniedText, 'Done.', 'text after denial');
      final deniedToolMessage =
          ((server.requests.last.jsonObject['messages'] as List).last as Map);
      ctx.observe('deniedToolMessage', deniedToolMessage['content']);
      ctx.expect(
        '${deniedToolMessage['content']}'.contains('User said no'),
        'denial reason missing from the tool message: $deniedToolMessage',
      );

      final approvedText = await resume(approved: true);
      ctx.observe('executionsAfterApproval', executions);
      ctx.expectEquals(executions, 1, 'executions after approval');
      ctx.expectEquals(approvedText, 'Done.', 'text after approval');
      final toolMessage =
          (server.requests.last.jsonObject['messages'] as List).last as Map;
      ctx.expectEquals(toolMessage['role'], 'tool', 'tool message role');
      ctx.expectEquals(
        toolMessage['tool_call_id'],
        'call_verify_1',
        'tool_call_id on the wire',
      );
      ctx.expect(
        '${toolMessage['content']}'.contains('deleted /tmp/x'),
        'tool output missing: ${toolMessage['content']}',
      );
      ctx.expectEquals(
        server.requests.length,
        3,
        'requests: first turn, denied resume, approved resume',
      );
    },
  ),
]);

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': content,
        'tool_calls': ?toolCalls,
      },
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
