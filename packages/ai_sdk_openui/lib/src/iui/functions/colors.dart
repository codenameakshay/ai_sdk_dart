import '../../spec/library.dart';
import '../../spec/schema.dart';

final _hex = RegExp(r'^#?([\da-f]{3}|[\da-f]{6})$', caseSensitive: false);

List<int> _channels(String color) {
  final m = _hex.firstMatch(color.trim());
  if (m == null) throw StateError('not a hex color: $color');
  final digits = m.group(1)!;
  final hex = digits.length == 3
      ? digits.split('').map((c) => '$c$c').join()
      : digits;
  return [
    for (var i = 0; i < 6; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

final List<FunctionSpec> colorFunctions = [
  FunctionSpec(
    'MixColor',
    description:
        'The hex color a fraction t of the way from one hex color to another, e.g. @MixColor("#ffffff", "#0285ff", 0.5) for a heatmap or a tint',
    params: {'from': S.string(), 'to': S.string(), 't': S.number()},
    returns: S.string(),
    fn: (a) {
      final from = _channels(a['from'] as String);
      final to = _channels(a['to'] as String);
      final k = (a['t'] as num).clamp(0, 1);
      final mixed = [
        for (var i = 0; i < 3; i++)
          // JS Math.round for values in 0..255; floor(x + 0.5) is exact there.
          (from[i] + (to[i] - from[i]) * k + 0.5)
              .floor()
              .toRadixString(16)
              .padLeft(2, '0'),
      ];
      return '#${mixed.join()}';
    },
  ),
];
