import 'package:ai_sdk_dart/src/core/partial_json.dart';
import 'package:test/test.dart';

void main() {
  test('append-only snapshots retain old values and reject mutation', () {
    final builder = ImmutableArraySnapshotBuilder<int>();
    builder.addAll([1, 2]);
    final first = builder.snapshot();
    builder.addAll([3, 4, 5]);
    final second = builder.snapshot();

    expect(first, [1, 2]);
    expect(second, [1, 2, 3, 4, 5]);
    expect(first[1], 2);
    expect(second[4], 5);
    expect(() => first[0] = 9, throwsUnsupportedError);
    expect(() => first.add(9), throwsUnsupportedError);
  });

  test(
    'structural snapshots copy no elements and expose deterministic metrics',
    () {
      final counters = PartialJsonDebugCounters();
      final previous = partialJsonDebugCounters;
      partialJsonDebugCounters = counters;
      try {
        final builder = ImmutableArraySnapshotBuilder<int>();
        for (var i = 0; i < 1000; i++) {
          builder.add(i);
          builder.snapshot();
        }
        expect(counters.snapshotCount, 1000);
        expect(counters.snapshotElementsCopied, 0);
        expect(counters.snapshotStructuralNodes, greaterThan(1000));
        expect(counters.snapshotStructuralReferences, greaterThan(0));
      } finally {
        partialJsonDebugCounters = previous;
      }
    },
  );

  test('matches a reference across boundaries, batches, nulls, and bounds', () {
    final builder = ImmutableArraySnapshotBuilder<int?>();
    final reference = <int?>[];
    final retained = <List<int?>>[];
    for (var i = 0; i <= 4096; i++) {
      if (i % 7 == 0) {
        builder.addAll([null, i]);
        reference.addAll([null, i]);
      } else {
        builder.add(i);
        reference.add(i);
      }
      if (i % 257 == 0) retained.add(builder.snapshot());
    }
    final snapshot = builder.snapshot();
    expect(snapshot, reference);
    for (var i = 0; i < reference.length; i += 113) {
      expect(snapshot[i], reference[i]);
    }
    expect(() => snapshot[-1], throwsRangeError);
    expect(() => snapshot[snapshot.length], throwsRangeError);
    expect(retained.first, [null, 0]);
    expect(() => snapshot.clear(), throwsUnsupportedError);
  });
}
