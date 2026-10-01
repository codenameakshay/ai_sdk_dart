import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_basic_example/main.dart' as basic;
import 'package:ai_sdk_basic_example/mcp_demo.dart' as mcp;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    for (final name in [
      'failed remote initialization closes its client',
      'completed CLI closes its provider',
      'failed MCP model request closes its provider',
      'invalid structured output reports one awaited error',
      'lost tool response executes once and retries only safe reads',
      'reasoning output identifies the final step',
    ]) {
      final result = await Process.run(Platform.resolvedExecutable, [
        '--enable-asserts',
        'run',
        '--define=OPENAI_API_KEY=test',
        Platform.script.toFilePath(),
        name,
      ]);
      if (result.exitCode != 0) {
        stderr.write(result.stdout);
        stderr.write(result.stderr);
        throw StateError('$name failed with exit code ${result.exitCode}');
      }
      print('PASS: $name');
    }
    return;
  }

  final clients = <_TrackingClient>[];
  await HttpOverrides.runZoned(
    () async {
      switch (args.single) {
        case 'reasoning output identifies the final step':
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          _redirect = Uri.parse('http://127.0.0.1:${server.port}/chat');
          server.listen((request) async {
            await request.drain<void>();
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'index': 0,
                    'message': {
                      'role': 'assistant',
                      'content': '80 km/h',
                      'reasoning_content': '60 divided by 0.75 is 80.',
                    },
                    'finish_reason': 'stop',
                  },
                ],
              }),
            );
            await request.response.close();
          });
          final output = <String>[];
          try {
            await runZoned(
              () => basic.main(['11']),
              zoneSpecification: ZoneSpecification(
                print: (_, _, _, line) => output.add(line),
              ),
            );
          } finally {
            await server.close(force: true);
          }
          assert(!output.any((line) => line.contains('Aggregate reasoning')));
          assert(
            output.any((line) => line == 'Final-step reasoning : 1 part(s)'),
          );
        case 'lost tool response executes once and retries only safe reads':
          final unsafeTransport = mcp.ResponseLossTransport();
          final unsafe = MCPClient(
            transport: unsafeTransport,
            protocolMode: MCPProtocolMode.modern,
          );
          try {
            await unsafe.initialize();
            try {
              await unsafe.callTool('rollDice', {'sides': 6});
              throw StateError('Expected ambiguous tool completion');
            } on MCPAmbiguousToolCompletionException catch (_) {}
            assert(unsafeTransport.executedToolCalls == 1);
          } finally {
            await unsafe.close();
          }
          final safeTransport = mcp.ResponseLossTransport();
          final safe = MCPClient(
            transport: safeTransport,
            protocolMode: MCPProtocolMode.modern,
            reconnectPolicy: const MCPReconnectPolicy(
              maxAttempts: 1,
              initialDelayMs: 0,
              maxDelayMs: 0,
            ),
          );
          try {
            await safe.initialize();
            final recovered = await safe.callTool('getWeather', {
              'city': 'Paris',
            }, retryOnTransportFailure: true);
            assert(recovered == 'It is sunny and 24°C in Paris.');
            assert(safeTransport.executedToolCalls == 2);
            await safe.callTool('getWeather', {'city': 'Tokyo'});
            assert(safeTransport.executedToolCalls == 3);
          } finally {
            await safe.close();
          }
        case 'failed remote initialization closes its client':
          try {
            await mcp.connectViaHttp(Uri.parse('https://fixture.invalid/mcp'));
            throw StateError('Expected initialization to fail');
          } on MCPTransportException catch (_) {}
          assert(clients.length == 1);
          assert(clients.single.closed, 'The failed connection was not closed');
        case 'completed CLI closes its provider':
          await basic.main(['1']);
          assert(clients.isNotEmpty);
          assert(
            clients.every((client) => client.closed),
            'Provider stayed open',
          );
        case 'failed MCP model request closes its provider':
          try {
            await mcp.main();
            throw StateError('Expected the model request to fail');
          } on AiApiCallError catch (_) {}
          assert(clients.isNotEmpty);
          assert(
            clients.every((client) => client.closed),
            'Provider stayed open',
          );
        case 'invalid structured output reports one awaited error':
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final endpoint = Uri.parse('http://127.0.0.1:${server.port}/chat');
          server.listen((request) async {
            await request.drain<void>();
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            for (final event in [
              {
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': '{}'},
                    'finish_reason': null,
                  },
                ],
              },
              {
                'choices': [
                  {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
                ],
              },
            ]) {
              request.response.write('data: ${jsonEncode(event)}\n\n');
            }
            request.response.write('data: [DONE]\n\n');
            await request.response.close();
          });
          _redirect = endpoint;
          final unhandled = <Object>[];
          final completed = Completer<void>();
          Object? awaitedError;
          runZonedGuarded(() async {
            try {
              await basic.demo8StreamObject();
            } catch (error) {
              awaitedError = error;
            } finally {
              completed.complete();
            }
          }, (error, _) => unhandled.add(error));
          await completed.future;
          await Future<void>.delayed(Duration.zero);
          for (final client in clients) {
            client.close(force: true);
          }
          await server.close(force: true);
          assert(
            awaitedError != null,
            'Invalid object must reject the awaited result',
          );
          assert(
            unhandled.isEmpty,
            'Companion streams leaked errors: $unhandled',
          );
      }
    },
    createHttpClient: (context) {
      final client = _TrackingClient(
        _RealHttpOverrides().createHttpClient(context),
      );
      clients.add(client);
      return client;
    },
  );
}

Uri? _redirect;

class _RealHttpOverrides extends HttpOverrides {}

class _TrackingClient implements HttpClient {
  _TrackingClient(this.delegate);

  final HttpClient delegate;
  bool closed = false;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (_redirect case final endpoint?) {
      return delegate.openUrl(method, endpoint);
    }
    if (url.host != '127.0.0.1') throw const SocketException('offline');
    return delegate.openUrl(method, url);
  }

  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;

  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;

  @override
  void close({bool force = false}) {
    closed = true;
    delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
