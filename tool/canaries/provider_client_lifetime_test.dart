import 'dart:io';

import 'package:test/test.dart';

import 'provider_canaries.dart';

void main() {
  for (final provider in ['openai', 'anthropic', 'google']) {
    test(
      '$provider canary closes its owned HTTP client after failure',
      () async {
        final client = _FailingClient();
        await HttpOverrides.runZoned(() async {
          await expectLater(
            runProviderCanary(
              ProviderCanaryConfig(
                name: provider,
                apiKey: 'test',
                model: 'test',
              ),
            ),
            throwsA(anything),
          );
        }, createHttpClient: (_) => client);
        expect(client.requests, 1);
        expect(client.closes, 1);
      },
    );
  }
}

class _FailingClient implements HttpClient {
  var requests = 0;
  var closes = 0;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests++;
    throw const SocketException('offline canary failure');
  }

  @override
  void close({bool force = false}) => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
