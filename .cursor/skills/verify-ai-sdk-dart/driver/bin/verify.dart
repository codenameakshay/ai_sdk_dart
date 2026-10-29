// Runs the AI SDK Dart verification checks and writes evidence.
//
//   dart run bin/verify.dart list [package]
//   dart run bin/verify.dart run <package|all> [--check <id>] [--live] --evidence <dir>
//
// Use the `scripts/verify` wrapper instead of calling this directly; it sets
// the run id, evidence directory and secret files.
import 'package:ai_sdk_verify/harness.dart';
import 'package:ai_sdk_verify/runner.dart';
import 'package:ai_sdk_verify/packages/ai_sdk_anthropic.dart' as anthropic;
import 'package:ai_sdk_verify/packages/ai_sdk_azure.dart' as azure;
import 'package:ai_sdk_verify/packages/ai_sdk_cohere.dart' as cohere;
import 'package:ai_sdk_verify/packages/ai_sdk_conversation.dart'
    as conversation;
import 'package:ai_sdk_verify/packages/ai_sdk_dart.dart' as core;
import 'package:ai_sdk_verify/packages/ai_sdk_google.dart' as google;
import 'package:ai_sdk_verify/packages/ai_sdk_groq.dart' as groq;
import 'package:ai_sdk_verify/packages/ai_sdk_json_schema.dart' as json_schema;
import 'package:ai_sdk_verify/packages/ai_sdk_mcp.dart' as mcp;
import 'package:ai_sdk_verify/packages/ai_sdk_mistral.dart' as mistral;
import 'package:ai_sdk_verify/packages/ai_sdk_ollama.dart' as ollama;
import 'package:ai_sdk_verify/packages/ai_sdk_openai.dart' as openai;
import 'package:ai_sdk_verify/packages/ai_sdk_openai_compatible.dart'
    as openai_compatible;
import 'package:ai_sdk_verify/packages/ai_sdk_provider.dart' as provider;
import 'package:ai_sdk_verify/packages/ai_sdk_realtime.dart' as realtime;
import 'package:ai_sdk_verify/packages/ai_sdk_remote.dart' as remote;
import 'package:ai_sdk_verify/packages/ai_sdk_telemetry.dart' as telemetry;

final List<PackageChecks> registry = [
  provider.checks,
  core.checks,
  json_schema.checks,
  conversation.checks,
  remote.checks,
  realtime.checks,
  telemetry.checks,
  openai_compatible.checks,
  openai.checks,
  anthropic.checks,
  google.checks,
  azure.checks,
  cohere.checks,
  groq.checks,
  mistral.checks,
  ollama.checks,
  mcp.checks,
];

Future<void> main(List<String> args) => runCli(args, registry);
