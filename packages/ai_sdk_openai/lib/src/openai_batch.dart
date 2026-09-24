import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'openai_files.dart';
import 'openai_errors.dart';
import 'openai_request_scope.dart';

class OpenAIBatchException implements Exception {
  const OpenAIBatchException(this.message);
  final String message;
  @override
  String toString() => 'OpenAIBatchException: $message';
}

class OpenAIBatchSubmissionException implements Exception {
  const OpenAIBatchSubmissionException(this.inputFile, this.cause);
  final DataContentProviderReference inputFile;
  final Object cause;
  @override
  String toString() => 'OpenAIBatchSubmissionException: $cause';
}

class OpenAIBatchInput {
  const OpenAIBatchInput({
    required this.customId,
    required this.model,
    required this.input,
    this.options,
  });
  final String customId;
  final String model;
  final Object input;
  final Map<String, dynamic>? options;

  Map<String, dynamic> toJson() => {
    'custom_id': customId,
    'method': 'POST',
    'url': '/v1/responses',
    'body': {'model': model, 'input': input, ...?options},
  };
}

enum OpenAIBatchStatus {
  validating,
  failed,
  inProgress,
  finalizing,
  completed,
  expired,
  cancelling,
  cancelled,
  unknown;

  static OpenAIBatchStatus parse(String value) => switch (value) {
    'validating' => validating,
    'failed' => failed,
    'in_progress' => inProgress,
    'finalizing' => finalizing,
    'completed' => completed,
    'expired' => expired,
    'cancelling' => cancelling,
    'cancelled' => cancelled,
    _ => unknown,
  };
}

class OpenAIBatch {
  const OpenAIBatch({
    required this.id,
    required this.status,
    required this.rawStatus,
    this.inputFileId,
    this.outputFileId,
    this.errorFileId,
    this.totalRequests,
    this.completedRequests,
    this.failedRequests,
  });

  final String id;
  final OpenAIBatchStatus status;
  final String rawStatus;
  final DataContentProviderReference? inputFileId;
  final DataContentProviderReference? outputFileId;
  final DataContentProviderReference? errorFileId;
  final int? totalRequests;
  final int? completedRequests;
  final int? failedRequests;

  factory OpenAIBatch.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final raw = json['status'];
    if (id is! String || id.isEmpty || raw is! String || raw.isEmpty) {
      throw const OpenAIBatchException('Malformed batch metadata');
    }
    final counts = json['request_counts'];
    if (counts != null && counts is! Map) {
      throw const OpenAIBatchException('Malformed batch request counts');
    }
    return OpenAIBatch(
      id: id,
      status: OpenAIBatchStatus.parse(raw),
      rawStatus: raw,
      inputFileId: _reference(json['input_file_id']),
      outputFileId: _reference(json['output_file_id']),
      errorFileId: _reference(json['error_file_id']),
      totalRequests: _requiredInteger(counts, 'total'),
      completedRequests: _requiredInteger(counts, 'completed'),
      failedRequests: _requiredInteger(counts, 'failed'),
    );
  }
}

class OpenAIBatchResult {
  const OpenAIBatchResult({
    required this.customId,
    required this.statusCode,
    this.requestId,
    this.response,
    this.error,
  });
  final String customId;
  final int? statusCode;
  final String? requestId;
  final Map<String, dynamic>? response;
  final Map<String, dynamic>? error;

  factory OpenAIBatchResult.fromJson(Map<String, dynamic> json) {
    final id = json['custom_id'];
    final response = json['response'];
    final code = response is Map ? response['status_code'] : null;
    final error = json['error'];
    if (id is! String ||
        id.isEmpty ||
        (code != null && code is! int) ||
        (response != null && response is! Map) ||
        (response == null && error is! Map) ||
        (response is Map && response['status_code'] is! int) ||
        (error != null && error is! Map)) {
      throw const OpenAIBatchException('Malformed batch result');
    }
    return OpenAIBatchResult(
      customId: id,
      statusCode: code,
      requestId: response is Map && response['request_id'] is String
          ? response['request_id'] as String
          : null,
      response: response is Map
          ? Map<String, dynamic>.from(response.cast<String, dynamic>())
          : null,
      error: error is Map
          ? Map<String, dynamic>.from(error.cast<String, dynamic>())
          : null,
    );
  }
}

