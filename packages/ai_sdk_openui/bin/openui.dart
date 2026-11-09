import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openui/src/cli/openui_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runOpenUiCli(
    args,
    read: (path) async => path == '-'
        ? await stdin.transform(utf8.decoder).join()
        : File(path).readAsString(),
    out: stdout.write,
    err: stderr.writeln,
  );
}
