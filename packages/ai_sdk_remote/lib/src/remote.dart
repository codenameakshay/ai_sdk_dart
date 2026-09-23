import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:http/http.dart' as http;

const remoteUiMessageStreamVersion = 'v1';

class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.message);
  final String message;
  @override
  String toString() => 'RemoteProtocolException: $message';
}

class RemoteCancelledException implements Exception {
  const RemoteCancelledException();
  @override
  String toString() => 'RemoteCancelledException';
}

class RemoteCancellationToken {
  bool _cancelled = false;
  final _changes = StreamController<void>.broadcast();
  final _cancelledSignal = Completer<void>();
  bool get isCancelled => _cancelled;
  Stream<void> get changes => _changes.stream;
  Future<void> get whenCancelled => _cancelledSignal.future;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledSignal.complete();
    _changes.add(null);
  }

  Future<void> dispose() async {
    cancel();
    await _changes.close();
  }
}

class RemoteConversationTransport {
  RemoteConversationTransport({
    required this.endpoint,
    http.Client? client,
    this.authHeaders,
    Map<String, String> headers = const {},
  }) : _client = client ?? http.Client(),
       _headers = Map.unmodifiable(headers),
       _ownsClient = client == null;

  final Uri endpoint;
  final FutureOr<Map<String, String>> Function()? authHeaders;
  final http.Client _client;
  final bool _ownsClient;
  final Map<String, String> _headers;
  final _activeAborters = <Completer<void>>{};
  bool _closed = false;

  Stream<Conversation> send(
    Conversation conversation, {
    RemoteCancellationToken? cancellation,
  }) {
    if (_closed) throw StateError('Remote transport is disposed');
    if (cancellation?.isCancelled ?? false) return const Stream.empty();
    Completer<void>? aborter;
    var paused = false;
    StreamSubscription<void>? cancellationSubscription;
    StreamSubscription<Conversation>? producer;
    late final StreamController<Conversation> controller;
    controller = StreamController<Conversation>(
      onListen: () {
        if (cancellation?.isCancelled ?? false) {
          unawaited(controller.close());
          return;
        }
        if (_closed) {
          controller.addError(StateError('Remote transport is disposed'));
          unawaited(controller.close());
          return;
        }
        final activeAborter = aborter = Completer<void>();
        _activeAborters.add(activeAborter);
        final cancellationSignal = Completer<void>();
        if (cancellation != null) {
          cancellationSubscription = cancellation.changes.listen((_) {
            if (!cancellationSignal.isCompleted) {
              cancellationSignal.complete();
            }
          });
          if (cancellation.isCancelled) cancellationSignal.complete();
        }
        final abortTrigger = cancellation == null
            ? activeAborter.future
            : Future.any<void>([
                activeAborter.future,
                cancellationSignal.future,
              ]);
        producer =
            _sendBody(
              conversation,
              cancellation: cancellation,
              aborter: activeAborter,
              abortTrigger: abortTrigger,
              cancellationSubscription: cancellationSubscription,
            ).listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        if (paused) producer!.pause();
      },
      onPause: () {
        paused = true;
        producer?.pause();
      },
      onResume: () {
        paused = false;
        producer?.resume();
      },
      onCancel: () async {
        final activeAborter = aborter;
        if (activeAborter == null) return;
        if (!activeAborter.isCompleted) activeAborter.complete();
        try {
          await cancellationSubscription?.cancel();
        } catch (_) {
          // Preserve the producer's first error.
        }
        try {
          await producer?.cancel();
        } catch (_) {
          // Downstream cancellation completes normally. The producer's
          // RemoteCancelledException is intentionally not delivered through
          // StreamSubscription.cancel(); active sends surface it via their
          // stream future instead.
        }
      },
    );
    return controller.stream;
  }

