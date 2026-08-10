import 'dart:typed_data';

import 'package:dio/dio.dart';

class TrackingHttpClientAdapter implements HttpClientAdapter {
  TrackingHttpClientAdapter(this.inner);

  final HttpClientAdapter inner;

  int closeCount = 0;
  bool? lastForce;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {
    closeCount++;
    lastForce = force;
    inner.close(force: force);
  }
}

TrackingHttpClientAdapter attachTrackingAdapter(Dio client) {
  final adapter = TrackingHttpClientAdapter(client.httpClientAdapter);
  client.httpClientAdapter = adapter;
  return adapter;
}
