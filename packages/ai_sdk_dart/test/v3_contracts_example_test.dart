import 'package:test/test.dart';

import '../example/migration/v3_contracts.dart' as contracts;

void main() {
  test('v3 public contract migration example runs without a provider', () {
    return contracts.main();
  });
}