  Stream<Conversation> _sendBody(
    Conversation conversation, {
    required RemoteCancellationToken? cancellation,
    required Completer<void> aborter,
    required Future<void> abortTrigger,
    required StreamSubscription<void>? cancellationSubscription,
  }) async* {
    try {
      // Validate and materialize media before obtaining auth or opening the
      // HTTP request. Provider-scoped references cannot be represented by the
      // UI-message protocol and must fail instead of becoming a null URL.
      final uiMessages = _toUiMessages(conversation);
      final headers = <String, String>{
        ..._headers,
        if (authHeaders != null)
          ...await _beforeAbort(authHeaders!(), abortTrigger),
        'accept': 'text/event-stream',
        'content-type': 'application/json',
        'x-vercel-ai-ui-message-stream': remoteUiMessageStreamVersion,
      };
      if (_closed || (cancellation?.isCancelled ?? false)) {
        throw const RemoteCancelledException();
      }
      final request =
          http.AbortableRequest('POST', endpoint, abortTrigger: abortTrigger)
            ..headers.addAll(headers)
            ..body = jsonEncode({'messages': uiMessages});
      final response = await _client.send(request);
      final streamVersion = response.headers['x-vercel-ai-ui-message-stream'];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RemoteProtocolException(
          'Remote request failed (${response.statusCode})',
        );
      }
      final mediaType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (streamVersion != remoteUiMessageStreamVersion ||
          mediaType != 'text/event-stream') {
        throw const RemoteProtocolException(
          'Invalid UI message stream headers',
        );
      }
      final reducer = _ConversationReducer(conversation);
      var done = false;
      try {
        await for (final frame in _sseFrames(response.stream)) {
          if (cancellation?.isCancelled ?? false) return;
          if (frame['__done__'] == true) {
            done = true;
            if (!reducer.hasTerminalEvent) {
              throw const RemoteProtocolException(
                'UI message stream ended without finish or abort',
              );
            }
            break;
          }
          yield reducer.apply(frame);
        }
      } on http.RequestAbortedException {
        if (cancellation?.isCancelled ?? false || _closed) return;
        rethrow;
      } on FormatException catch (error) {
        throw RemoteProtocolException('Malformed SSE or JSON frame: $error');
      }
      if (cancellation?.isCancelled ?? false) return;
      if (!done) {
        throw const RemoteProtocolException('Truncated UI message stream');
      }
    } on http.RequestAbortedException {
      if (cancellation?.isCancelled ?? false || _closed) {
        throw const RemoteCancelledException();
      }
      rethrow;
    } finally {
      if (!aborter.isCompleted) aborter.complete();
      _activeAborters.remove(aborter);
      try {
        await cancellationSubscription?.cancel();
      } catch (_) {
        // Cleanup must not replace a transport or protocol failure.
      }
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final aborter in _activeAborters.toList()) {
      if (!aborter.isCompleted) aborter.complete();
    }
    if (_ownsClient) _client.close();
  }
}

Future<T> _beforeAbort<T>(FutureOr<T> operation, Future<void> abortTrigger) {
  return Future.any<T>([
    Future<T>.value(operation),
    abortTrigger.then<T>((_) => throw const RemoteCancelledException()),
  ]);
}

