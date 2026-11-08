import 'dart:convert';

import '../lang/parser.dart';
import '../lang/policy.dart';

const usage = '''Usage: openui validate <spec.json> <program|-> [options]
  --root=<Name>           root component (default: the spec's "root")
  --max-nodes=<n>         fail when the program has more components
  --max-depth=<n>         fail when components nest deeper
  --max-string=<n>        fail on a longer string
  --unknown=drop|fail     unknown components warn (drop, the default) or fail
  --allow-actions=<A,B>   the only steps and actions the program may call
  --bound=<\$a,\$b>         host-bound \$variables
Exit codes: 0 valid, 1 invalid, 2 unreadable input, 64 usage error.''';

const _intFlags = {'max-nodes', 'max-depth', 'max-string'};
const _flags = {..._intFlags, 'root', 'unknown', 'allow-actions', 'bound'};

/// `openui validate <spec.json> <program|->`: prints the validation report as
/// JSON and returns the exit code (0 valid, 1 invalid, 2 unreadable input,
/// 64 usage). [read] loads a file, or stdin for `-`.
Future<int> runOpenUiCli(
  List<String> args, {
  required Future<String> Function(String path) read,
  required void Function(String text) out,
  required void Function(String text) err,
}) async {
  final options = args.length < 3 || args[0] != 'validate'
      ? null
      : _options(args.skip(3).toList());
  if (options == null) {
    err(usage);
    return 64;
  }
  final CompiledSchema schema;
  final String? root;
  final String program;
  try {
    final spec = jsonDecode(await read(args[1])) as Map<String, Object?>;
    schema = CompiledSchema.fromJsonSchema(
      (spec['schema'] as Map?)?.cast<String, Object?>() ?? spec,
    );
    root = options.root ?? spec['root'] as String?;
    program = await read(args[2]);
  } catch (error) {
    err('openui: $error');
    return 2;
  }
  final report = validateProgram(
    program,
    schema,
    rootName: root,
    policy: options.policy,
    boundNames: options.bound,
  );
  out(report.toJsonString());
  return report.ok ? 0 : 1;
}

final class _Options {
  const _Options(this.policy, this.root, this.bound);
  final ValidationPolicy policy;
  final String? root;
  final Set<String> bound;
}

/// The flags after the two paths, or null for a usage error.
_Options? _options(List<String> flags) {
  final values = <String, String>{};
  for (final arg in flags) {
    final eq = arg.indexOf('=');
    if (!arg.startsWith('--') || eq < 0) return null;
    final name = arg.substring(2, eq);
    if (!_flags.contains(name)) return null;
    values[name] = arg.substring(eq + 1);
  }
  final ints = <String, int?>{};
  for (final name in _intFlags) {
    final text = values[name];
    if (text == null) continue;
    final value = int.tryParse(text);
    if (value == null) return null;
    ints[name] = value;
  }
  final unknown = values['unknown'];
  if (unknown != null && unknown != 'drop' && unknown != 'fail') return null;
  final allow = values['allow-actions'];
  return _Options(
    ValidationPolicy(
      maxNodes: ints['max-nodes'],
      maxDepth: ints['max-depth'],
      maxStringLength: ints['max-string'],
      unknownComponents: unknown == 'fail'
          ? UnknownComponentPolicy.fail
          : UnknownComponentPolicy.drop,
      allowedActions: allow == null ? null : _names(allow),
    ),
    values['root'],
    _names(values['bound'] ?? ''),
  );
}

Set<String> _names(String list) => {
  for (final name in list.split(','))
    if (name.isNotEmpty) name,
};
