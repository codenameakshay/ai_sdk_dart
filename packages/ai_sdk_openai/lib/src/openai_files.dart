import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'openai_errors.dart';
import 'openai_request_scope.dart';

class OpenAIFileException implements Exception {
  const OpenAIFileException(this.message);
  final String message;
  @override
  String toString() => 'OpenAIFileException: $message';
}

class OpenAIFileUpload {
  const OpenAIFileUpload({
    required this.filename,
    required this.purpose,
    this.bytes,
    this.stream,
    this.length,
    this.mediaType,
    this.expiresAfter,
  }) : assert(
         (bytes != null) != (stream != null),
         'Provide exactly one of bytes or stream',
       ),
       assert(
         stream == null || length != null,
         'A stream upload requires a known length',
       );

  final String filename;
  final String purpose;
  final Uint8List? bytes;
  final Stream<List<int>>? stream;
  final int? length;
  final String? mediaType;
  final OpenAIFileExpiry? expiresAfter;

  void validate() {
    if (filename.trim().isEmpty) {
      throw const OpenAIFileException('filename must not be empty');
    }
    if (purpose.trim().isEmpty) {
      throw const OpenAIFileException('purpose must not be empty');
    }
    if ((bytes == null) == (stream == null)) {
      throw const OpenAIFileException('provide exactly one upload source');
    }
    if (stream != null && (length == null || length! < 0)) {
      throw const OpenAIFileException('stream length must be non-negative');
    }
    final expiry = expiresAfter;
    if (expiry != null &&
        (expiry.anchor != 'created_at' ||
            expiry.seconds < 1 ||
            expiry.seconds > 2592000)) {
      throw const OpenAIFileException(
        'expiresAfter must use created_at and 1..2592000 seconds',
      );
    }
  }
}

class OpenAIFileExpiry {
  const OpenAIFileExpiry({this.anchor = 'created_at', required this.seconds});
  final String anchor;
  final int seconds;

  Map<String, dynamic> toJson() => {'anchor': anchor, 'seconds': seconds};
}

class OpenAIFileMetadata {
  const OpenAIFileMetadata({
    required this.id,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
    this.expiresAt,
    this.status,
  });

  final DataContentProviderReference id;
  final int bytes;
  final DateTime createdAt;
  final String filename;
  final String purpose;
  final DateTime? expiresAt;
  final String? status;

  factory OpenAIFileMetadata.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const OpenAIFileException('File response has no id');
    }
    final created = json['created_at'];
    final bytes = json['bytes'];
    final filename = json['filename'];
    final purpose = json['purpose'];
    final expires = json['expires_at'];
    if (!_isJsonInt(created) ||
        !_isJsonInt(bytes) ||
        bytes < 0 ||
        filename is! String ||
        filename.isEmpty ||
        purpose is! String ||
        purpose.isEmpty ||
        (expires != null && !_isJsonInt(expires))) {
      throw const OpenAIFileException('Malformed file metadata');
    }
    final status = json['status'];
    if (status != null && status is! String) {
      throw const OpenAIFileException('Malformed file metadata');
    }
    try {
      return OpenAIFileMetadata(
        id: DataContentProviderReference(namespace: 'openai', id: id),
        bytes: (bytes as num).toInt(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (created as num).toInt() * 1000,
          isUtc: true,
        ),
        filename: filename,
        purpose: purpose,
        expiresAt: expires == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (expires as num).toInt() * 1000,
                isUtc: true,
              ),
        status: status as String?,
      );
    } catch (_) {
      throw const OpenAIFileException('Malformed file metadata');
    }
  }
}

bool _isJsonInt(Object? value) =>
    value is int || (value is num && value.isFinite && value == value.toInt());

class OpenAIFiles {
  const OpenAIFiles({
    required this.client,
    required this.headers,
    required this.baseUrl,
  });

  final Dio client;
  final Future<Map<String, String>> Function() headers;
  final String baseUrl;

