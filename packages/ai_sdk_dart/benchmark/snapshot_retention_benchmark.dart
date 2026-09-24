import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:ai_sdk_dart/src/core/partial_json.dart';

final _retained = <List<int>>[];

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      !const ['copy', 'structural'].contains(arguments.single)) {
    throw ArgumentError('Expected copy or structural');
  }
  final info = await Service.controlWebServer(
    enable: true,
    silenceOutput: true,
  );
  final client = HttpClient();
  final isolateId = Service.getIsolateId(Isolate.current)!;
  Future<int> liveHeap() async {
    final uri = info.serverUri!
        .resolve('getAllocationProfile')
        .replace(queryParameters: {'isolateId': isolateId, 'gc': 'true'});
    final request = await client.getUrl(uri);
    final response = await request.close();
    final decoded = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
    final result = decoded['result'] as Map? ?? decoded;
    return (result['memoryUsage'] as Map)['heapUsage'] as int;
  }

  try {
    const count = 4000;
    final values = List.generate(count, (index) => index);
    await liveHeap();
    final before = await liveHeap();
    final timer = Stopwatch()..start();
    if (arguments.single == 'structural') {
      final builder = ImmutableArraySnapshotBuilder<int>();
      for (final value in values) {
        builder.addAll([value]);
        _retained.add(builder.snapshot());
      }
    } else {
      final prefix = <int>[];
      for (final value in values) {
        prefix.add(value);
        _retained.add(createTrackedImmutableSnapshot(prefix));
      }
    }
    timer.stop();
    final after = await liveHeap();
    for (var i = 0; i < count; i++) {
      if (_retained[i].length != i + 1 || _retained[i].last != i) {
        throw StateError('Snapshot prefix changed');
      }
    }
    print(
      jsonEncode({
        'mode': arguments.single,
        'elements': count,
        'retainedSnapshots': _retained.length,
        'heapBeforeBytes': before,
        'heapAfterBytes': after,
        'retainedHeapDeltaBytes': after - before,
        'elapsedMicroseconds': timer.elapsedMicroseconds,
        'processPeakRssBytes': ProcessInfo.maxRss,
        'runtime': Platform.version,
        'platform': Platform.operatingSystem,
        'note':
            'Post-GC live heap with every prefix retained; process peak RSS includes VM/compiler. Same-source algorithm comparison, integer payloads, not typical whole-SDK memory.',
      }),
    );
  } finally {
    client.close(force: true);
    await Service.controlWebServer(enable: false);
  }
}
