import 'dart:convert';
import 'dart:io';

/// Loads a JSON spec fixture from the conformance/specs directory.
///
/// [relativePath] is relative to `packages/ai_sdk/test/conformance/specs/`.
/// This is the source-of-truth contract document; update it when v6 changes.
Map<String, dynamic> loadFixture(String relativePath) {
  // Resolve relative to the file's own package test directory.
  final scriptPath = Platform.script.toFilePath();
  final scriptFile = File(scriptPath);

  // Walk up the directory tree to find the conformance/specs folder.
  var dir = scriptFile.parent;
  for (var i = 0; i < 10; i++) {
    final candidate = File('${dir.path}/conformance/specs/$relativePath');
    if (candidate.existsSync()) {
      return jsonDecode(candidate.readAsStringSync()) as Map<String, dynamic>;
    }
    final candidate2 = File('${dir.path}/specs/$relativePath');
    if (candidate2.existsSync()) {
      return jsonDecode(candidate2.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }

  // Fallback: search relative to the current working directory.
  final cwdCandidate = File(
    '${Directory.current.path}/packages/ai_sdk/test/conformance/specs/$relativePath',
  );
  if (cwdCandidate.existsSync()) {
    return jsonDecode(cwdCandidate.readAsStringSync()) as Map<String, dynamic>;
  }

  final directCandidate = File(
    '${Directory.current.path}/test/conformance/specs/$relativePath',
  );
  if (directCandidate.existsSync()) {
    return jsonDecode(directCandidate.readAsStringSync())
        as Map<String, dynamic>;
  }

  throw StateError(
    'Spec fixture not found: $relativePath\n'
    'Searched relative to: $scriptPath\n'
    'CWD: ${Directory.current.path}',
  );
}

/// Loads a specific test case from a spec fixture by [caseId].
Map<String, dynamic> loadTestCase(String fixturePath, String caseId) {
  final fixture = loadFixture(fixturePath);
  final cases = fixture['cases'] as List<dynamic>;
  for (final c in cases) {
    final caseMap = c as Map<String, dynamic>;
    if (caseMap['id'] == caseId) {
      return caseMap;
    }
  }
  throw StateError(
    'Test case "$caseId" not found in $fixturePath. '
    'Available: ${cases.map((c) => (c as Map)['id']).join(', ')}',
  );
}

/// Returns all test cases from a fixture.
List<Map<String, dynamic>> allTestCases(String fixturePath) {
  final fixture = loadFixture(fixturePath);
  return (fixture['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
}
