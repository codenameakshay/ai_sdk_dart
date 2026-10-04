import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final issuer = Uri.parse('https://auth.example/tenant');
  Map<String, dynamic> metadata() => {
    'issuer': issuer.toString(),
    'authorization_endpoint': 'https://auth.example/authorize',
    'token_endpoint': 'https://auth.example/token',
  };

  test('OAuth discovery retains issuer path after well-known prefix', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path ==
          '/.well-known/oauth-authorization-server/tenant') {
        return http.Response(jsonEncode(metadata()), 200);
      }
      return http.Response('', 404);
    });
    addTearDown(client.close);
    final result = await MCPAuthDiscovery.authorizationServer(
      issuer,
      client: client,
    );
    expect(result.issuer, issuer);
    expect(
      requests.single.path,
      '/.well-known/oauth-authorization-server/tenant',
    );
  });

  test('OIDC fallback appends well-known suffix to issuer path', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return request.url.path == '/tenant/.well-known/openid-configuration'
          ? http.Response(jsonEncode(metadata()), 200)
          : http.Response('', 404);
    });
    addTearDown(client.close);
    final result = await MCPAuthDiscovery.authorizationServer(
      issuer,
      client: client,
    );
    expect(result.issuer, issuer);
    expect(requests.last.path, '/tenant/.well-known/openid-configuration');
  });

  for (final endpoint in [
    '',
    '/token',
    'javascript:token',
    'http://auth.example/token',
    'https://user:secret@auth.example/token',
    'https://auth.example/token#fragment',
  ]) {
    test('rejects invalid token endpoint $endpoint', () {
      expect(
        () => MCPAuthorizationServerMetadata.fromJson({
          ...metadata(),
          'token_endpoint': endpoint,
        }, issuer),
        throwsA(isA<MCPException>()),
      );
    });
  }

  test('protected resource rejects relative authorization server', () {
    expect(
      () => MCPProtectedResourceMetadata.fromJson({
        'resource': 'https://mcp.example/api',
        'authorization_servers': ['/issuer'],
      }),
      throwsA(isA<MCPException>()),
    );
  });

  test('loopback HTTP discovery remains available for native hosts', () {
    final local = Uri.parse('http://127.0.0.1:3456');
    final result = MCPAuthorizationServerMetadata.fromJson({
      'issuer': local.toString(),
      'authorization_endpoint': '$local/authorize',
      'token_endpoint': '$local/token',
    }, local);
    expect(result.issuer, local);
  });

  test(
    'prefers Bearer resource_metadata and does not forward credentials',
    () async {
      final requests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.url.toString(), 'https://mcp.example/meta');
        return http.Response(
          jsonEncode({
            'resource': 'https://mcp.example/public/mcp',
            'authorization_servers': ['https://auth.example'],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final result = await MCPAuthDiscovery.discoverProtectedResource(
        Uri.parse('https://mcp.example/public/mcp'),
        wwwAuthenticate:
            'Basic realm="a,b", Bearer realm="mcp", resource_metadata="https://mcp.example/meta"',
        client: client,
      );
      expect(result.resource, Uri.parse('https://mcp.example/public/mcp'));
      expect(requests, hasLength(1));
    },
  );

  test(
    'falls back from path insertion to root protected-resource metadata',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/.well-known/oauth-protected-resource') {
          return http.Response(
            jsonEncode({
              'resource': 'https://mcp.example/public/mcp',
              'authorization_servers': ['https://auth.example'],
            }),
            200,
          );
        }
        return http.Response('', 404);
      });
      addTearDown(client.close);
      await MCPAuthDiscovery.discoverProtectedResource(
        Uri.parse('https://mcp.example/public/mcp'),
        client: client,
      );
      expect(requests.map((uri) => uri.path), [
        '/.well-known/oauth-protected-resource/public/mcp',
        '/.well-known/oauth-protected-resource',
      ]);
    },
  );

  test(
    'rejects malformed, ambiguous, and mismatched resource metadata',
    () async {
      expect(
        () => MCPAuthDiscovery.discoverProtectedResource(
          Uri.parse('https://mcp.example/mcp'),
          wwwAuthenticate: 'Bearer resource_metadata="/relative"',
        ),
        throwsA(isA<MCPException>()),
      );
      expect(
        () => MCPAuthDiscovery.discoverProtectedResource(
          Uri.parse('https://mcp.example/mcp'),
          wwwAuthenticate:
              'Bearer resource_metadata="https://mcp.example/a", Bearer resource_metadata="https://mcp.example/b"',
        ),
        throwsA(isA<MCPException>()),
      );
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'resource': 'https://other.example/mcp',
            'authorization_servers': ['https://auth.example'],
          }),
          200,
        ),
      );
      addTearDown(client.close);
      expect(
        () => MCPAuthDiscovery.discoverProtectedResource(
          Uri.parse('https://mcp.example/mcp'),
          wwwAuthenticate:
              'Bearer resource_metadata="https://mcp.example/meta"',
          client: client,
        ),
        throwsA(isA<MCPException>()),
      );
    },
  );

  test('rejects duplicate metadata parameters before making a request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response(
        jsonEncode({
          'resource': 'https://mcp.example/mcp',
          'authorization_servers': ['https://auth.example'],
        }),
        200,
      );
    });
    addTearDown(client.close);
    await expectLater(
      MCPAuthDiscovery.discoverProtectedResource(
        Uri.parse('https://mcp.example/mcp'),
        wwwAuthenticate:
            'Bearer resource_metadata="https://mcp.example/a", resource_metadata="https://mcp.example/b"',
        client: client,
      ),
      throwsA(isA<MCPException>()),
    );
    expect(calls, 0);
  });

  test('discovers metadata through an actual loopback 401 flow', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final resource = Uri.parse(
      'http://${server.address.host}:${server.port}/mcp',
    );
    final metadata = Uri.parse(
      'http://${server.address.host}:${server.port}/.well-known/oauth-protected-resource/mcp',
    );
    server.listen((request) async {
      if (request.uri.path == '/mcp') {
        request.response
          ..statusCode = 401
          ..headers.set(
            'www-authenticate',
            'Bearer resource_metadata="$metadata"',
          );
      } else if (request.uri.path == metadata.path) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'resource': resource.toString(),
              'authorization_servers': [
                'http://${server.address.host}:${server.port}/auth',
              ],
            }),
          );
      } else if (request.uri.path == '/auth/.well-known/openid-configuration') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'issuer': 'http://${server.address.host}:${server.port}/auth',
              'authorization_endpoint': '$resource/authorize',
              'token_endpoint': '$resource/token',
            }),
          );
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final client = http.Client();
    addTearDown(client.close);
    final unauthorized = await client.get(resource);
    final protected = await MCPAuthDiscovery.discoverProtectedResource(
      resource,
      wwwAuthenticate: unauthorized.headers['www-authenticate'],
      client: client,
    );
    expect(protected.resource, resource);
    final auth = await MCPAuthDiscovery.authorizationServer(
      protected.authorizationServers.single,
      client: client,
    );
    expect(auth.issuer, protected.authorizationServers.single);
  });
}