List<Map<String, dynamic>> _toUiMessages(Conversation conversation) {
  final toolResults = <String, ToolResultPart>{};
  final approvals = <String, ApprovalPart>{};
  for (final message in conversation.messages) {
    for (final part in message.parts) {
      if (part is ToolResultPart) toolResults[part.callId] = part;
      if (part is ApprovalPart) approvals[part.callId] = part;
    }
  }
  return conversation.messages.map((message) {
    final parts = <Map<String, dynamic>>[];
    for (final part in message.parts) {
      switch (part) {
        case TextPart():
          parts.add({
            'type': 'text',
            'text': part.text,
            if (part.providerOptions.isNotEmpty)
              'providerMetadata': part.providerOptions,
          });
        case ReasoningPart():
          parts.add({
            'type': 'reasoning',
            'text': part.text,
            if (part.providerOptions.isNotEmpty)
              'providerMetadata': part.providerOptions,
          });
        case FilePart(:final uri, :final data, :final mimeType, :final name):
          final url = switch (data) {
            ConversationFileBytes(:final bytes) =>
              'data:$mimeType;base64,${base64Encode(bytes)}',
            ConversationFileProviderReference(:final namespace, :final id) =>
              throw UnsupportedError(
                'Provider file reference $namespace/$id cannot be sent '
                'through the UI-message transport.',
              ),
            null => uri!,
          };
          final file = <String, dynamic>{
            'type': 'file',
            'url': url,
            'mediaType': mimeType,
          };
          if (name != null) file['filename'] = name;
          if (part.providerOptions.isNotEmpty) {
            file['providerMetadata'] = part.providerOptions;
          }
          parts.add(file);
        case ReasoningFilePart(
          :final uri,
          :final data,
          :final mimeType,
          :final name,
          :final providerOptions,
        ):
          final url = switch (data) {
            ConversationFileBytes(:final bytes) =>
              'data:$mimeType;base64,${base64Encode(bytes)}',
            ConversationFileProviderReference(:final namespace, :final id) =>
              throw UnsupportedError(
                'Provider reasoning file reference $namespace/$id cannot be '
                'sent through the UI-message transport.',
              ),
            null => uri!,
          };
          final file = <String, dynamic>{
            'type': 'reasoning-file',
            'url': url,
            'mediaType': mimeType,
          };
          if (name != null) file['filename'] = name;
          if (providerOptions.isNotEmpty) {
            file['providerMetadata'] = providerOptions;
          }
          parts.add(file);
        case ImagePart(
          :final uri,
          :final data,
          :final mimeType,
          :final providerOptions,
        ):
          if (mimeType == null) {
            throw UnsupportedError(
              'Image part ${part.id} requires a MIME type for UI transport.',
            );
          }
          final url = switch (data) {
            ConversationFileBytes(:final bytes) =>
              'data:$mimeType;base64,${base64Encode(bytes)}',
            ConversationFileProviderReference() => throw UnsupportedError(
              'Provider image references are not supported by UI transport.',
            ),
            null => uri!,
          };
          parts.add({
            'type': 'file',
            'url': url,
            'mediaType': mimeType,
            if (providerOptions.isNotEmpty) 'providerMetadata': providerOptions,
          });
        case RedactedReasoningPart():
          throw UnsupportedError(
            'Redacted reasoning is not supported by UI transport.',
          );
        case SourcePart():
          parts.add({
            'type': 'source-url',
            'sourceId': part.id,
            'url': part.uri,
            if (part.title != null) 'title': part.title,
            if (part.providerMetadata.isNotEmpty)
              'providerMetadata': part.providerMetadata,
          });
        case DocumentSourcePart():
          parts.add({
            'type': 'source-document',
            'sourceId': part.id,
            'mediaType': part.mediaType,
            'title': part.title,
            if (part.name != null) 'filename': part.name,
            if (part.providerMetadata.isNotEmpty)
              'providerMetadata': part.providerMetadata,
          });
        case ToolCallPart():
          final result = toolResults[part.callId];
          final approval = approvals[part.callId];
          final dynamicTool =
              part.extra['dynamic'] == true || result?.isDynamic == true;
          final denied =
              approval?.status == ApprovalStatus.rejected ||
              result?.outputKind == 'execution_denied';
          if (denied && approval?.status != ApprovalStatus.rejected) {
            throw UnsupportedError(
              'Denied tool output ${part.callId} requires a rejected approval.',
            );
          }
          if (result != null && result.isError && !denied) {
            if (result.output is! String) {
              throw UnsupportedError(
                'UI transport supports tool errors with text output only.',
              );
            }
          }
          final state = result != null
              ? denied
                    ? 'output-denied'
                    : (result.isError ? 'output-error' : 'output-available')
              : approval != null
              ? (approval.status == ApprovalStatus.pending
                    ? 'approval-requested'
                    : 'approval-responded')
              : 'input-available';
          final encoded = <String, dynamic>{
            'type': dynamicTool ? 'dynamic-tool' : 'tool-${part.name}',
            'toolCallId': part.callId,
            'state': state,
            'input': part.arguments,
            if (dynamicTool) 'toolName': result?.toolName ?? part.name,
            if (part.providerExecuted) 'providerExecuted': true,
            if (part.providerOptions.isNotEmpty)
              'callProviderMetadata': part.providerOptions,
            if (result != null && result.preliminary) 'preliminary': true,
            if (result != null && result.providerOptions.isNotEmpty)
              'resultProviderMetadata': result.providerOptions,
            if (approval != null)
              'approval': {
                'id': approval.approvalId ?? approval.id,
                if (approval.status != ApprovalStatus.pending)
                  'approved': approval.status == ApprovalStatus.approved,
                if (approval.extra['reason'] case final String reason)
                  'reason': reason,
              },
          };
          if (result != null && !denied) {
            if (result.isError) {
              encoded['errorText'] = result.output;
            } else {
              encoded['output'] = result.output;
            }
          }
          parts.add(encoded);
        case ToolResultPart() || ApprovalPart():
          continue;
        case UnknownPart():
          parts.add({...part.raw});
      }
    }
    return {
      ...message.extra,
      'id': message.id,
      'role': message.role.name,
      'parts': parts,
      if (message.metadata.isNotEmpty) 'metadata': message.metadata,
    };
  }).toList();
}

