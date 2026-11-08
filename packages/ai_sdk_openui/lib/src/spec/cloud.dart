import '../lang/js.dart';
import 'library.dart';

/// OpenUI Cloud's pin for its built-in chat library (lang-core `CLOUD_CHAT_LIBRARY_VERSION`).
const String cloudChatLibraryVersion = '0.1.0';

/// OpenUI Cloud's pin for the slides artifact library.
const String slidesLibraryVersion = '0.1.0';

/// OpenUI Cloud's pin for the report artifact library.
const String reportLibraryVersion = '0.1.0';

/// The prompt options OpenUI Cloud accepts (lang-core `CloudPromptOptions`).
final class CloudPromptOptions {
  const CloudPromptOptions({
    this.examples,
    this.preamble,
    this.additionalRules,
  });
  final List<String>? examples;
  final String? preamble;
  final List<String>? additionalRules;
}

/// lang-core `generateSystemPrompt({cloud: true})`: OpenUI Cloud's `]]>openui:config` block.
///
/// Without [library], Cloud uses its built-in chat library.
String cloudSystemPrompt({
  OpenUiLibrary? library,
  CloudPromptOptions? promptOptions,
  String? instructions,
}) {
  final Map<String, Object?> config;
  if (library != null) {
    final issues = validateChatLibrary(library.toSpec());
    if (issues.isNotEmpty) {
      throw ArgumentError(
        '[generateSystemPrompt] Invalid library: ${issues.map((i) => i.message).join(' ')}',
      );
    }
    final spec = {...library.toSpec()}..remove('components');
    final picked = _pickCloudOptions(promptOptions);
    config = {'chatLibrary': spec, 'systemPromptOptions': ?picked};
  } else {
    if (_pickCloudOptions(promptOptions) != null) {
      throw ArgumentError(
        '[generateSystemPrompt] promptOptions requires a library — the built-in library ignores it.',
      );
    }
    config = {'libraryVersion': cloudChatLibraryVersion};
  }
  final block = ']]>openui:config\n${Js.stringify(config)}';
  return instructions != null && instructions.isNotEmpty
      ? '$block\n$instructions'
      : block;
}

/// lang-core `ChatLibraryIssue`: one structural problem of a library spec.
final class ChatLibraryIssue {
  const ChatLibraryIssue(this.code, this.message, [this.path]);

  /// `invalid-shape`, `root-not-found`, `unresolved-ref`,
  /// `unknown-group-component` or `invalid-required`.
  final String code;
  final String message;

  /// Where, such as `$defs/Card/properties/children/items`.
  final String? path;
}

final _refPattern = RegExp(r'^#/\$defs/(.+)$');

