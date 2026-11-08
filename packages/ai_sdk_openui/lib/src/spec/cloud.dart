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
    final issues = [
      for (final group in library.groups)
        for (final component in group.components)
          if (!library.components.containsKey(component.typeName))
            'Component group "${group.name}" references unknown component "${component.typeName}".',
    ];
    if (issues.isNotEmpty) {
      throw ArgumentError(
        '[generateSystemPrompt] Invalid library: ${issues.join(' ')}',
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