const _doneFrame = <String, dynamic>{'__done__': true};

Stream<Map<String, dynamic>> _sseFrames(Stream<List<int>> bytes) async* {
  final decoder = utf8.decoder;
  var pending = '';
  var data = <String>[];
  await for (final chunk in decoder.bind(bytes)) {
    pending += chunk;
    var newline = pending.indexOf('\n');
    while (newline >= 0) {
      var line = pending.substring(0, newline);
      pending = pending.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          final joined = data.join('\n');
          data = [];
          if (joined == '[DONE]') {
            yield _doneFrame;
          } else {
            final decoded = jsonDecode(joined);
            if (decoded is! Map) {
              throw const FormatException('SSE data must be a JSON object');
            }
            final frame = <String, dynamic>{};
            for (final entry in decoded.entries) {
              if (entry.key is! String) {
                throw const FormatException('SSE object keys must be strings');
              }
              frame[entry.key as String] = entry.value;
            }
            yield frame;
          }
        }
      } else if (!line.startsWith(':')) {
        if (line.startsWith('data:')) {
          var value = line.substring(5);
          if (value.startsWith(' ')) value = value.substring(1);
          data.add(value);
        }
      }
      newline = pending.indexOf('\n');
    }
  }
  if (pending.isNotEmpty || data.isNotEmpty) {
    throw const FormatException('Truncated SSE event');
  }
}

class _ConversationReducer {
  _ConversationReducer(Conversation initial)
    : _conversationId = initial.id,
      _messages = [...initial.messages],
      _conversationMetadata = initial.metadata,
      _conversationExtra = initial.extra;

  final String _conversationId;
  final List<ConversationMessage> _messages;
  final Map<String, dynamic> _conversationMetadata;
  final Map<String, dynamic> _conversationExtra;
  final Map<String, String> _inputBuffers = {};
  final Map<String, String> _approvalCalls = {};
  final Map<String, int> _unknownCounts = {};
  String? _assistantId;
  final List<ConversationPart> _parts = [];
  final Map<String, int> _partIndexes = {};
  final Map<String, int> _toolIndexes = {};
  int _currentStepStart = 0;
  Map<String, dynamic> _messageMetadata = {};
  ConversationMessageStatus _status = ConversationMessageStatus.streaming;
  bool _hasTerminalEvent = false;
  bool get hasTerminalEvent => _hasTerminalEvent;

