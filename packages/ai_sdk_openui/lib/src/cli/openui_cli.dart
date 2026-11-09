import 'dart:convert';

import '../iui/library.dart' show intelligentUi;
import '../lang/parser.dart';
import '../lang/policy.dart';

const usage = '''Usage: openui validate <spec> <program|-> [options]
       openui spec <spec> [policy options]
  <spec> is a spec.json file, - for stdin, or intelligent-ui (built in).
  spec prints it as canonical JSON (sorted keys); policy options add a
  "policy" block, which validate applies under its own flags.
Policy options:
  --max-nodes=<n>         fail when the program has more components
  --max-depth=<n>         fail when components nest deeper
  --max-string=<n>        fail on a longer string
  --unknown=drop|fail     unknown components warn (drop, the default) or fail
  --allow-actions=<A,B>   the only steps and actions the program may call
validate options:
  --root=<Name>           root component (default: the spec's "root")
  --bound=<\$a,\$b>         host-bound \$variables
  --bound-schemas=<file>  JSON object of a JSON Schema per \$variable: bound
                          paths must exist in it and fit their props
Exit codes: 0 valid, 1 invalid, 2 unreadable input, 64 usage error.''';

/// Policy flags and the [ValidationPolicy.toJson] key each sets.
const _policyFlags = {
  'max-nodes': 'maxNodes',
  'max-depth': 'maxDepth',
  'max-string': 'maxStringLength',
  'unknown': 'unknownComponents',
  'allow-actions': 'allowedActions',
};
const _intFlags = {'max-nodes', 'max-depth', 'max-string'};
const _validateFlags = {'root', 'bound', 'bound-schemas'};

/// `openui validate <spec> <program|->` prints the validation report as JSON;
/// `openui spec <spec>` prints the spec as canonical JSON. Returns the exit
/// code (0 valid, 1 invalid, 2 unreadable input, 64 usage). [read] loads a
/// file, or stdin for `-`.
Future<int> runOpenUiCli(
  List<String> args, {
  required Future<String> Function(String path) read,
  required void Function(String text) out,
  required void Function(String text) err,
}) async {
  final command = args.isEmpty ? null : args[0];
  final paths = command == 'validate' ? 2 : 1;
  final options =
      (command == 'validate' || command == 'spec') && args.length > paths
      ? _options(args.skip(paths + 1).toList(), command == 'validate')
      : null;
  if (options == null) {
    err(usage);
    return 64;
  }
  final Map<String, Object?> spec;
  final ValidationPolicy policy;
  try {
    spec = args[1] == 'intelligent-ui'
        ? intelligentUi.toSpec()
        : jsonDecode(await read(args[1])) as Map<String, Object?>;
    final policyJson = {
      ...?(spec['policy'] as Map?)?.cast<String, Object?>(),
      ...options.policy,
    };
    policy = ValidationPolicy.fromJson(policyJson);
    if (command == 'spec') {
      out(
        canonicalJson({
          ...spec,
          if (policyJson.isNotEmpty) 'policy': policy.toJson(),
        }),
      );
      return 0;
    }
  } catch (error) {
    err('openui: $error');
    return 2;
  }
  final CompiledSchema schema;
  final String program;
  final Map<String, Map<String, Object?>> boundSchemas;
  try {
    schema = CompiledSchema.fromJsonSchema(
      (spec['schema'] as Map?)?.cast<String, Object?>() ?? spec,
    );
    program = await read(args[2]);
    final schemasPath = options.boundSchemas;
    boundSchemas = schemasPath == null
        ? const {}
        : (jsonDecode(await read(schemasPath)) as Map)
              .cast<String, Map<String, Object?>>();
  } catch (error) {
    err('openui: $error');
    return 2;
  }
  final report = validateProgram(
    program,
    schema,
    rootName: options.root ?? spec['root'] as String?,
    policy: policy,
    boundNames: options.bound,
    boundSchemas: boundSchemas,
  );
  out(report.toJsonString());
  return report.ok ? 0 : 1;
}

final class _Options {
  const _Options(this.policy, this.root, this.bound, this.boundSchemas);

  /// [ValidationPolicy.toJson] keys the flags set.
  final Map<String, Object?> policy;
  final String? root;
  final Set<String> bound;

  /// The `--bound-schemas` file.
  final String? boundSchemas;
}

/// The flags after the paths, or null for a usage error. Only `validate`
/// takes `--root`, `--bound` and `--bound-schemas`.
_Options? _options(List<String> flags, bool validate) {
  final values = <String, String>{};
  for (final arg in flags) {
    final eq = arg.indexOf('=');
    if (!arg.startsWith('--') || eq < 0) return null;
    final name = arg.substring(2, eq);
    if (!_policyFlags.containsKey(name) &&
        !(validate && _validateFlags.contains(name))) {
      return null;
    }
    values[name] = arg.substring(eq + 1);
  }
  final policy = <String, Object?>{};
  for (final MapEntry(key: flag, value: key) in _policyFlags.entries) {
    final text = values[flag];
    if (text == null) continue;
    if (_intFlags.contains(flag)) {
      final value = int.tryParse(text);
      if (value == null) return null;
      policy[key] = value;
    } else if (flag == 'unknown') {
      if (text != 'drop' && text != 'fail') return null;
      policy[key] = text;
    } else {
      policy[key] = _names(text).toList();
    }
  }
  return _Options(
    policy,
    values['root'],
    _names(values['bound'] ?? ''),
    values['bound-schemas'],
  );
}

Set<String> _names(String list) => {
  for (final name in list.split(','))
    if (name.isNotEmpty) name,
};
