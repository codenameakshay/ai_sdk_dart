import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_telemetry/ai_sdk_telemetry.dart';

Future<void> main() async {
  final sink = OtlpHttpMetricSink(
    endpoint: Uri.parse('http://127.0.0.1:4318/v1/metrics'),
  );
  sink.record(const TelemetryMetric(name: 'ai.example.metric', value: 1));
  await sink.dispose();
}