  Conversation apply(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is! String) {
      throw const RemoteProtocolException('Event type is missing');
    }
    switch (type) {
      case 'start':
        _start(event);
      case 'text-start':
        _textStart(event, reasoning: false);
      case 'text-delta':
        _textDelta(event, reasoning: false);
      case 'text-end':
        _textMetadata(event, reasoning: false);
      case 'reasoning-start':
        _textStart(event, reasoning: true);
      case 'reasoning-delta':
        _textDelta(event, reasoning: true);
      case 'reasoning-end':
        _textMetadata(event, reasoning: true);
      case 'tool-input-start':
        _toolStart(event);
      case 'tool-input-delta':
        _toolDelta(event);
      case 'tool-input-available':
        _toolAvailable(event, false);
      case 'tool-input-error':
        _toolAvailable(event, true);
      case 'tool-approval-request':
        _approvalRequest(event);
      case 'tool-approval-response':
        _approvalResponse(event);
      case 'tool-output-available':
        _toolOutput(event, false);
      case 'tool-output-error':
        _toolOutput(event, true);
      case 'tool-output-denied':
        _toolOutputDenied(event);
      case 'source-url':
        _sourceUrl(event);
      case 'source-document':
        _sourceDocument(event);
      case 'file':
        _file(event, reasoning: false);
      case 'reasoning-file':
        _file(event, reasoning: true);
      case 'message-metadata':
        _messageMetadata = _map(event['messageMetadata'], 'messageMetadata');
      case 'error':
        _status = ConversationMessageStatus.failed;
        _messageMetadata['error'] = _string(event, 'errorText');
      case 'abort':
        _status = ConversationMessageStatus.interrupted;
        _hasTerminalEvent = true;
      case 'finish':
        _hasTerminalEvent = true;
        if (_status == ConversationMessageStatus.streaming) {
          _status = ConversationMessageStatus.complete;
        }
      case 'start-step' || 'finish-step' || 'reset-step':
        if (type == 'start-step') {
          _currentStepStart = _parts.length;
        }
        if (type == 'reset-step') {
          if (_currentStepStart < _parts.length) {
            _parts.removeRange(_currentStepStart, _parts.length);
          }
          _partIndexes.clear();
          _toolIndexes.clear();
          _inputBuffers.removeWhere(
            (callId, _) => !_parts.any(
              (part) => part is ToolCallPart && part.callId == callId,
            ),
          );
          _approvalCalls.removeWhere(
            (_, callId) => !_parts.any(
              (part) => part is ToolCallPart && part.callId == callId,
            ),
          );
          for (var index = 0; index < _parts.length; index++) {
            final part = _parts[index];
            if (part is ToolCallPart) _toolIndexes[part.callId] = index;
          }
          if (_status == ConversationMessageStatus.failed ||
              (_status == ConversationMessageStatus.pendingApproval &&
                  !_parts.any(
                    (part) =>
                        part is ApprovalPart &&
                        part.status == ApprovalStatus.pending,
                  ))) {
            _status = ConversationMessageStatus.streaming;
          }
          _currentStepStart = _parts.length;
        }
      default:
        _unknown(event);
    }
    return _snapshot();
  }

  void _start(Map<String, dynamic> event) {
    _assistantId =
        (event['messageId'] as String?) ?? 'remote-${_messages.length + 1}';
    _parts.clear();
    _partIndexes.clear();
    _toolIndexes.clear();
    _inputBuffers.clear();
    _approvalCalls.clear();
    _currentStepStart = 0;
    _messageMetadata = event['messageMetadata'] == null
        ? {}
        : _map(event['messageMetadata'], 'messageMetadata');
    _status = ConversationMessageStatus.streaming;
  }

  void _textStart(Map<String, dynamic> e, {required bool reasoning}) {
    final id = _string(e, 'id');
    if (_partIndexes.containsKey(id)) return;
    _partIndexes[id] = _parts.length;
    _parts.add(
      reasoning
          ? ReasoningPart(
              id: id,
              text: '',
              providerOptions: _optionalMap(e, 'providerMetadata'),
            )
          : TextPart(
              id: id,
              text: '',
              providerOptions: _optionalMap(e, 'providerMetadata'),
            ),
    );
  }

  void _textDelta(Map<String, dynamic> e, {required bool reasoning}) {
    final id = _string(e, 'id');
    final delta = _stringAllowEmpty(e, 'delta');
    final index = _partIndexes[id];
    if (index == null) {
      throw RemoteProtocolException('Delta without start for $id');
    }
    final old = _parts[index];
    if (reasoning && old is ReasoningPart) {
      _parts[index] = ReasoningPart(
        id: id,
        text: old.text + delta,
        providerOptions: _mergeProviderMetadata(
          old.providerOptions,
          _optionalMap(e, 'providerMetadata'),
        ),
      );
    } else if (!reasoning && old is TextPart) {
      _parts[index] = TextPart(
        id: id,
        text: old.text + delta,
        providerOptions: _mergeProviderMetadata(
          old.providerOptions,
          _optionalMap(e, 'providerMetadata'),
        ),
      );
    } else {
      throw RemoteProtocolException('Mismatched text boundary for $id');
    }
  }

  void _textMetadata(Map<String, dynamic> e, {required bool reasoning}) {
    final id = _string(e, 'id');
    final index = _partIndexes[id];
    if (index == null) {
      throw RemoteProtocolException('Boundary without start for $id');
    }
    final old = _parts[index];
    final providerOptions = _optionalMap(e, 'providerMetadata');
    if (reasoning && old is ReasoningPart) {
      _parts[index] = ReasoningPart(
        id: id,
        text: old.text,
        providerOptions: _mergeProviderMetadata(
          old.providerOptions,
          providerOptions,
        ),
      );
    } else if (!reasoning && old is TextPart) {
      _parts[index] = TextPart(
        id: id,
        text: old.text,
        providerOptions: _mergeProviderMetadata(
          old.providerOptions,
          providerOptions,
        ),
      );
    } else {
      throw RemoteProtocolException('Mismatched text boundary for $id');
    }
    _partIndexes.remove(id);
  }

  void _toolStart(Map<String, dynamic> e) {
    final id = _string(e, 'toolCallId');
    if (_toolIndexes.containsKey(id)) return;
    final name = _string(e, 'toolName');
    _toolIndexes[id] = _parts.length;
    _parts.add(
      ToolCallPart(
        id: 'tool-$id',
        callId: id,
        name: name,
        arguments: {},
        providerExecuted: e['providerExecuted'] == true,
        providerOptions: _optionalMap(e, 'providerMetadata'),
        extra: {if (e['dynamic'] == true) 'dynamic': true},
      ),
    );
  }

  void _toolDelta(Map<String, dynamic> e) {
    final id = _string(e, 'toolCallId');
    _inputBuffers[id] =
        (_inputBuffers[id] ?? '') + _stringAllowEmpty(e, 'inputTextDelta');
  }

  void _toolAvailable(Map<String, dynamic> e, bool error) {
    final callId = _string(e, 'toolCallId');
    final name = _string(e, 'toolName');
    final input = error ? e['input'] : e['input'];
    final args = _map(input, 'input');
    final index = _toolIndexes[callId];
    final previous = index == null ? null : _parts[index];
    final previousCall = previous is ToolCallPart ? previous : null;
    final dynamicTool =
        e['dynamic'] == true || (previousCall?.extra['dynamic'] == true);
    final part = ToolCallPart(
      id: 'tool-$callId',
      callId: callId,
      name: name,
      arguments: args,
      providerExecuted:
          e['providerExecuted'] == true ||
          (previousCall?.providerExecuted ?? false),
      providerOptions: _mergeProviderMetadata(
        previousCall?.providerOptions ?? const {},
        _optionalMap(e, 'providerMetadata'),
      ),
      extra: {if (dynamicTool) 'dynamic': true},
    );
    if (index == null) {
      _toolIndexes[callId] = _parts.length;
      _parts.add(part);
    } else {
      _parts[index] = part;
    }
    if (error) {
      _parts.add(
        ToolResultPart(
          id: 'tool-error-$callId',
          callId: callId,
          output: _string(e, 'errorText'),
          isError: true,
          toolName: name,
          outputKind: 'error_text',
        ),
      );
    }
  }

  void _approvalRequest(Map<String, dynamic> e) {
    final approvalId = _string(e, 'approvalId');
    final callId = _string(e, 'toolCallId');
    if (!_toolIndexes.containsKey(callId)) {
      throw RemoteProtocolException('Approval without tool input $callId');
    }
    _approvalCalls[approvalId] = callId;
    _addPart(
      ApprovalPart(
        id: 'approval-$approvalId',
        callId: callId,
        status: ApprovalStatus.pending,
        approvalId: approvalId,
      ),
    );
    _status = ConversationMessageStatus.pendingApproval;
  }

  void _approvalResponse(Map<String, dynamic> e) {
    final approvalId = _string(e, 'approvalId');
    final callId = _approvalCalls[approvalId];
    if (callId == null) {
      throw RemoteProtocolException('Unknown approval $approvalId');
    }
    final index = _parts.indexWhere(
      (part) => part.id == 'approval-$approvalId',
    );
    if (index < 0) {
      throw RemoteProtocolException('Missing approval part $approvalId');
    }
    _parts[index] = ApprovalPart(
      id: 'approval-$approvalId',
      callId: callId,
      status: e['approved'] == true
          ? ApprovalStatus.approved
          : ApprovalStatus.rejected,
      approvalId: approvalId,
      metadata: _optionalMap(e, 'providerMetadata'),
      extra: {if (e['reason'] case final String reason) 'reason': reason},
    );
    _status = ConversationMessageStatus.streaming;
  }

  void _toolOutput(Map<String, dynamic> e, bool error) {
    final callId = _string(e, 'toolCallId');
    if (!_toolIndexes.containsKey(callId)) {
      throw RemoteProtocolException('Tool output without input $callId');
    }
    _addPart(
      ToolResultPart(
        id: 'result-$callId',
        callId: callId,
        output: error ? _string(e, 'errorText') : _freeze(e['output']),
        isError: error,
        toolName: e['toolName'] as String?,
        outputKind:
            e['outputKind'] as String? ?? (error ? 'error_text' : 'json'),
        preliminary: e['preliminary'] == true,
        isDynamic: e['dynamic'] == true,
        providerOptions: _optionalMap(e, 'providerMetadata'),
      ),
    );
  }

  void _toolOutputDenied(Map<String, dynamic> e) {
    final callId = _string(e, 'toolCallId');
    if (!_toolIndexes.containsKey(callId)) {
      throw RemoteProtocolException('Tool output without input $callId');
    }
    _addPart(
      ToolResultPart(
        id: 'denied-$callId',
        callId: callId,
        output: null,
        isError: true,
        toolName: e['toolName'] as String?,
        outputKind: 'execution_denied',
        executionDeniedReason:
            e['reason'] as String? ?? 'Tool execution denied',
        executionDeniedApprovalId: e['approvalId'] as String?,
        preliminary: e['preliminary'] == true,
        isDynamic: e['dynamic'] == true,
        providerOptions: _optionalMap(e, 'providerMetadata'),
      ),
    );
  }

  void _sourceUrl(Map<String, dynamic> e) => _addPart(
    SourcePart(
      id: 'source-${_string(e, 'sourceId')}',
      uri: _string(e, 'url'),
      title: e['title'] as String?,
      providerMetadata: _optionalMap(e, 'providerMetadata'),
    ),
  );
  void _sourceDocument(Map<String, dynamic> e) => _addPart(
    DocumentSourcePart(
      id: 'source-${_string(e, 'sourceId')}',
      mediaType: _string(e, 'mediaType'),
      title: _string(e, 'title'),
      name: e['filename'] as String?,
      providerMetadata: _optionalMap(e, 'providerMetadata'),
    ),
  );
  void _file(Map<String, dynamic> e, {required bool reasoning}) {
    final url = e['url'] as String?;
    final typedData = _fileData(e['data']);
    final data = typedData ?? (url == null ? null : _fileDataFromUrl(url));
    final uri = data == null && url != null ? url : null;
    final id = 'file-${_parts.length}';
    if (reasoning) {
      _addPart(
        ReasoningFilePart(
          id: id,
          uri: uri,
          data: data,
          mimeType: _string(e, 'mediaType'),
          name: e['filename'] as String?,
          providerOptions: _optionalMap(e, 'providerMetadata'),
        ),
      );
    } else {
      _addPart(
        FilePart(
          id: id,
          uri: uri,
          data: data,
          mimeType: _string(e, 'mediaType'),
          name: e['filename'] as String?,
          providerOptions: _optionalMap(e, 'providerMetadata'),
        ),
      );
    }
  }

  void _unknown(Map<String, dynamic> e) {
    final type = e['type'] as String;
    final n = (_unknownCounts[type] ?? 0) + 1;
    _unknownCounts[type] = n;
    final raw = {...e, 'id': e['id'] is String ? e['id'] : 'remote-$type-$n'};
    _addPart(UnknownPart(id: raw['id'] as String, type: type, raw: raw));
  }

  void _addPart(ConversationPart part) {
    final index = _parts.indexWhere((existing) => existing.id == part.id);
    if (index < 0) {
      _parts.add(part);
    } else {
      _parts[index] = part;
    }
  }

  Conversation _snapshot() {
    final message = ConversationMessage(
      id: _assistantId ?? 'remote-1',
      role: ConversationRole.assistant,
      status: _status,
      parts: List.of(_parts),
      metadata: _messageMetadata,
    );
    final messages = [..._messages.where((m) => m.id != message.id), message];
    return Conversation(
      id: _conversationId,
      messages: messages,
      metadata: _conversationMetadata,
      extra: _conversationExtra,
    );
  }
}

