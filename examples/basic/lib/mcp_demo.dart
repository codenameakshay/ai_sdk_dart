/// AI SDK Dart — MCP (Model Context Protocol) Example
///
/// Demonstrates using `ai_sdk_mcp` to:
///
///   1. Connect to an MCP server over HTTP (`HttpClientTransport`)
///   2. Run the `initialize` handshake and discover the server's tools
///   3. Call a discovered tool directly
///   4. Hand the discovered `ToolSet` to `generateText` so the model can call
///      the MCP tools itself
///
/// To keep the example self-contained and runnable with zero external setup, it
/// spins up a tiny in-process MCP server (a `dart:io` `HttpServer` speaking
/// MCP's JSON-RPC) and connects to it over loopback. In a real app you would
/// point the transport at a remote server URL instead — see [connectViaSse]
/// below for the `SseClientTransport` variant.
///
/// Note: stdio-based MCP servers (`StdioMCPTransport`) are desktop/native only;
/// this HTTP/SSE flow works everywhere `package:http` does, including web.
///
/// Run:
///   dart run lib/mcp_demo.dart                          # discovery + tool call
///   OPENAI_API_KEY=sk-... dart run lib/mcp_demo.dart    # also runs the LLM step
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

// ─── helpers ──────────────────────────────────────────────────────────────

void header(String title) {
  final bar = '─' * (title.length + 4);
  print('\n┌$bar┐');
  print('│  $title  │');
  print('└$bar┘');
}

// ─── entry point ────────────────────────────────────────────────────────────

Future<void> main() async {
  // 1. Start a local MCP server so the example runs with no external setup.
  final server = await _startMockMcpServer();
  final baseUrl = 'http://${server.address.address}:${server.port}/mcp';
  print('Mock MCP server listening at $baseUrl');

  // 2. Connect over HTTP and run the MCP initialize handshake.
  final client = MCPClient(
    transport: HttpClientTransport(url: Uri.parse(baseUrl)),
  );

  try {
    await client.initialize();
    print('✓ Connected and initialized.');

    // 3. Discover tools. `tools()` returns a `ToolSet` (Map<String, Tool>)
    //    ready to pass straight to generateText / streamText.
    final tools = await client.tools();
    header('Discovered MCP tools');
    for (final name in tools.keys) {
      print('  • $name');
    }

    // 4. Call a discovered tool directly — no LLM / API key required.
    header('Direct tool call');
    final weather = await client.callTool('getWeather', {'city': 'Tokyo'});
    print('getWeather(Tokyo) -> $weather');
    final dice = await client.callTool('rollDice', {'sides': 20});
    print('rollDice(20)      -> $dice');

    // 5. Hand the discovered tools to the model so it can call them itself.
    //    Requires an OpenAI key; the MCP steps above work without one.
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      header('LLM step skipped');
      print(
        'Set OPENAI_API_KEY to let the model call the MCP tools via '
        'generateText:\n  export OPENAI_API_KEY=sk-...',
      );
    } else {
      header('generateText with MCP tools');
      final result = await generateText(
        model: openai('gpt-4.1-mini'),
        prompt: 'What is the weather in Paris, and roll a 6-sided die for me?',
        tools: tools,
        maxSteps: 5,
        onStepFinish: (step) {
          for (final call in step.toolCalls) {
            print('  → called ${call.toolName}(${jsonEncode(call.input)})');
          }
        },
      );
      print('\nAnswer: ${result.text}');
    }
  } on MCPException catch (e) {
    print('MCP error: ${e.message}');
  } finally {
    await client.close();
    await server.close(force: true);
    print('\nDone.');
  }
}

/// Connect to a *remote* MCP server over HTTP+SSE (protocol 2024-11-05).
///
/// Shown for reference — `main` uses the simpler [HttpClientTransport] against
/// the in-process server. Use SSE when the server pushes notifications (e.g.
/// `notifications/resources/updated`) over a long-lived connection.
///
/// ```dart
/// final client = await connectViaSse(Uri.parse('https://example.com/sse'));
/// final tools = await client.tools();
/// ```
Future<MCPClient> connectViaSse(Uri sseUrl) async {
  final client = MCPClient(
    transport: SseClientTransport(
      url: sseUrl,
      connectTimeout: const Duration(seconds: 30),
      requestTimeout: const Duration(seconds: 30),
    ),
  );
  await client.initialize();
  return client;
}

// ─── in-process mock MCP server (JSON-RPC over HTTP) ──────────────────────────

/// Tool descriptors advertised by `tools/list`. The descriptions document the
/// expected arguments so the model knows what to pass.
const _toolDescriptors = [
  {
    'name': 'getWeather',
    'description':
        'Get the current weather for a city. Argument: { "city": string }.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
    },
  },
  {
    'name': 'rollDice',
    'description': 'Roll an N-sided die. Argument: { "sides": integer }.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'sides': {'type': 'integer'},
      },
      'required': ['sides'],
    },
  },
];

Future<HttpServer> _startMockMcpServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(_handleRequest);
  return server;
}

Future<void> _handleRequest(HttpRequest request) async {
  if (request.method != 'POST') {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
    return;
  }

  final body = await utf8.decoder.bind(request).join();
  Map<String, dynamic> rpc;
  try {
    rpc = (jsonDecode(body) as Map).cast<String, dynamic>();
  } catch (_) {
    request.response.statusCode = HttpStatus.badRequest;
    await request.response.close();
    return;
  }

  final result = _dispatch(rpc['method'] as String?, rpc['params']);
  final payload = jsonEncode({
    'jsonrpc': '2.0',
    'id': rpc['id'],
    'result': result,
  });

  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write(payload);
  await request.response.close();
}

Object? _dispatch(String? method, Object? params) {
  switch (method) {
    case 'initialize':
      return {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': <String, dynamic>{}},
        'serverInfo': {'name': 'mock-mcp-server', 'version': '1.0.0'},
      };
    case 'notifications/initialized':
      return <String, dynamic>{};
    case 'tools/list':
      return {'tools': _toolDescriptors};
    case 'tools/call':
      final p = (params as Map?)?.cast<String, dynamic>() ?? const {};
      final args = (p['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
      return _callTool(p['name'] as String?, args);
    default:
      return <String, dynamic>{};
  }
}

Map<String, dynamic> _callTool(String? name, Map<String, dynamic> args) {
  final String text;
  switch (name) {
    case 'getWeather':
      final city = (args['city'] as String?) ?? 'Unknown';
      text = 'It is sunny and 24°C in $city.';
    case 'rollDice':
      final sides = ((args['sides'] as num?)?.toInt() ?? 6).clamp(1, 1000);
      final roll = Random().nextInt(sides) + 1;
      text = 'You rolled a $roll (1–$sides).';
    default:
      return {
        'content': [
          {'type': 'text', 'text': 'Unknown tool: $name'},
        ],
        'isError': true,
      };
  }
  return {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': false,
  };
}