class OpenAIBatchPage extends Iterable<OpenAIBatch> {
  const OpenAIBatchPage({
    required this.items,
    required this.hasMore,
    this.lastId,
  });
  final List<OpenAIBatch> items;
  final bool hasMore;
  final String? lastId;
  @override
  Iterator<OpenAIBatch> get iterator => items.iterator;
}

class OpenAIBatches {
  const OpenAIBatches({
    required this.client,
    required this.headers,
    required this.baseUrl,
    required this.files,

    /// Monotonic clock seam for hosts that need deterministic deadline control.
    this.stopwatchFactory = Stopwatch.new,
  });
  final Dio client;
  final Future<Map<String, String>> Function() headers;
  final String baseUrl;
  final OpenAIFiles files;
  final Stopwatch Function() stopwatchFactory;

  Future<OpenAIBatch> create(
    List<OpenAIBatchInput> inputs, {
    Map<String, String>? metadata,
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    final stopwatch = stopwatchFactory()..start();
    _validateInputs(inputs);
    final lines = inputs.map((input) => jsonEncode(input.toJson())).join('\n');
    final bytes = Uint8List.fromList(utf8.encode('$lines\n'));
    if (bytes.length > 200 * 1024 * 1024) {
      throw const OpenAIBatchException('batch JSONL exceeds 200 MB');
    }
    final uploadTimeout = timeout == null ? null : timeout - stopwatch.elapsed;
    if (uploadTimeout != null && uploadTimeout <= Duration.zero) {
      throw const OpenAIFileTimeoutException();
    }
    final inputFile = await files.upload(
      OpenAIFileUpload(
        filename: 'batch.jsonl',
        purpose: 'batch',
        bytes: bytes,
        mediaType: 'application/jsonl',
      ),
      abortSignal: abortSignal,
      timeout: uploadTimeout,
    );
    final remaining = timeout == null ? null : timeout - stopwatch.elapsed;
    if (remaining != null && remaining <= Duration.zero) {
      throw OpenAIBatchSubmissionException(
        inputFile.id,
        const OpenAIFileTimeoutException(),
      );
    }
    final scope = OpenAIRequestScope(abortSignal, remaining);
    try {
      final response = await client.post<Map<String, dynamic>>(
        _endpoint,
        data: {
          'input_file_id': inputFile.id.id,
          'endpoint': '/v1/responses',
          'completion_window': '24h',
          'metadata': ?metadata,
        },
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      if (response.data == null) {
        throw const OpenAIBatchException('Empty batch response');
      }
      return OpenAIBatch.fromJson(response.data!);
    } catch (error) {
      final cause = scope.timedOut
          ? const OpenAIFileTimeoutException()
          : scope.cancelled
          ? const AiOperationCancelledError()
          : error is DioException
          ? await apiErrorFromDioException(error, provider: 'openai')
          : error;
      throw OpenAIBatchSubmissionException(inputFile.id, cause);
    } finally {
      await scope.dispose();
    }
  }

  Future<OpenAIBatch> get(
    String id, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) => _request(
    '$_endpoint/${Uri.encodeComponent(_checkId(id))}',
    expectedId: id,
    abortSignal: abortSignal,
    timeout: timeout,
  );

  Future<OpenAIBatchPage> list({
    int? limit,
    String? after,
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    if (limit != null && (limit < 1 || limit > 100)) {
      throw const OpenAIBatchException('limit must be 1..100');
    }
    final query = <String, dynamic>{'limit': ?limit, 'after': ?after};
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.get<Map<String, dynamic>>(
        _endpoint,
        queryParameters: query,
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      final data = response.data?['data'];
      if (data is! List) {
        throw const OpenAIBatchException('Malformed batch list');
      }
      final items = <OpenAIBatch>[];
      for (final item in data) {
        if (item is! Map) {
          throw const OpenAIBatchException('Malformed batch list item');
        }
        items.add(OpenAIBatch.fromJson(Map<String, dynamic>.from(item)));
      }
      final hasMore = response.data?['has_more'];
      final lastId = response.data?['last_id'];
      if (hasMore is! bool ||
          lastId != null && lastId is! String ||
          hasMore && lastId is! String) {
        throw const OpenAIBatchException('Malformed batch pagination');
      }
      return OpenAIBatchPage(
        items: items,
        hasMore: hasMore,
        lastId: lastId as String?,
      );
    } on DioException catch (error) {
      throwIfOpenAICancelled(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  Future<OpenAIBatch> cancel(
    String id, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.post<Map<String, dynamic>>(
        '$_endpoint/${Uri.encodeComponent(_checkId(id))}/cancel',
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      if (response.data == null) {
        throw const OpenAIBatchException('Empty batch response');
      }
      final batch = OpenAIBatch.fromJson(response.data!);
      if (batch.id != id) {
        throw const OpenAIBatchException('Batch ID mismatch');
      }
      return batch;
    } on DioException catch (error) {
      throwIfOpenAICancelled(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  Future<OpenAIBatch> _request(
    String url, {
    String? expectedId,
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.get<Map<String, dynamic>>(
        url,
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      if (response.data == null) {
        throw const OpenAIBatchException('Empty batch response');
      }
      final batch = OpenAIBatch.fromJson(response.data!);
      if (expectedId != null && batch.id != expectedId) {
        throw const OpenAIBatchException('Batch ID mismatch');
      }
      return batch;
    } on DioException catch (error) {
      throwIfOpenAICancelled(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  String get _endpoint => '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/batches';
}

Stream<OpenAIBatchResult> decodeOpenAIBatchResults(
  Stream<List<int>> source, {
  int maxLineBytes = 200 * 1024 * 1024,
  int maxRows = 50000,
}) async* {
  final lineBytes = <int>[];
  final seen = <String>{};
  if (maxLineBytes < 1 || maxRows < 1) {
    throw const OpenAIBatchException('result bounds must be positive');
  }
  await for (final part in source) {
    for (final byte in part) {
      if (byte == 0x0a) {
        final result = _decodeBatchResultLine(lineBytes);
        lineBytes.clear();
        if (result == null) continue;
        if (seen.length >= maxRows) {
          throw const OpenAIBatchException('Batch result row limit exceeded');
        }
        if (!seen.add(result.customId)) {
          throw const OpenAIBatchException('Duplicate batch custom_id');
        }
        yield result;
      } else {
        lineBytes.add(byte);
        if (lineBytes.length > maxLineBytes) {
          throw const OpenAIBatchException('Batch result line exceeds limit');
        }
      }
    }
  }
  final result = _decodeBatchResultLine(lineBytes);
  if (result != null) {
    if (seen.length >= maxRows) {
      throw const OpenAIBatchException('Batch result row limit exceeded');
    }
    if (!seen.add(result.customId)) {
      throw const OpenAIBatchException('Duplicate batch custom_id');
    }
    yield result;
  }
}

OpenAIBatchResult? _decodeBatchResultLine(List<int> bytes) {
  if (bytes.isEmpty) return null;
  try {
    final line = utf8.decode(bytes).trim();
    if (line.isEmpty) return null;
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const OpenAIBatchException('Malformed batch JSONL');
    }
    return OpenAIBatchResult.fromJson(decoded);
  } on OpenAIBatchException {
    rethrow;
  } on FormatException {
    throw const OpenAIBatchException('Malformed or truncated batch JSONL');
  }
}

void _validateInputs(List<OpenAIBatchInput> inputs) {
  if (inputs.isEmpty || inputs.length > 50000) {
    throw const OpenAIBatchException('batch must contain 1..50000 inputs');
  }
  final ids = <String>{};
  final model = inputs.first.model;
  for (final input in inputs) {
    if (input.customId.trim().isEmpty ||
        input.model.trim().isEmpty ||
        (input.input is! String && input.input is! List) ||
        (input.options?.containsKey('model') ?? false) ||
        (input.options?.containsKey('input') ?? false) ||
        !ids.add(input.customId)) {
      throw const OpenAIBatchException(
        'custom_id and model must be nonempty and unique',
      );
    }
    if (input.model != model) {
      throw const OpenAIBatchException('batch inputs must use one model');
    }
  }
}

String _checkId(String id) {
  if (id.trim().isEmpty) {
    throw const OpenAIBatchException('batch id must not be empty');
  }
  return id;
}

DataContentProviderReference? _reference(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw const OpenAIBatchException('Malformed batch file reference');
  }
  return DataContentProviderReference(namespace: 'openai', id: value);
}

int? _requiredInteger(Object? map, String key) {
  if (map == null) return null;
  final value = (map as Map)[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw const OpenAIBatchException('Malformed batch request counts');
  }
  return value;
}