Map<String, dynamic> _optionalMap(Map<String, dynamic> e, String key) {
  final value = e[key];
  if (value == null) return const {};
  return _map(value, key);
}

Map<String, dynamic> _mergeProviderMetadata(
  Map<String, dynamic> previous,
  Map<String, dynamic> next,
) {
  final merged = <String, dynamic>{...previous};
  for (final entry in next.entries) {
    final previousValue = merged[entry.key];
    final nextValue = entry.value;
    if (previousValue is Map && nextValue is Map) {
      merged[entry.key] = _mergeMetadataObjects(previousValue, nextValue);
    } else {
      merged[entry.key] = nextValue;
    }
  }
  return merged;
}

Map<String, dynamic> _mergeMetadataObjects(Map previous, Map next) {
  final merged = <String, dynamic>{};
  for (final entry in previous.entries) {
    if (entry.key is String) merged[entry.key as String] = entry.value;
  }
  for (final entry in next.entries) {
    if (entry.key is! String) continue;
    final previousValue = merged[entry.key];
    final nextValue = entry.value;
    merged[entry.key as String] = previousValue is Map && nextValue is Map
        ? _mergeMetadataObjects(previousValue, nextValue)
        : nextValue;
  }
  return merged;
}

ConversationFileData? _fileData(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const RemoteProtocolException('File data must be an object');
  }
  final kind = value['kind'];
  switch (kind) {
    case 'bytes' || 'base64':
      final encoded = value['base64'];
      if (encoded is! String) {
        throw const RemoteProtocolException('File data requires base64');
      }
      try {
        return ConversationFileBytes(Uint8List.fromList(base64Decode(encoded)));
      } on FormatException {
        throw const RemoteProtocolException('File data has invalid base64');
      }
    case 'provider_reference':
      if (value['namespace'] is! String || value['id'] is! String) {
        throw const RemoteProtocolException(
          'Provider file data requires namespace and id',
        );
      }
      return ConversationFileProviderReference(
        namespace: value['namespace'] as String,
        id: value['id'] as String,
      );
    default:
      throw RemoteProtocolException('Unsupported file data kind $kind');
  }
}

