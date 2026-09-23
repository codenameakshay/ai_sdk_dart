import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// OpenAI Responses API implementation of the existing V4 language model
/// contract. It intentionally has no state: callers may continue a response
/// with provider options (`previous_response_id`) or send their own items.
class OpenAIResponsesLanguageModel extends LanguageModelV4 {
  const OpenAIResponsesLanguageModel({
    required this.modelId,
    required this.client,
    required this.headers,
    required this.baseUrl,
    this.queryParameters,
    this.providerName = 'openai',
  });

  @override
  final String modelId;
  final Dio client;
  final Future<Map<String, String>> Function() headers;
  final String baseUrl;
  final Map<String, dynamic>? queryParameters;
  final String providerName;

  @override
  String get provider => providerName;
  @override
  String get specificationVersion => 'v4';

  Map<String, dynamic> _body(
    LanguageModelV4CallOptions options, {
    required bool stream,
  }) {
    final body = <String, dynamic>{
      'model': modelId,
      'input': _input(options.prompt),
      if (options.prompt.system != null) 'instructions': options.prompt.system,
      if (stream) 'stream': true,
      if (options.maxOutputTokens != null)
        'max_output_tokens': options.maxOutputTokens,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.reasoning != LanguageModelV4Reasoning.providerDefault)
        'reasoning': {'effort': options.reasoning.name},
      if (options.tools.isNotEmpty) 'tools': options.tools.map(_tool).toList(),
      if (options.toolChoice != null)
        'tool_choice': _toolChoice(options.toolChoice!),
    };
    if (options.responseFormat
        case final LanguageModelV4JsonResponseFormat format) {
      body['text'] = {
        'format': format.schema == null
            ? {'type': 'json_object'}
            : {
                'type': 'json_schema',
                'name': format.name ?? 'response',
                if (format.description != null)
                  'description': format.description,
                'schema': format.schema,
                'strict': true,
              },
      };
    }
    final extra = options.providerOptions?[provider];
    if (extra != null) {
      final native = Map<String, dynamic>.from(extra);
      final effort = native.remove('reasoning_effort');
      final summary = native.remove('reasoning_summary');
      body.addAll(native);
      if (effort != null || summary != null) {
        body['reasoning'] = {
          if (body['reasoning'] is Map)
            ...Map<String, dynamic>.from(body['reasoning'] as Map),
          'effort': ?effort,
          'summary': ?summary,
        };
      }
    }
    return body;
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    final request = _body(options, stream: false);
    final cancellation = _ResponsesCancellationBridge(options.abortSignal);
    late Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        _endpoint(),
        data: request,
        queryParameters: queryParameters,
        options: Options(
          headers: {...?options.headers, ...await cancellation.race(headers)},
        ),
        cancelToken: cancellation.token,
      );
    } on DioException catch (e) {
      await cancellation.dispose();
      throw await apiErrorFromDioException(e, provider: provider);
    } on AiOperationCancelledError {
      await cancellation.dispose();
      rethrow;
    } catch (_) {
      await cancellation.dispose();
      rethrow;
    }
    await cancellation.dispose();
    final data = response.data;
    if (data == null) throw _invalid(response);
    if (data['error'] != null || data['status'] == 'failed') {
      throw _responseFailure(response, data['error']);
    }
    try {
      final content = <LanguageModelV4ContentPart>[];
      final approvalRequestCallIds = _approvalRequestCallIds(options.prompt);
      for (final raw in (data['output'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final type = item['type']?.toString();
        if (type == 'message') {
          for (final rawPart in (item['content'] as List? ?? const [])) {
            if (rawPart is Map && rawPart['type'] == 'output_text') {
              final text = rawPart['text']?.toString() ?? '';
              if (text.isNotEmpty) {
                content.add(
                  LanguageModelV4TextPart(
                    text: text,
                    providerOptions: {'id': item['id']},
                  ),
                );
              }
              _appendAnnotations(rawPart['annotations'], content.add);
            }
          }
        } else if (type == 'reasoning') {
          final summary = (item['summary'] as List? ?? const [])
              .map((e) => e is Map ? e['text']?.toString() : null)
              .whereType<String>()
              .join();
          if (summary.isNotEmpty || item['encrypted_content'] != null) {
            content.add(
              LanguageModelV4ReasoningPart(
                text: summary,
                providerOptions: {'id': item['id'], 'raw': item},
              ),
            );
          }
        } else if (type == 'function_call') {
          final itemId = _requiredString(item, 'id', 'function_call');
          final callId = _requiredString(item, 'call_id', 'function_call');
          final name = _requiredString(item, 'name', 'function_call');
          content.add(
            LanguageModelV4ToolCallPart(
              toolCallId: callId,
              toolName: name,
              input: _parse(item['arguments']),
              providerOptions: {'item_id': itemId},
            ),
          );
        } else if (_isHostedResponseItem(type)) {
          final approvalId = item['approval_request_id']?.toString();
          content.addAll(
            _hostedItemContent(
              item,
              toolCallId: approvalId == null
                  ? null
                  : approvalRequestCallIds[approvalId],
            ),
          );
        } else if (type == 'mcp_approval_request') {
          final approvalId =
              item['approval_request_id']?.toString() ??
              _requiredString(item, 'id', 'mcp_approval_request');
          content.addAll(_hostedItemContent(item));
          approvalRequestCallIds[approvalId] = _requiredString(
            item,
            'id',
            'mcp_approval_request',
          );
        } else {
          content.add(LanguageModelV4OpaquePart(provider: provider, raw: item));
        }
      }
      final usage = _usage(data['usage']);
      final status = data['status']?.toString();
      return LanguageModelV4GenerateResult(
        content: content,
        finishReason: _finish(
          status,
          (data['incomplete_details'] as Map?)?['reason']?.toString(),
        ),
        warnings: _warnings(options),
        rawFinishReason: status,
        usage: usage,
        request: LanguageModelV4RequestMetadata(body: request),
        response: _metadata(response, data),
      );
    } on Object catch (e) {
      throw _invalid(response, e);
    }
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final request = _body(options, stream: true);
    final cancellation = _ResponsesCancellationBridge(options.abortSignal);
    late Response<ResponseBody> response;
    try {
      response = await client.post<ResponseBody>(
        _endpoint(),
        data: request,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...?options.headers, ...await cancellation.race(headers)},
        ),
        cancelToken: cancellation.token,
      );
    } on DioException catch (e) {
      await cancellation.dispose();
      throw await apiErrorFromDioException(e, provider: provider);
    } catch (_) {
      await cancellation.dispose();
      rethrow;
    }
    final body = response.data;
    if (body == null) {
      await cancellation.dispose();
      throw StateError('$provider Responses stream body is null.');
    }
    final controller = StreamController<LanguageModelV4StreamPart>();
    final bodyRelay = StreamController<List<int>>();
    late StreamSubscription<List<int>> bodySubscription;
    bodySubscription = body.stream.listen(
      bodyRelay.add,
      onError: bodyRelay.addError,
      onDone: bodyRelay.close,
    );
    controller.onCancel = () async {
      cancellation.cancel('stream subscription cancelled');
      try {
        await bodySubscription.cancel();
      } catch (_) {}
      try {
        await bodyRelay.close();
      } catch (_) {}
      await cancellation.dispose();
    };
    final metadataHeaders = response.headers.map.map(
      (k, v) => MapEntry(k, v.join(',')),
    );
    String? responseId;
    String? responseModel;
    LanguageModelV4Usage usage = const LanguageModelV4Usage();
    var terminal = false;
    final functionArguments = <String, StringBuffer>{};
    final emittedFunctionCalls = <String>{};
    final functionIdentity = <String, ({String callId, String name})>{};
    final functionInputStarted = <String>{};
    final functionInputEnded = <String>{};
    final textIds = <String>{};
    final textEnded = <String>{};
    final textItemIdsByOutputIndex = <int, String>{};
    final reasoningIds = <String>{};
    final reasoningRaw = <String, Map<String, dynamic>>{};
    final emittedHostedItems = <String>{};
    final approvalRequestCallIds = _approvalRequestCallIds(options.prompt);
    unawaited(() async {
      try {
        controller.add(StreamPartStreamStart(warnings: _warnings(options)));
        await for (final line in _sse(bodyRelay.stream)) {
          final event = _parseMap(line);
          if (event == null) continue;
          if (options.includeRawChunks) {
            controller.add(StreamPartRaw(rawValue: event));
          }
          final type = event['type']?.toString();
          final responseMap = (event['response'] as Map?)
              ?.cast<String, dynamic>();
          responseId ??=
              responseMap?['id']?.toString() ??
              event['response_id']?.toString();
          responseModel ??= responseMap?['model']?.toString();
          if (type == 'response.output_text.delta') {
            final delta = event['delta']?.toString() ?? '';
            final id = _requiredEventString(
              event,
              'item_id',
              'response.output_text.delta',
            );
            if (textIds.add(id)) {
              controller.add(StreamPartTextStart(id: id));
            }
            if (delta.isNotEmpty) {
              controller.add(StreamPartTextDelta(id: id, delta: delta));
            }
          } else if (type == 'response.output_text.annotation.added') {
            _appendAnnotations([event['annotation']], (part) {
              if (part is LanguageModelV4SourcePart) {
                controller.add(StreamPartSource(source: part));
              } else if (part is LanguageModelV4DocumentSourcePart) {
                controller.add(StreamPartDocumentSource(source: part));
              } else if (part is LanguageModelV4FilePart) {
                controller.add(StreamPartFile(file: part));
              }
            });
          } else if (type == 'response.reasoning_summary_text.delta' ||
              type == 'response.reasoning_text.delta') {
            final delta = event['delta']?.toString() ?? '';
            final id = _requiredEventString(
              event,
              'item_id',
              type ?? 'response.reasoning_text.delta',
            );
            if (reasoningIds.add(id)) {
              controller.add(StreamPartReasoningStart(id: id));
            }
            if (delta.isNotEmpty) {
              controller.add(StreamPartReasoningDelta(id: id, delta: delta));
            }
          } else if (type == 'response.output_item.added') {
            final item = (event['item'] as Map?)?.cast<String, dynamic>();
            if (item?['type'] == 'message') {
              final id = _requiredString(item!, 'id', 'message');
              if (event['output_index'] is int) {
                textItemIdsByOutputIndex[event['output_index'] as int] = id;
              }
              if (textIds.add(id)) {
                controller.add(StreamPartTextStart(id: id));
              }
            } else if (item?['type'] == 'function_call') {
              if (item == null) {
                throw const FormatException(
                  'Responses function_call added event is missing item.',
                );
              }
              final itemId = _requiredString(item, 'id', 'function_call');
              final callId = _requiredString(item, 'call_id', 'function_call');
              final name = _requiredString(item, 'name', 'function_call');
              final previous = functionIdentity[itemId];
              if (previous != null &&
                  (previous.callId != callId || previous.name != name)) {
                throw FormatException(
                  'Responses function_call identity changed for item $itemId.',
                );
              }
              functionIdentity[itemId] = (callId: callId, name: name);
              if (functionInputStarted.add(itemId)) {
                controller.add(
                  StreamPartToolInputStart(id: callId, toolName: name),
                );
              }
            }
          } else if (type == 'response.output_item.done') {
            final item = (event['item'] as Map?)?.cast<String, dynamic>();
            if (item?['type'] == 'message') {
              final outputIndex = event['output_index'];
              final id = outputIndex is int
                  ? textItemIdsByOutputIndex[outputIndex] ??
                        _requiredString(item!, 'id', 'message')
                  : _requiredString(item!, 'id', 'message');
              if (textIds.add(id)) {
                controller.add(StreamPartTextStart(id: id));
              }
              if (textEnded.add(id)) {
                controller.add(StreamPartTextEnd(id: id));
              }
            }
            if (item?['type'] == 'reasoning' && item?['id'] != null) {
              final id = item!['id'].toString();
              reasoningRaw[id] = item;
              if (reasoningIds.add(id)) {
                controller.add(StreamPartReasoningStart(id: id));
              }
            }
            if (item?['type'] == 'function_call') {
              if (item == null) {
                throw const FormatException(
                  'Responses function_call done event is missing item.',
                );
              }
              final itemId = _requiredString(item, 'id', 'function_call');
              final callId = _requiredString(item, 'call_id', 'function_call');
              final name = _requiredString(item, 'name', 'function_call');
              final previous = functionIdentity[itemId];
              if (previous != null &&
                  (previous.callId != callId || previous.name != name)) {
                throw FormatException(
                  'Responses function_call identity changed for item $itemId.',
                );
              }
              functionIdentity[itemId] = (callId: callId, name: name);
              if (functionInputStarted.add(itemId)) {
                controller.add(
                  StreamPartToolInputStart(id: callId, toolName: name),
                );
              }
              if (functionInputEnded.add(itemId)) {
                controller.add(StreamPartToolInputEnd(id: callId));
              }
              if (!emittedFunctionCalls.add(callId)) continue;
              controller.add(
                StreamPartToolCall(
                  toolCall: LanguageModelV4ToolCallPart(
                    toolCallId: callId,
                    toolName: name,
                    input: _parse(item['arguments']),
                    providerOptions: {'item_id': itemId},
                  ),
                ),
              );
            } else if (item != null &&
                (_isHostedResponseItem(item['type']?.toString()) ||
                    item['type']?.toString() == 'mcp_approval_request')) {
              final itemId = item['id']?.toString();
              if (itemId == null || itemId.isEmpty) {
                throw const FormatException(
                  'Responses hosted output item is missing required string field "id".',
                );
              }
              if (emittedHostedItems.add(itemId)) {
                final approvalId = item['approval_request_id']?.toString();
                final hostedParts = _hostedItemContent(
                  item,
                  toolCallId: approvalId == null
                      ? null
                      : approvalRequestCallIds[approvalId],
                );
                for (final part in hostedParts) {
                  switch (part) {
                    case final LanguageModelV4ToolCallPart call:
                      controller.add(StreamPartToolCall(toolCall: call));
                    case final LanguageModelV4ToolResultPart result:
                      controller.add(
                        StreamPartToolResult(
                          toolResult: result,
                          preliminary: _isPreliminaryHostedItem(item),
                        ),
                      );
                    case final LanguageModelV4SourcePart source:
                      controller.add(StreamPartSource(source: source));
                    case final LanguageModelV4ToolApprovalRequestPart approval:
                      controller.add(
                        StreamPartToolApprovalRequest(
                          approvalRequest: approval,
                        ),
                      );
                    default:
                      break;
                  }
                }
                if (item['type'] == 'mcp_approval_request' &&
                    approvalId != null) {
                  approvalRequestCallIds[approvalId] = itemId;
                }
              }
            } else if (item != null && item['type'] != 'reasoning') {
              controller.add(
                StreamPartOpaque(
                  opaque: LanguageModelV4OpaquePart(
                    provider: provider,
                    raw: item,
                  ),
                ),
              );
            }
          } else if (type == 'response.function_call_arguments.delta') {
            final id = _requiredEventString(
              event,
              'item_id',
              'function_call_arguments.delta',
            );
            final identity = functionIdentity[id];
            if (identity == null) {
              throw FormatException(
                'Responses function_call_arguments.delta references unknown '
                'item $id.',
              );
            }
            final delta = event['delta']?.toString() ?? '';
            final buffer = functionArguments.putIfAbsent(id, StringBuffer.new);
            if (functionInputStarted.add(id)) {
              controller.add(
                StreamPartToolInputStart(
                  id: identity.callId,
                  toolName: identity.name,
                ),
              );
            }
            buffer.write(delta);
            if (delta.isNotEmpty) {
              controller.add(
                StreamPartToolInputDelta(id: identity.callId, delta: delta),
              );
            }
          } else if (type == 'response.function_call_arguments.done') {
            final id = _requiredEventString(
              event,
              'item_id',
              'function_call_arguments.done',
            );
            final identity = functionIdentity[id];
            if (identity == null) {
              throw FormatException(
                'Responses function_call_arguments.done references unknown '
                'item $id.',
              );
            }
            final args =
                event['arguments']?.toString() ??
                functionArguments[id]?.toString() ??
                '{}';
            if (functionInputEnded.add(id)) {
              controller.add(StreamPartToolInputEnd(id: identity.callId));
            }
            final callId = identity.callId;
            if (emittedFunctionCalls.add(callId)) {
              controller.add(
                StreamPartToolCall(
                  toolCall: LanguageModelV4ToolCallPart(
                    toolCallId: callId,
                    toolName: identity.name,
                    input: _parse(args),
                    providerOptions: {'item_id': id},
                  ),
                ),
              );
            }
          } else if (type == 'response.completed' ||
              type == 'response.incomplete' ||
              type == 'response.failed') {
            usage = _usage(responseMap?['usage']);
            for (final id in textIds) {
              if (textEnded.add(id)) {
                controller.add(StreamPartTextEnd(id: id));
              }
            }
            for (final id in reasoningIds) {
              controller.add(
                StreamPartReasoningEnd(
                  id: id,
                  providerMetadata: reasoningRaw[id] == null
                      ? null
                      : {
                          provider: {'raw': reasoningRaw[id]},
                        },
                ),
              );
            }
            final status =
                responseMap?['status']?.toString() ??
                (type == 'response.completed' ? 'completed' : 'failed');
            if (type == 'response.failed') {
              controller.add(
                StreamPartError(
                  error: _responseFailure(response, responseMap?['error']),
                ),
              );
            }
            controller.add(
              StreamPartResponseMetadata(
                metadata: LanguageModelV4ResponseMetadata(
                  id: responseId,
                  modelId: responseModel,
                  timestamp: DateTime.now().toUtc(),
                  headers: metadataHeaders,
                  body: responseMap,
                ),
              ),
            );
            controller.add(
              StreamPartFinish(
                finishReason: _finish(
                  status,
                  (responseMap?['incomplete_details'] as Map?)?['reason']
                      ?.toString(),
                ),
                rawFinishReason: status,
                usage: usage,
              ),
            );
            terminal = true;
          } else if (type == 'error') {
            controller.add(
              StreamPartError(error: _responseFailure(response, event)),
            );
            controller.add(
              const StreamPartFinish(
                finishReason: LanguageModelV4FinishReason.error,
                rawFinishReason: 'error',
              ),
            );
            terminal = true;
          }
        }
        if (!terminal) {
          controller.add(
            const StreamPartError(
              error: FormatException(
                'Responses stream ended before a terminal event.',
              ),
            ),
          );
          controller.add(
            StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.error,
              rawFinishReason: 'truncated',
              usage: usage,
            ),
          );
        }
      } catch (e) {
        cancellation.cancel('stream failure');
        if (!controller.isClosed) controller.add(StreamPartError(error: e));
      } finally {
        try {
          await bodySubscription.cancel();
        } catch (_) {}
        try {
          await bodyRelay.close();
        } catch (_) {}
        await cancellation.dispose();
        if (!controller.isClosed) await controller.close();
      }
    }());
    return LanguageModelV4StreamResult(
      stream: controller.stream,
      request: LanguageModelV4RequestMetadata(body: request),
      response: LanguageModelV4ResponseMetadata(
        id: responseId,
        modelId: responseModel,
        headers: metadataHeaders,
      ),
    );
  }

  String _endpoint() => baseUrl.endsWith('/responses')
      ? baseUrl
      : '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/responses';
  List<Map<String, dynamic>> _input(LanguageModelV4Prompt prompt) {
    final out = <Map<String, dynamic>>[];
    final emittedRawItemIds = <String>{};
    void addRawItem(Map raw) {
      final item = raw.cast<String, dynamic>();
      final id = item['id'];
      if (id is String && !emittedRawItemIds.add(id)) return;
      out.add(item);
    }

    for (final message in prompt.messages) {
      final content = <Map<String, dynamic>>[];
      void flushContent() {
        if (content.isNotEmpty) {
          out.add({
            'role': message.role.name,
            'content': [...content],
          });
          content.clear();
        }
      }

      for (final part in message.content) {
        if (part case LanguageModelV4ToolCallPart call) {
          flushContent();
          final raw = call.providerOptions?[provider]?['raw'];
          if (raw is Map) {
            addRawItem(raw);
            continue;
          }
          out.add({
            'type': 'function_call',
            if (call.providerOptions?['item_id'] != null)
              'id': call.providerOptions!['item_id'],
            'call_id': call.toolCallId,
            'name': call.toolName,
            'arguments': jsonEncode(call.input),
          });
        } else if (part case LanguageModelV4ReasoningPart reasoning) {
          flushContent();
          final raw =
              reasoning.providerOptions?['raw'] ??
              (reasoning.providerOptions?[provider] as Map?)?['raw'];
          if (raw is Map) addRawItem(raw);
        } else if (part case LanguageModelV4ToolResultPart result) {
          flushContent();
          final raw = result.providerOptions?[provider]?['raw'];
          if (raw is Map) {
            addRawItem(raw);
            continue;
          }
          if (_toolResultInput(result) case final wire?) out.add(wire);
        } else if (part case LanguageModelV4ToolApprovalResponse approval) {
          flushContent();
          out.add({
            'type': 'mcp_approval_response',
            'approval_request_id': approval.approvalId,
            'approve': approval.approved,
            if (approval.reason != null) 'reason': approval.reason,
          });
        } else if (part case LanguageModelV4TextPart(:final text)) {
          final extension = part.providerOptions?[provider];
          if (extension?['type'] == 'response_item_extension' &&
              extension?['raw'] is Map) {
            flushContent();
            addRawItem(extension!['raw'] as Map);
            continue;
          }
          content.add({'type': 'input_text', 'text': text});
        } else if (part case LanguageModelV4OpaquePart(
          :final provider,
          :final raw,
        )) {
          if (provider == this.provider && raw is Map) {
            flushContent();
            addRawItem(raw);
          }
        } else if (part case LanguageModelV4ImagePart(
          :final image,
          :final mediaType,
        )) {
          final encoded = dataContentToBase64(image);
          final url = image is DataContentUrl
              ? (image).url.toString()
              : (encoded == null
                    ? null
                    : 'data:${mediaType ?? 'image/png'};base64,$encoded');
          if (url != null) {
            content.add({'type': 'input_image', 'image_url': url});
          }
        } else if (part case LanguageModelV4FilePart(
          :final data,
          :final mediaType,
          :final filename,
        )) {
          if (data case DataContentProviderReference(
            :final namespace,
            :final id,
          )) {
            if (namespace != 'openai') {
              throw ArgumentError.value(
                namespace,
                'namespace',
                'OpenAI Responses cannot serialize another provider reference',
              );
            }
            content.add({'type': 'input_file', 'file_id': id});
            continue;
          }
          final encoded = dataContentToBase64(data);
          final url = data is DataContentUrl
              ? (data).url.toString()
              : (encoded == null ? null : 'data:$mediaType;base64,$encoded');
          if (url != null) {
            content.add({
              'type': 'input_file',
              if (data is DataContentUrl) 'file_url': url,
              if (data is! DataContentUrl) ...{
                'file_data': url,
                'filename': filename ?? 'data',
              },
            });
          }
        } else if (part case LanguageModelV4ReasoningFilePart reasoningFile) {
          flushContent();
          final raw = reasoningFile.providerOptions?[provider]?['raw'];
          if (raw is Map) {
            addRawItem(raw);
          } else {
            throw UnsupportedError(
              'OpenAI Responses cannot replay a reasoning file without '
              'provider raw metadata.',
            );
          }
        } else if (part case LanguageModelV4DocumentSourcePart document) {
          flushContent();
          final raw = document.providerMetadata?[provider]?['raw'];
          if (raw is Map) {
            addRawItem(raw);
          } else {
            throw UnsupportedError(
              'OpenAI Responses cannot replay a document source without '
              'provider raw metadata.',
            );
          }
        }
      }
      flushContent();
    }
    return out;
  }

  Map<String, dynamic>? _toolResultInput(LanguageModelV4ToolResultPart result) {
    if (result.toolName == 'computer') {
      final output = _computerCallOutput(result.output);
      return {
        'type': 'computer_call_output',
        'call_id': result.toolCallId,
        'output': output,
      };
    }
    final output = switch (result.output) {
      ToolResultOutputText(:final text) => text,
      ToolResultOutputErrorText(:final text) => text,
      ToolResultOutputJson(:final value) => jsonEncode(value),
      ToolResultOutputErrorJson(:final value) => jsonEncode(value),
      ToolResultOutputExecutionDenied(:final reason, :final approvalId) =>
        approvalId == null ? reason : null,
      ToolResultOutputContent(:final parts) => _responsesContentOutput(parts),
    };
    if (output == null) return null;
    return {
      'type': 'function_call_output',
      'call_id': result.toolCallId,
      'output': output,
    };
  }

  List<Map<String, dynamic>> _responsesContentOutput(
    List<LanguageModelV4ContentPart> parts,
  ) => parts.map(_responsesContentOutputPart).toList(growable: false);

  Map<String, dynamic> _responsesContentOutputPart(
    LanguageModelV4ContentPart part,
  ) {
    if (part case LanguageModelV4TextPart(:final text)) {
      return {'type': 'input_text', 'text': text};
    }
    if (part case LanguageModelV4ImagePart image) {
      final reference = _responsesImageReference(image);
      if (reference == null) {
        throw UnsupportedError(
          'OpenAI Responses cannot serialize this tool image content.',
        );
      }
      return {
        'type': 'input_image',
        ...reference,
        ..._imageDetail(image.providerOptions),
      };
    }
    if (part case LanguageModelV4FilePart file) {
      final topLevel = file.mediaType.split('/').first;
      if (topLevel == 'image') {
        final reference = _responsesImageReference(
          LanguageModelV4ImagePart(
            image: file.data,
            mediaType: file.mediaType,
            providerOptions: file.providerOptions,
          ),
        );
        if (reference == null) {
          throw UnsupportedError(
            'OpenAI Responses cannot serialize this tool image file.',
          );
        }
        return {
          'type': 'input_image',
          ...reference,
          ..._imageDetail(file.providerOptions),
        };
      }
      final data = file.data;
      if (data case DataContentProviderReference(:final namespace, :final id)) {
        if (namespace != 'openai') {
          throw ArgumentError.value(
            namespace,
            'namespace',
            'OpenAI Responses cannot serialize another provider reference',
          );
        }
        return {'type': 'input_file', 'file_id': id};
      }
      if (data case DataContentUrl(:final url)) {
        return {'type': 'input_file', 'file_url': url.toString()};
      }
      final encoded = dataContentToBase64(data);
      if (encoded == null) {
        throw UnsupportedError(
          'OpenAI Responses cannot serialize this tool file.',
        );
      }
      return {
        'type': 'input_file',
        'file_data': 'data:${file.mediaType};base64,$encoded',
        'filename': file.filename ?? 'data',
      };
    }
    throw UnsupportedError(
      'OpenAI Responses cannot serialize ${part.runtimeType} in tool content.',
    );
  }

  Map<String, dynamic>? _computerCallOutput(
    LanguageModelV4ToolResultOutput output,
  ) {
    if (output case ToolResultOutputJson(:final value)) {
      return _validatedComputerOutput(value);
    }
    if (output case ToolResultOutputErrorJson(:final value)) {
      return _validatedComputerOutput(value);
    }
    if (output case ToolResultOutputContent(:final parts)) {
      final images = parts.whereType<LanguageModelV4ImagePart>().toList();
      if (images.length != 1 || parts.length != 1) {
        throw UnsupportedError(
          'Computer results require exactly one screenshot image.',
        );
      }
      final reference = _responsesImageReference(images.single);
      if (reference == null) {
        throw UnsupportedError(
          'Computer screenshot image is not serializable.',
        );
      }
      return {
        'type': 'computer_screenshot',
        ...reference,
        ..._imageDetail(images.single.providerOptions),
      };
    }
    throw UnsupportedError(
      'Computer results require structured screenshot JSON or image content.',
    );
  }

  Map<String, dynamic> _validatedComputerOutput(Object? value) {
    if (value is! Map) {
      throw FormatException('Computer output must be a JSON object.');
    }
    final output = value.cast<String, dynamic>();
    if (output['type'] != 'computer_screenshot') {
      throw FormatException('Computer output must be a screenshot.');
    }
    final imageUrl = output['image_url'];
    final fileId = output['file_id'];
    if ((imageUrl is! String || imageUrl.isEmpty) &&
        (fileId is! String || fileId.isEmpty)) {
      throw FormatException(
        'Computer screenshot requires image_url or file_id.',
      );
    }
    if ((imageUrl != null && imageUrl is! String) ||
        (fileId != null && fileId is! String)) {
      throw FormatException('Computer screenshot references must be strings.');
    }
    if (output['detail'] != null && output['detail'] is! String) {
      throw FormatException('Computer screenshot detail must be a string.');
    }
    if (output['acknowledged_safety_checks'] case final checks?) {
      if (checks is! List || checks.any((check) => check is! Map)) {
        throw FormatException('Computer safety checks must be JSON objects.');
      }
    }
    return output;
  }

  Map<String, dynamic> _imageDetail(Map<String, dynamic>? providerOptions) {
    final options = providerOptions?[provider];
    final detail = options is Map
        ? options['detail'] ?? options['imageDetail']
        : null;
    return detail is String ? {'detail': detail} : const {};
  }

  Map<String, dynamic>? _responsesImageReference(
    LanguageModelV4ImagePart image,
  ) {
    final data = image.image;
    if (data is DataContentUrl) {
      return {'image_url': data.url.toString()};
    }
    if (data case DataContentProviderReference(:final namespace, :final id)) {
      if (namespace == 'openai') return {'file_id': id};
      return null;
    }
    final encoded = dataContentToBase64(data);
    if (encoded == null) return null;
    return {
      'image_url': 'data:${image.mediaType ?? 'image/png'};base64,$encoded',
    };
  }

  List<LanguageModelV4Warning> _warnings(LanguageModelV4CallOptions options) =>
      [
        if (options.stopSequences.isNotEmpty)
          const LanguageModelV4UnsupportedWarning(feature: 'stopSequences'),
        if (options.topK != null)
          const LanguageModelV4UnsupportedWarning(feature: 'topK'),
        if (options.presencePenalty != null)
          const LanguageModelV4UnsupportedWarning(feature: 'presencePenalty'),
        if (options.frequencyPenalty != null)
          const LanguageModelV4UnsupportedWarning(feature: 'frequencyPenalty'),
        if (options.seed != null)
          const LanguageModelV4UnsupportedWarning(feature: 'seed'),
      ];

  Map<String, dynamic> _tool(LanguageModelV4Tool tool) => switch (tool) {
    LanguageModelV4FunctionTool() => {
      'type': 'function',
      'name': tool.name,
      if (tool.description != null) 'description': tool.description,
      'parameters': tool.inputSchema,
      if (tool.strict != null) 'strict': tool.strict,
    },
    LanguageModelV4ProviderDefinedTool() => {'type': tool.id, ...tool.args},
  };
  Object _toolChoice(LanguageModelV4ToolChoice choice) => switch (choice) {
    ToolChoiceAuto() => 'auto',
    ToolChoiceNone() => 'none',
    ToolChoiceRequired() => 'required',
    ToolChoiceSpecific(:final toolName) => {
      'type': 'function',
      'name': toolName,
    },
  };
}

