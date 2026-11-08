import 'dart:typed_data';

/// JavaScript `Math.round`: halves go up (-2.5 is -2), exactly for every double.
double jsRound(num x) {
  final d = x.toDouble();
  final f = d.floorToDouble();
  return d - f >= 0.5 ? f + 1 : f;
}

/// JavaScript `Number.prototype.toFixed(digits)`: the exact binary value
/// rounded half up, to 0 to 100 digits (Dart's toStringAsFixed stops at 20).
String toFixed(double x, int digits) {
  if (digits < 0 || digits > 100) {
    throw RangeError.range(digits, 0, 100, 'digits');
  }
  if (x.isNaN) return 'NaN';
  if (x.abs() >= 1e21) {
    final s = x.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
  // Two 32-bit halves, not getUint64: dart2js has no 64-bit ints.
  final bytes = ByteData(8)..setFloat64(0, x.abs());
  final high = bytes.getUint32(0);
  final biased = (high >> 20) & 0x7FF;
  final fraction =
      BigInt.from(high & 0xFFFFF) << 32 | BigInt.from(bytes.getUint32(4));
  final mantissa = biased == 0 ? fraction : fraction | BigInt.one << 52;
  final exponent = (biased == 0 ? 1 : biased) - 1075;
  final scaled = mantissa * BigInt.from(10).pow(digits);
  BigInt n;
  if (exponent >= 0) {
    n = scaled << exponent;
  } else {
    final den = BigInt.one << -exponent;
    n = scaled ~/ den;
    if ((scaled - n * den) * BigInt.two >= den) n += BigInt.one;
  }
  var s = n.toString();
  if (digits > 0) {
    s = s.padLeft(digits + 1, '0');
    s = '${s.substring(0, s.length - digits)}.${s.substring(s.length - digits)}';
  }
  return x < 0 ? '-$s' : s;
}