ConversationFileData? _fileDataFromUrl(String url) {
  if (!url.startsWith('data:')) return null;
  final comma = url.indexOf(',');
  if (comma < 0) {
    throw const RemoteProtocolException('Data URL has no payload');
  }
  final header = url.substring(5, comma);
  final payload = url.substring(comma + 1);
  try {
    if (header.endsWith(';base64')) {
      return ConversationFileBytes(Uint8List.fromList(base64Decode(payload)));
    }
    return ConversationFileBytes(Uint8List.fromList(utf8.encode(payload)));
  } on FormatException {
    throw const RemoteProtocolException('Data URL has invalid base64');
  }
}

String _string(Map<String, dynamic> e, String key) {
  final value = e[key];
  if (value is! String || value.isEmpty) {
    throw RemoteProtocolException('Expected non-empty $key');
  }
  return value;
}

String _stringAllowEmpty(Map<String, dynamic> e, String key) {
  final value = e[key];
  if (value is! String) throw RemoteProtocolException('Expected string $key');
  return value;
}

Map<String, dynamic> _map(Object? value, String key) {
  if (value is! Map) throw RemoteProtocolException('Expected object $key');
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw RemoteProtocolException('Expected string keys in $key');
    }
    result[entry.key as String] = _freeze(entry.value);
  }
  return result;
}

class _RemoteJsonState {
  final active = Set<Object>.identity();
  int nodes = 0;
}

Object? _freeze(Object? value, [_RemoteJsonState? state, int depth = 0]) {
  final context = state ?? _RemoteJsonState();
  if (depth > 64) {
    throw const RemoteProtocolException('JSON value is too deeply nested');
  }
  if (++context.nodes > 10000) {
    throw const RemoteProtocolException('JSON value contains too many nodes');
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    if (!context.active.add(value)) {
      throw const RemoteProtocolException('Cyclic JSON value');
    }
    final result = List.unmodifiable(
      value.map((item) => _freeze(item, context, depth + 1)),
    );
    context.active.remove(value);
    return result;
  }
  if (value is Map) {
    if (!context.active.add(value)) {
      throw const RemoteProtocolException('Cyclic JSON value');
    }
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const RemoteProtocolException('JSON object keys must be strings');
      }
      result[entry.key as String] = _freeze(entry.value, context, depth + 1);
    }
    context.active.remove(value);
    return Map<String, dynamic>.unmodifiable(result);
  }
  throw RemoteProtocolException('Unsupported JSON value');
}