LanguageModelV4ResponseMetadata _metadata(
  Response<Map<String, dynamic>> r,
  Map<String, dynamic> d,
) => LanguageModelV4ResponseMetadata(
  id: d['id']?.toString(),
  modelId: d['model']?.toString(),
  timestamp: DateTime.now().toUtc(),
  headers: r.headers.map.map((k, v) => MapEntry(k, v.join(','))),
  body: d,
);
LanguageModelV4Usage _usage(Object? raw) {
  final m = raw is Map
      ? raw.cast<String, dynamic>()
      : const <String, dynamic>{};
  final inT = m['input_tokens'] as int?;
  final outT = m['output_tokens'] as int?;
  final reason =
      (m['output_tokens_details'] as Map?)?['reasoning_tokens'] as int?;
  return LanguageModelV4Usage(
    inputTokens: LanguageModelV4InputTokenUsage(total: inT),
    outputTokens: LanguageModelV4OutputTokenUsage(
      total: outT,
      reasoning: reason,
    ),
    raw: raw,
  );
}

LanguageModelV4FinishReason _finish(
  String? status, [
  String? incompleteReason,
]) => switch (status) {
  'completed' => LanguageModelV4FinishReason.stop,
  'incomplete' =>
    incompleteReason == 'content_filter'
        ? LanguageModelV4FinishReason.contentFilter
        : LanguageModelV4FinishReason.length,
  'failed' => LanguageModelV4FinishReason.error,
  _ => LanguageModelV4FinishReason.unknown,
};
Object _parse(Object? value) {
  if (value is Map || value is List) return value!;
  try {
    return jsonDecode(value?.toString() ?? '{}');
  } catch (_) {
    return value?.toString() ?? '{}';
  }
}

