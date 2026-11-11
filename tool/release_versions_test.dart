import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('MCP clientInfo reports the ai_sdk_mcp package version', () {
    final pubspec = File('packages/ai_sdk_mcp/pubspec.yaml').readAsStringSync();
    final client = File(
      'packages/ai_sdk_mcp/lib/src/mcp_client.dart',
    ).readAsStringSync();
    final version = RegExp(
      r'^version: (\S+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(
      client,
      contains(
        "const _clientInfo = {'name': 'ai_sdk_dart', 'version': '$version'};",
      ),
    );
  });
}
