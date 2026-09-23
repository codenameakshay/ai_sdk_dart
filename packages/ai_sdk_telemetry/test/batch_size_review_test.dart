import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';
import 'package:test/test.dart';

void main() {
  test(
    'valid observations split into payloads within the byte limit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final sizes = <int>[];
      final received = <Object?>[];
      server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        sizes.add(bytes.length);
        final payload = jsonDecode(utf8.decode(bytes)) as Map;
        final resource = (payload['resourceMetrics'] as List).single as Map;
        final scope = (resource['scopeMetrics'] as List).single as Map;
        received.addAll(scope['metrics'] as List);
        await request.response.close();
      });
      final sink = OtlpHttpMetricSink(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/metrics'),
        maxPayloadBytes: 800,
        batchSize: 4,
      );
      addTearDown(sink.dispose);
      for (var index = 0; index < 3; index++) {
        sink.record(TelemetryMetric(name: '${'x' * 200}$index', value: index));
      }
      expect(sink.pendingCount, 3);
      await sink.flush();
      expect(received, hasLength(3));
      expect(sizes, everyElement(lessThanOrEqualTo(800)));
      expect(sink.pendingCount, 0);
    },
  );
}