String _requiredString(
  Map<String, dynamic> object,
  String key,
  String itemType,
) {
  final value = object[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Responses $itemType is missing required string field "$key".',
    );
  }
  return value;
}

String _requiredEventString(
  Map<String, dynamic> event,
  String key,
  String eventType,
) {
  final value = event[key];
  if (value is! String || value.isEmpty) {
    throw FormatException(
      'Responses $eventType event is missing required string field "$key".',
    );
  }
  return value;
}

Map<String, dynamic>? _parseMap(String value) {
  try {
    final p = jsonDecode(value);
    return p is Map ? p.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

Stream<String> _sse(Stream<List<int>> stream) async* {
  var buffer = '';
  await for (final chunk in stream.transform(utf8.decoder)) {
    buffer += chunk;
    final lines = buffer.split('\n');
    buffer = lines.removeLast();
    for (final line in lines) {
      if (line.startsWith('data:')) yield line.substring(5).trim();
    }
  }
  if (buffer.startsWith('data:')) yield buffer.substring(5).trim();
}

void _appendAnnotations(
  Object? raw,
  void Function(LanguageModelV4ContentPart part) add,
) {
  if (raw is! List) return;
  for (final value in raw.whereType<Map>()) {
    final annotation = value.cast<String, dynamic>();
    if (annotation['type'] == 'url_citation' && annotation['url'] != null) {
      add(
        LanguageModelV4SourcePart(
          id: annotation['id']?.toString() ?? 'source-${annotation['url']}',
          url: annotation['url'].toString(),
          title: annotation['title']?.toString(),
          providerMetadata: {'openai': annotation},
        ),
      );
    }
    if (annotation['type'] == 'file_citation') {
      final fileId = annotation['file_id']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        final title =
            annotation['filename']?.toString() ??
            annotation['title']?.toString() ??
            fileId;
        add(
          LanguageModelV4DocumentSourcePart(
            id: fileId,
            mediaType:
                annotation['media_type']?.toString() ??
                'application/octet-stream',
            title: title,
            filename: annotation['filename']?.toString(),
            providerMetadata: {'openai': annotation},
          ),
        );
      }
    }
  }
}

bool _isHostedResponseItem(String? type) => switch (type) {
  'web_search_call' ||
  'file_search_call' ||
  'code_interpreter_call' ||
  'image_generation_call' ||
  'computer_call' ||
  'mcp_call' => true,
  _ => false,
};

Map<String, String> _approvalRequestCallIds(LanguageModelV4Prompt prompt) {
  final mapping = <String, String>{};
  for (final message in prompt.messages) {
    if (message.role != LanguageModelV4Role.assistant) continue;
    for (final part in message.content) {
      if (part case LanguageModelV4ToolApprovalRequestPart request) {
        mapping[request.approvalId] = request.toolCall.toolCallId;
      }
      if (part case LanguageModelV4ToolCallPart call) {
        final namespaced = call.providerOptions?['openai'];
        if (namespaced is Map && namespaced['approval_request_id'] is String) {
          mapping[namespaced['approval_request_id'] as String] =
              call.toolCallId;
          continue;
        }
        final raw = namespaced is Map ? namespaced['raw'] : null;
        if (raw is Map && raw['approval_request_id'] is String) {
          mapping[raw['approval_request_id'] as String] = call.toolCallId;
        }
      }
    }
  }
  return mapping;
}

List<LanguageModelV4ContentPart> _hostedItemContent(
  Map<String, dynamic> item, {
  String? toolCallId,
}) {
  final type = item['type']?.toString();
  final itemId = _requiredString(item, 'id', type ?? 'hosted item');
  final computerCallId = item['call_id'];
  final isClientComputerCall =
      type == 'computer_call' &&
      computerCallId is String &&
      computerCallId.isNotEmpty;
  final id = isClientComputerCall ? computerCallId : itemId;
  final toolName = switch (type) {
    'web_search_call' => 'web_search_preview',
    'file_search_call' => 'file_search',
    'code_interpreter_call' => 'code_interpreter',
    'image_generation_call' => 'image_generation',
    'computer_call' => isClientComputerCall ? 'computer' : 'computer_use',
    'mcp_call' => 'mcp.${_requiredString(item, 'name', 'mcp_call')}',
    'mcp_approval_request' =>
      'mcp.${_requiredString(item, 'name', 'mcp_approval_request')}',
    _ => throw FormatException(
      'Unsupported hosted Responses item type: $type.',
    ),
  };
  final raw = Map<String, dynamic>.from(item);
  final effectiveToolCallId = toolCallId ?? id;
  final providerOptions = <String, dynamic>{
    'item_id': itemId,
    'openai': <String, dynamic>{
      'item_id': itemId,
      if (!isClientComputerCall) 'provider_executed': true,
      if (item['approval_request_id'] != null)
        'approval_request_id': item['approval_request_id'],
      'raw': raw,
    },
  };
  final input = switch (type) {
    'web_search_call' => <String, dynamic>{},
    'file_search_call' => <String, dynamic>{},
    'code_interpreter_call' => <String, dynamic>{
      'code': item['code'],
      'container_id': item['container_id'],
    },
    'image_generation_call' => <String, dynamic>{},
    'computer_call' => <String, dynamic>{
      if (item['action'] != null) 'action': item['action'],
      if (item['actions'] != null) 'actions': item['actions'],
      if (item['pending_safety_checks'] != null)
        'pending_safety_checks': item['pending_safety_checks'],
    },
    'mcp_call' || 'mcp_approval_request' =>
      item['arguments'] is String
          ? item['arguments'] as String
          : _parse(item['arguments']),
    _ => <String, dynamic>{},
  };
  final parts = <LanguageModelV4ContentPart>[
    LanguageModelV4ToolCallPart(
      toolCallId: effectiveToolCallId,
      toolName: toolName,
      input: input,
      providerOptions: providerOptions,
      providerExecuted: !isClientComputerCall,
    ),
  ];

  if (type == 'mcp_approval_request') {
    final approvalId =
        item['approval_request_id']?.toString() ??
        _requiredString(item, 'id', 'mcp_approval_request');
    parts.add(
      LanguageModelV4ToolApprovalRequestPart(
        approvalId: approvalId,
        toolCall: parts.single as LanguageModelV4ToolCallPart,
      ),
    );
    return parts;
  }

  if (isClientComputerCall) return parts;

  final output = switch (type) {
    'web_search_call' => <String, dynamic>{
      'action': item['action'],
      'status': item['status'],
    },
    'file_search_call' => <String, dynamic>{
      'queries': item['queries'],
      'results': item['results'],
      'status': item['status'],
    },
    'code_interpreter_call' => <String, dynamic>{
      'outputs': item['outputs'],
      'status': item['status'],
    },
    'image_generation_call' => <String, dynamic>{
      'result': item['result'],
      'status': item['status'],
    },
    'computer_call' => <String, dynamic>{
      'action': item['action'],
      'actions': item['actions'],
      'status': item['status'],
    },
    'mcp_call' => <String, dynamic>{
      'server_label': item['server_label'],
      'name': item['name'],
      'arguments': item['arguments'],
      if (item['output'] != null) 'output': item['output'],
      if (item['error'] != null) 'error': item['error'],
      'status': item['status'],
    },
    _ => <String, dynamic>{},
  };
  final resultOptions = <String, dynamic>{
    'openai': <String, dynamic>{
      'item_id': id,
      'provider_executed': true,
      'raw': raw,
    },
  };
  parts.add(
    LanguageModelV4ToolResultPart(
      toolCallId: effectiveToolCallId,
      toolName: toolName,
      output: ToolResultOutputText(jsonEncode(output)),
      isError: item['error'] != null || item['status'] == 'failed',
      providerOptions: resultOptions,
    ),
  );
  if (type == 'web_search_call') {
    final sources = ((item['action'] as Map?)?['sources'] as List? ?? const [])
        .whereType<Map>()
        .map((source) => source.cast<String, dynamic>())
        .where((source) => source['url'] != null)
        .map(
          (source) => LanguageModelV4SourcePart(
            id: source['id']?.toString() ?? 'source-${source['url']}',
            url: source['url'].toString(),
            title: source['title']?.toString(),
            providerMetadata: {'openai': source},
          ),
        );
    parts.addAll(sources);
  }
  return parts;
}

bool _isPreliminaryHostedItem(Map<String, dynamic> item) =>
    item['status'] == 'in_progress';

AiApiCallError _responseFailure<T>(Response<T> response, Object? error) {
  final fields = error is Map ? error : const <String, Object?>{};
  return AiApiCallError(
    fields['message'] is String
        ? fields['message'] as String
        : 'OpenAI Responses response failed.',
    statusCode: response.statusCode,
    url: response.requestOptions.uri.toString(),
    code: fields['code']?.toString(),
    type: fields['type']?.toString(),
    responseHeaders: response.headers.map.map(
      (key, values) => MapEntry(key, values.join(',')),
    ),
    responseBody: jsonEncode({'error': error}),
  );
}

AiApiCallError _invalid<T>(Response<T> response, [Object? cause]) =>
    AiApiCallError(
      'OpenAI returned an invalid Responses response.',
      statusCode: response.statusCode,
      url: response.requestOptions.uri.toString(),
      cause: cause,
    );

class _ResponsesCancellationBridge {
  _ResponsesCancellationBridge(this.signal)
    : _scope = DioCancellationScope(signal, alwaysCreateToken: true) {
    token = _scope.token!;
  }

  final DioCancellationScope _scope;
  final AbortSignal? signal;
  late final CancelToken token;

  Future<T> race<T>(Future<T> Function() operation) {
    return runWithAbortSignal(operation, signal);
  }

  void cancel(String reason) {
    if (!token.isCancelled) token.cancel(reason);
  }

  Future<void> dispose() => _scope.dispose();
}
