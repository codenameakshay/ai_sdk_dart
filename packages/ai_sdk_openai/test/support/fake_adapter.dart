import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A [HttpClientAdapter] that hands every request to [handler] and returns
/// whatever [ResponseBody] it produces. Shared across tests that only need a
/// plain request/response stub.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