  Future<OpenAIFileMetadata> upload(
    OpenAIFileUpload upload, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    upload.validate();
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final contentType = upload.mediaType == null
          ? null
          : DioMediaType.parse(upload.mediaType!);
      final part = upload.bytes != null
          ? MultipartFile.fromBytes(
              upload.bytes!,
              filename: upload.filename,
              contentType: contentType,
            )
          : MultipartFile.fromStream(
              () => upload.stream!,
              upload.length!,
              filename: upload.filename,
              contentType: contentType,
            );
      final form = FormData.fromMap({
        'purpose': upload.purpose,
        if (upload.expiresAfter != null)
          'expires_after[anchor]': upload.expiresAfter!.anchor,
        if (upload.expiresAfter != null)
          'expires_after[seconds]': upload.expiresAfter!.seconds.toString(),
        'file': part,
      });
      final response = await client.post<Map<String, dynamic>>(
        _endpoint,
        data: form,
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      final data = response.data;
      if (data == null) throw const OpenAIFileException('Empty file response');
      return OpenAIFileMetadata.fromJson(data);
    } on DioException catch (error) {
      _rethrowCancellation(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  Future<OpenAIFileMetadata> retrieve(
    DataContentProviderReference reference, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    _checkReference(reference);
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.get<Map<String, dynamic>>(
        '$_endpoint/${Uri.encodeComponent(reference.id)}',
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      if (response.data == null) {
        throw const OpenAIFileException('Empty file response');
      }
      final metadata = OpenAIFileMetadata.fromJson(response.data!);
      if (metadata.id.id != reference.id) {
        throw const OpenAIFileException('File response ID mismatch');
      }
      return metadata;
    } on DioException catch (error) {
      _rethrowCancellation(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  Future<Stream<List<int>>> download(
    DataContentProviderReference reference, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    _checkReference(reference);
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.get<ResponseBody>(
        '$_endpoint/${Uri.encodeComponent(reference.id)}/content',
        options: Options(
          headers: await scope.race(headers),
          responseType: ResponseType.stream,
        ),
        cancelToken: scope.token,
      );
      final body = response.data;
      if (body == null) throw const OpenAIFileException('Empty file body');
      return _downloadStream(body.stream, scope);
    } on DioException catch (error) {
      await scope.dispose(cancelTransport: true);
      _rethrowCancellation(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } catch (_) {
      await scope.dispose(cancelTransport: true);
      rethrow;
    }
  }

  Future<void> delete(
    DataContentProviderReference reference, {
    AbortSignal? abortSignal,
    Duration? timeout,
  }) async {
    _checkReference(reference);
    final scope = OpenAIRequestScope(abortSignal, timeout);
    try {
      final response = await client.delete<Map<String, dynamic>>(
        '$_endpoint/${Uri.encodeComponent(reference.id)}',
        options: Options(headers: await scope.race(headers)),
        cancelToken: scope.token,
      );
      final data = response.data;
      if (data?['id'] != reference.id || data?['deleted'] != true) {
        throw const OpenAIFileException('File delete acknowledgement mismatch');
      }
    } on DioException catch (error) {
      _rethrowCancellation(scope);
      throw await apiErrorFromDioException(error, provider: 'openai');
    } finally {
      await scope.dispose();
    }
  }

  String get _endpoint => '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/files';

  void _checkReference(DataContentProviderReference reference) {
    if (reference.namespace != 'openai') {
      throw ArgumentError.value(
        reference.namespace,
        'namespace',
        'OpenAI Files requires an openai provider reference',
      );
    }
    if (reference.id.trim().isEmpty) {
      throw ArgumentError('provider reference id must not be empty');
    }
  }
}

void _rethrowCancellation(OpenAIRequestScope scope) {
  if (scope.timedOut) throw const OpenAIFileTimeoutException();
  if (scope.cancelled) throw const AiOperationCancelledError();
}

Stream<List<int>> _downloadStream(
  Stream<List<int>> source,
  OpenAIRequestScope scope,
) {
  late StreamSubscription<List<int>> subscription;
  final output = StreamController<List<int>>();
  output.onListen = () {
    subscription = source.listen(
      (chunk) {
        if (scope.cancelled) {
          output.addError(
            scope.timedOut
                ? const OpenAIFileTimeoutException()
                : const AiOperationCancelledError(),
          );
          unawaited(subscription.cancel());
          unawaited(_disposeAndClose(output, scope));
          return;
        }
        output.add(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (scope.cancelled) {
          output.addError(
            scope.timedOut
                ? const OpenAIFileTimeoutException()
                : const AiOperationCancelledError(),
          );
        } else {
          output.addError(error, stack);
        }
        unawaited(_disposeAndClose(output, scope));
      },
      onDone: () => unawaited(_disposeAndClose(output, scope)),
      cancelOnError: false,
    );
  };
  output.onCancel = () async {
    // Do not let a transport's cancellation failure replace a source error.
    try {
      await subscription.cancel();
    } catch (_) {}
    await scope.dispose(cancelTransport: true);
  };
  return output.stream;
}

Future<void> _disposeAndClose(
  StreamController<List<int>> output,
  OpenAIRequestScope scope,
) async {
  try {
    await scope.dispose();
  } finally {
    await output.close();
  }
}
