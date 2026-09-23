import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:test/test.dart';

void main() {
  test('round trips a pending approval and interrupted streamed reply', () {
    final conversation = Conversation(
      id: 'conversation-1',
      messages: [
        ConversationMessage(
          id: 'm-user',
          role: ConversationRole.user,
          status: ConversationMessageStatus.complete,
          parts: [TextPart(id: 'p-user', text: 'Delete the file')],
        ),
        ConversationMessage(
          id: 'm-assistant',
          role: ConversationRole.assistant,
          status: ConversationMessageStatus.interrupted,
          parts: [
            ToolCallPart(
              id: 'p-call',
              callId: 'call-1',
              name: 'deleteFile',
              arguments: {'path': '/tmp/a'},
            ),
            ApprovalPart(
              id: 'p-approval',
              callId: 'call-1',
              approvalId: 'approval-1',
              toolName: 'deleteFile',
              argumentsFingerprint: 'fp-1',
              status: ApprovalStatus.pending,
              policyVersion: 'policy-7',
            ),
          ],
        ),
      ],
    );

    final restored = ConversationCodec.decode(
      ConversationCodec.encode(conversation),
    );
    expect(restored, conversation);
    expect(restored.messages[1].status, ConversationMessageStatus.interrupted);
    expect(
      (restored.messages[1].parts[1] as ApprovalPart).status,
      ApprovalStatus.pending,
    );
    final approval = restored.messages[1].parts[1] as ApprovalPart;
    expect(approval.approvalId, 'approval-1');
    expect(approval.toolName, 'deleteFile');
    expect(approval.argumentsFingerprint, 'fp-1');
  });

  test('preserves opaque provider metadata and unknown future parts', () {
    final json = {
      'schemaVersion': 1,
      'id': 'c1',
      'metadata': {
        'provider': {'signature': 'opaque-signature'},
      },
      'futureRoot': {'keep': true},
      'messages': [
        {
          'id': 'm1',
          'role': 'assistant',
          'status': 'complete',
          'futureMessage': 'keep-me',
          'parts': [
            {
              'id': 'p1',
              'type': 'future_part',
              'nested': {'keep': true},
            },
          ],
        },
      ],
    };
    final restored = ConversationCodec.decode(json);
    final encoded = ConversationCodec.encode(restored);
    expect(encoded, json);
  });

  test('preserves unknown fields on known part types', () {
    final json = {
      'schemaVersion': 1,
      'id': 'c1',
      'messages': [
        {
          'id': 'm1',
          'role': 'user',
          'status': 'complete',
          'parts': [
            {
              'id': 'p1',
              'type': 'text',
              'text': 'hello',
              'futureField': {'preserve': true},
            },
          ],
        },
      ],
    };
    final restored = ConversationCodec.decode(json);
    expect(ConversationCodec.encode(restored), json);
  });

  test(
    'rejects unsupported schema versions, duplicate IDs, and invalid states',
    () {
      expect(
        () => ConversationCodec.decode({
          'schemaVersion': 2,
          'id': 'c1',
          'messages': [],
        }),
        throwsA(isA<ConversationSchemaException>()),
      );
      expect(
        () => ConversationCodec.decode({
          'schemaVersion': 1,
          'id': 'c1',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'status': 'complete',
              'parts': [
                {'id': 'p1', 'type': 'text', 'text': 'a'},
                {'id': 'p1', 'type': 'text', 'text': 'b'},
              ],
            },
          ],
        }),
        throwsA(isA<ConversationValidationException>()),
      );
      expect(
        () => ConversationCodec.decode({
          'schemaVersion': 1,
          'id': 'c1',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'status': 'pending_approval',
              'parts': [
                {'id': 'p1', 'type': 'text', 'text': 'a'},
              ],
            },
          ],
        }),
        throwsA(isA<ConversationValidationException>()),
      );
      expect(
        () => TextPart(id: '   ', text: 'x'),
        throwsA(isA<ConversationValidationException>()),
      );
      expect(
        () => ConversationCodec.decode({
          'schemaVersion': 1,
          'id': 'c1',
          'messages': [
            {
              'id': 'm1',
              'role': 'tool',
              'status': 'complete',
              'parts': [
                {
                  'id': 'p1',
                  'type': 'tool_result',
                  'callId': 'call-1',
                  'isError': false,
                },
              ],
            },
          ],
        }),
        throwsA(isA<ConversationValidationException>()),
      );
    },
  );

  test('uses a binary reference instead of embedding bytes', () {
    final file = FilePart(
      id: 'file-part',
      uri: 'https://cdn.example/file.pdf',
      mimeType: 'application/pdf',
      name: 'file.pdf',
    );
    final encoded = ConversationCodec.encode(
      Conversation(
        id: 'c1',
        messages: [
          ConversationMessage(
            id: 'm1',
            role: ConversationRole.user,
            parts: [file],
          ),
        ],
      ),
    );
    expect((encoded['messages'] as List).single['parts'], [
      {
        'id': 'file-part',
        'type': 'file',
        'uri': 'https://cdn.example/file.pdf',
        'mimeType': 'application/pdf',
        'name': 'file.pdf',
      },
    ]);
  });

  test('round trips typed binary and provider file references', () {
    final value = Conversation(
      id: 'media',
      messages: [
        ConversationMessage(
          id: 'm1',
          role: ConversationRole.assistant,
          parts: [
            FilePart(
              id: 'bytes',
              data: ConversationFileBytes(Uint8List.fromList([1, 2, 3])),
              mimeType: 'image/png',
              name: 'a.png',
            ),
            FilePart(
              id: 'ref',
              data: ConversationFileProviderReference(
                namespace: 'provider-a',
                id: 'asset-1',
              ),
              mimeType: 'application/pdf',
            ),
          ],
        ),
      ],
    );
    final encoded = ConversationCodec.encode(value);
    expect(encoded['messages'], isNotEmpty);
    final restored = ConversationCodec.decode(encoded);
    expect(restored, value);
    expect(
      (restored.messages.single.parts.first as FilePart).data,
      isA<ConversationFileBytes>(),
    );
  });

  test(
    'round trips v4 typed provider parts and tool output discriminators',
    () {
      final conversation = Conversation(
        id: 'lossless',
        messages: [
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            parts: [
              TextPart(
                id: 'text-part',
                text: 'visible answer',
                providerOptions: {
                  'vendor': {'segment': 'answer'},
                },
              ),
              ReasoningPart(
                id: 'reasoning-part',
                text: 'private trace',
                signature: 'sig-1',
                providerOptions: {
                  'vendor': {'encrypted': true},
                },
              ),
              ImagePart(
                id: 'image-part',
                data: ConversationFileBytes(Uint8List.fromList([9, 8, 7])),
                mimeType: 'image/png',
                providerOptions: {
                  'vendor': {'asset': 'image-1'},
                },
              ),
              RedactedReasoningPart(
                id: 'redacted-reasoning',
                data: Uint8List.fromList([4, 5, 6]),
                providerOptions: {
                  'vendor': {'redacted': true},
                },
              ),
              ToolCallPart(
                id: 'call-part',
                callId: 'call-1',
                name: 'search',
                arguments: {'q': 'dart'},
                providerExecuted: true,
                providerOptions: {
                  'vendor': {'trace': 't-1'},
                },
              ),
              ReasoningFilePart(
                id: 'reasoning-file',
                data: ConversationFileBytes(Uint8List.fromList([0, 1, 255])),
                mimeType: 'application/octet-stream',
                providerOptions: {
                  'vendor': {'encrypted': true},
                },
              ),
              DocumentSourcePart(
                id: 'doc-source',
                mediaType: 'application/pdf',
                title: 'Research paper',
                name: 'paper.pdf',
                providerMetadata: {
                  'vendor': {'documentId': 'doc-7'},
                },
              ),
              UnknownPart(
                id: 'opaque-1',
                type: 'opaque',
                raw: {
                  'id': 'opaque-1',
                  'type': 'opaque',
                  'provider': 'vendor-x',
                  'raw': ['scalar', 7, true],
                },
              ),
              ToolResultPart(
                id: 'result-1',
                callId: 'call-1',
                toolName: 'search',
                output: {'ok': true},
                outputKind: 'json',
                preliminary: true,
                isDynamic: true,
                providerOptions: {
                  'vendor': {'requestId': 'r-1'},
                },
              ),
              ToolResultPart(
                id: 'result-error',
                callId: 'call-1',
                toolName: 'search',
                output: {'code': 'denied'},
                isError: true,
                outputKind: 'error_json',
              ),
              ToolResultPart(
                id: 'result-denied',
                callId: 'call-1',
                toolName: 'search',
                output: null,
                isError: true,
                outputKind: 'execution_denied',
                executionDeniedReason: 'Needs approval',
                executionDeniedApprovalId: 'approval-1',
              ),
            ],
          ),
        ],
      );

      final encoded = ConversationCodec.encode(conversation);
      final restored = ConversationCodec.decode(encoded);
      expect(restored, conversation);
      final reasoningFile = restored.messages.single.parts
          .whereType<ReasoningFilePart>()
          .single;
      expect(reasoningFile.data, isA<ConversationFileBytes>());
      expect((reasoningFile.data! as ConversationFileBytes).bytes, [0, 1, 255]);
      final denied = restored.messages.single.parts.last as ToolResultPart;
      expect(denied.executionDeniedReason, 'Needs approval');
      expect(denied.executionDeniedApprovalId, 'approval-1');
    },
  );

  test('rejects empty provider file reference fields at construction', () {
    expect(
      () => ConversationFileProviderReference(namespace: '', id: 'asset-1'),
      throwsA(isA<ConversationValidationException>()),
    );
    expect(
      () => ConversationFileProviderReference(namespace: 'provider-a', id: ''),
      throwsA(isA<ConversationValidationException>()),
    );
  });

  test('does not expose mutable binary storage through a file part', () {
    final file = FilePart(
      id: 'bytes',
      data: ConversationFileBytes(Uint8List.fromList([1, 2, 3])),
      mimeType: 'application/octet-stream',
    );
    final bytes = (file.data! as ConversationFileBytes).bytes;
    expect(() => bytes[0] = 9, throwsA(anything));
    expect(bytes, [1, 2, 3]);
  });

  test('rejects ambiguous URI and typed file data', () {
    expect(
      () => FilePart(
        id: 'ambiguous',
        uri: 'https://cdn.example/file.bin',
        data: ConversationFileBytes(Uint8List.fromList([1])),
        mimeType: 'application/octet-stream',
      ),
      throwsA(isA<ConversationValidationException>()),
    );
  });

  test('decodes the legacy URI-only file representation', () {
    final restored = ConversationCodec.decode({
      'schemaVersion': 1,
      'id': 'legacy-uri',
      'messages': [
        {
          'id': 'm1',
          'role': 'user',
          'status': 'complete',
          'parts': [
            {
              'id': 'file-1',
              'type': 'file',
              'uri': 'https://cdn.example/file.bin',
              'mimeType': 'application/octet-stream',
            },
          ],
        },
      ],
    });
    final file = restored.messages.single.parts.single as FilePart;
    expect(file.uri, 'https://cdn.example/file.bin');
    expect(file.data, isNull);
    expect(ConversationCodec.encode(restored), {
      'schemaVersion': 1,
      'id': 'legacy-uri',
      'messages': [
        {
          'id': 'm1',
          'role': 'user',
          'status': 'complete',
          'parts': [
            {
              'id': 'file-1',
              'type': 'file',
              'uri': 'https://cdn.example/file.bin',
              'mimeType': 'application/octet-stream',
            },
          ],
        },
      ],
    });
  });

  test('deep freezes nested provider values and preserves hash equality', () {
    final arguments = <String, dynamic>{
      'nested': <String, dynamic>{'x': 1},
    };
    final conversation = Conversation(
      id: 'c1',
      metadata: {
        'opaque': <String, dynamic>{'signature': 'sig'},
      },
      messages: [
        ConversationMessage(
          id: 'm1',
          role: ConversationRole.assistant,
          parts: [
            ToolCallPart(
              id: 'p1',
              callId: 'call-1',
              name: 'tool',
              arguments: arguments,
            ),
          ],
        ),
      ],
    );
    arguments['nested']['x'] = 99;
    final restored = ConversationCodec.decode(
      ConversationCodec.encode(conversation),
    );
    expect(ConversationCodec.encode(conversation)['metadata'], {
      'opaque': {'signature': 'sig'},
    });
    expect(
      (conversation.messages.single.parts.single as ToolCallPart)
          .arguments['nested'],
      {'x': 1},
    );
    expect(
      () =>
          ((conversation.messages.single.parts.single as ToolCallPart)
                      .arguments['nested']
                  as Map<String, dynamic>)['x'] =
              2,
      throwsA(anything),
    );
    expect({conversation, restored}, hasLength(1));

    final orderedA = ToolCallPart(
      id: 'p2',
      callId: 'call-2',
      name: 'tool',
      arguments: {'a': 1, 'b': 2},
    );
    final orderedB = ToolCallPart(
      id: 'p2',
      callId: 'call-2',
      name: 'tool',
      arguments: {'b': 2, 'a': 1},
    );
    expect(orderedA, orderedB);
    expect(orderedA.hashCode, orderedB.hashCode);

    final shared = <String, dynamic>{'x': 1};
    expect(
      () => Conversation(
        id: 'shared',
        metadata: {'a': shared, 'b': shared},
        messages: const [],
      ),
      returnsNormally,
    );
  });

  test(
    'accepts empty text and rejects malformed or cyclic persisted values',
    () {
      final empty = ConversationCodec.decode({
        'schemaVersion': 1,
        'id': 'c1',
        'messages': [
          {
            'id': 'm1',
            'role': 'user',
            'status': 'complete',
            'parts': [
              {'id': 'p1', 'type': 'text', 'text': ''},
            ],
          },
        ],
      });
      expect((empty.messages.single.parts.single as TextPart).text, '');
      expect(
        () => ConversationCodec.decode({
          'schemaVersion': 1,
          'id': 'c1',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'status': 'complete',
              'parts': [
                {'id': 'p1', 'type': 'text', 'text': '', 'metadata': 'bad'},
              ],
            },
          ],
        }),
        throwsA(isA<ConversationValidationException>()),
      );
      final cycle = <String, dynamic>{};
      cycle['self'] = cycle;
      expect(
        () => Conversation(id: 'c1', metadata: cycle, messages: const []),
        throwsA(isA<ConversationValidationException>()),
      );
      final deep = <String, dynamic>{};
      var cursor = deep;
      for (var i = 0; i < 65; i++) {
        final next = <String, dynamic>{};
        cursor['next'] = next;
        cursor = next;
      }
      expect(
        () => Conversation(id: 'deep', metadata: deep, messages: const []),
        throwsA(isA<ConversationValidationException>()),
      );
      final wide = <String, dynamic>{
        for (var i = 0; i < 10001; i++) 'key-$i': i,
      };
      expect(
        () => Conversation(id: 'wide', metadata: wide, messages: const []),
        throwsA(isA<ConversationValidationException>()),
      );
    },
  );

  test('approval and unknown parts keep stable references', () {
    expect(
      () => ConversationCodec.decode({
        'schemaVersion': 1,
        'id': 'c1',
        'messages': [
          {
            'id': 'm1',
            'role': 'assistant',
            'status': 'pending_approval',
            'parts': [
              {
                'id': 'p1',
                'type': 'approval',
                'callId': 'missing-call',
                'status': 'pending',
              },
            ],
          },
        ],
      }),
      throwsA(isA<ConversationValidationException>()),
    );
    expect(
      () => ConversationCodec.decode({
        'schemaVersion': 1,
        'id': 'c1',
        'messages': [
          {
            'id': 'm1',
            'role': 'assistant',
            'status': 'complete',
            'parts': [
              {'id': 'p1', 'type': 'future', 'nested': {}, 'type2': 'bad'},
            ],
          },
        ],
      }),
      returnsNormally,
    );
  });

  test('rejects duplicate message and call IDs or orphaned results', () {
    ConversationMessage message(String id, List<ConversationPart> parts) =>
        ConversationMessage(
          id: id,
          role: ConversationRole.assistant,
          parts: parts,
        );
    ToolCallPart call(String id) => ToolCallPart(
      id: 'part-$id',
      callId: 'call-1',
      name: 'deleteFile',
      arguments: const {'path': '/tmp/example'},
    );

    expect(
      () => Conversation(
        id: 'duplicate-message',
        messages: [message('m1', []), message('m1', [])],
      ),
      throwsA(isA<ConversationValidationException>()),
    );
    expect(
      () => Conversation(
        id: 'duplicate-call',
        messages: [
          message('m1', [call('a')]),
          message('m2', [call('b')]),
        ],
      ),
      throwsA(isA<ConversationValidationException>()),
    );
    expect(
      () => Conversation(
        id: 'orphaned-result',
        messages: [
          message('m1', [
            ToolResultPart(id: 'result-1', callId: 'missing', output: 'done'),
          ]),
        ],
      ),
      throwsA(isA<ConversationValidationException>()),
    );
  });

  test('rejects malformed wire envelopes and typed file payloads', () {
    Map<String, dynamic> envelope(Object? part) => {
      'schemaVersion': 1,
      'id': 'c1',
      'messages': [
        {
          'id': 'm1',
          'role': 'assistant',
          'status': 'complete',
          'parts': [part],
        },
      ],
    };
    final malformed = <Object?>[
      9,
      {'id': 'p1'},
      {'id': 'p1', 'type': 'text', 'text': 42},
      {'id': 'p1', 'type': 'text', 'text': '', 'providerOptions': []},
      {'id': 'p1', 'type': 'reasoning', 'text': '', 'signature': 42},
      {'id': 'p1', 'type': 'file', 'mimeType': 'image/png', 'data': []},
      {
        'id': 'p1',
        'type': 'file',
        'mimeType': 'image/png',
        'data': {'kind': 'bytes', 'base64': 'not base64'},
      },
      {
        'id': 'p1',
        'type': 'file',
        'mimeType': 'image/png',
        'data': {'kind': 'provider_reference', 'namespace': 'vendor'},
      },
      {
        'id': 'p1',
        'type': 'redacted_reasoning',
        'data': {'kind': 'url', 'url': 'https://example.test'},
      },
    ];
    for (final part in malformed) {
      expect(
        () => ConversationCodec.decode(envelope(part)),
        throwsA(isA<ConversationValidationException>()),
        reason: '$part',
      );
    }
  });
}