/// lang-core `validateChatLibrary`: every structural issue of a library
/// spec ([OpenUiLibrary.toSpec]) in one pass; empty when it is valid.
List<ChatLibraryIssue> validateChatLibrary(Object? library) {
  if (library is! Map) {
    return const [
      ChatLibraryIssue('invalid-shape', 'chatLibrary must be an object.'),
    ];
  }
  final issues = <ChatLibraryIssue>[];
  final root = library['root'];
  if (library.containsKey('root') && (root is! String || root.isEmpty)) {
    issues.add(
      const ChatLibraryIssue(
        'invalid-shape',
        'chatLibrary.root, when present, must be a non-empty string.',
        'root',
      ),
    );
  }
  final schema = library['schema'];
  if (schema is! Map) {
    issues.add(
      const ChatLibraryIssue(
        'invalid-shape',
        r'chatLibrary.schema must be an object with a $defs map of component schemas.',
        'schema',
      ),
    );
    return issues;
  }
  final defs = schema[r'$defs'];
  if (defs is! Map || defs.isEmpty) {
    issues.add(
      const ChatLibraryIssue(
        'invalid-shape',
        r'chatLibrary.schema.$defs must be a non-empty object keyed by component name.',
        r'schema/$defs',
      ),
    );
    return issues;
  }
  final defNames = {for (final k in defs.keys) '$k'};
  if (root is String && root.isNotEmpty && !defNames.contains(root)) {
    issues.add(
      ChatLibraryIssue(
        'root-not-found',
        'Root component "$root" was not found in schema.\$defs. Available components: ${defNames.join(', ')}.',
        'root',
      ),
    );
  }
  void collectRefs(Object? node, String path) {
    if (node is List) {
      for (var i = 0; i < node.length; i++) {
        collectRefs(node[i], '$path/$i');
      }
      return;
    }
    if (node is! Map) return;
    final ref = node[r'$ref'];
    if (ref is String) {
      final match = _refPattern.firstMatch(ref);
      if (match == null || !defNames.contains(match[1])) {
        issues.add(
          ChatLibraryIssue(
            'unresolved-ref',
            'Unresolvable \$ref "$ref" at $path — refs must be "#/\$defs/<name>" pointing at a component in \$defs.',
            path,
          ),
        );
      }
    }
    for (final MapEntry(:key, :value) in node.entries) {
      if (key != r'$ref') collectRefs(value, '$path/$key');
    }
  }

  for (final MapEntry(key: name, value: def) in defs.entries) {
    final defPath = '\$defs/$name';
    if (def is! Map) {
      issues.add(
        ChatLibraryIssue(
          'invalid-shape',
          '$defPath must be an object component schema.',
          defPath,
        ),
      );
      continue;
    }
    final properties = def['properties'];
    if (def.containsKey('properties') && properties is! Map) {
      issues.add(
        ChatLibraryIssue(
          'invalid-shape',
          '$defPath/properties must be an object.',
          '$defPath/properties',
        ),
      );
    }
    final required = def['required'];
    if (def.containsKey('required')) {
      if (required is! List || required.any((r) => r is! String)) {
        issues.add(
          ChatLibraryIssue(
            'invalid-required',
            '$defPath/required must be an array of property names.',
            '$defPath/required',
          ),
        );
      } else {
        final keys = properties is Map ? properties.keys.toSet() : <Object?>{};
        for (final r in required) {
          if (!keys.contains(r)) {
            issues.add(
              ChatLibraryIssue(
                'invalid-required',
                '$defPath lists required property "$r" that is not in properties.',
                '$defPath/required',
              ),
            );
          }
        }
      }
    }
    collectRefs(properties, '$defPath/properties');
  }
  final groups = library['componentGroups'];
  for (final group in groups is List ? groups : const []) {
    if (group is! Map ||
        group['name'] is! String ||
        group['components'] is! List) {
      issues.add(
        const ChatLibraryIssue(
          'invalid-shape',
          'Each componentGroups entry must be {name: string, components: string[], notes?: string[]}.',
          'componentGroups',
        ),
      );
      continue;
    }
    for (final comp in group['components'] as List) {
      if (comp is! String || !defNames.contains(comp)) {
        issues.add(
          ChatLibraryIssue(
            'unknown-group-component',
            'Component group "${group['name']}" references unknown component "${Js.string(comp)}".',
            'componentGroups',
          ),
        );
      }
    }
  }
  return issues;
}

Map<String, Object?>? _pickCloudOptions(CloudPromptOptions? options) {
  if (options == null) return null;
  final preamble = options.preamble;
  final picked = <String, Object?>{
    if (options.examples != null) 'examples': options.examples,
    if (preamble != null && preamble.isNotEmpty) 'preamble': preamble,
    if (options.additionalRules != null)
      'additionalRules': options.additionalRules,
  };
  return picked.isEmpty ? null : picked;
}

enum ArtifactKind { slides, report }

final class ArtifactOption {
  const ArtifactOption(this.type, {this.instruction, this.libraryVersion});
  final ArtifactKind type;

  /// Folded into the Cloud tool description.
  final String? instruction;

  /// Overrides this package's pinned library version for this artifact.
  final String? libraryVersion;
}

/// lang-core `artifactTool`: the Responses `tools[]` entry enabling OpenUI Cloud's artifact tool.
///
/// Omit [artifacts] to enable every kind.
Map<String, Object?> artifactTool({List<ArtifactOption>? artifacts}) {
  if (artifacts == null) {
    return {
      'type': 'artifact',
      'artifacts': [
        for (final kind in ArtifactKind.values)
          {'artifact_type': kind.name, 'library_version': _pinFor(kind)},
      ],
    };
  }
  if (artifacts.isEmpty) {
    throw ArgumentError(
      'artifactTool: `artifacts` must not be empty — omit it to enable all artifact types.',
    );
  }
  final seen = <ArtifactKind>{};
  final entries = <Map<String, Object?>>[];
  for (final artifact in artifacts) {
    if (!seen.add(artifact.type)) {
      throw ArgumentError(
        "artifactTool: duplicate artifact '${artifact.type.name}'.",
      );
    }
    final instruction = artifact.instruction;
    entries.add({
      'artifact_type': artifact.type.name,
      if (instruction != null && instruction.isNotEmpty)
        'instruction': instruction,
      'library_version': artifact.libraryVersion ?? _pinFor(artifact.type),
    });
  }
  return {'type': 'artifact', 'artifacts': entries};
}

String _pinFor(ArtifactKind kind) => switch (kind) {
  ArtifactKind.slides => slidesLibraryVersion,
  ArtifactKind.report => reportLibraryVersion,
};
