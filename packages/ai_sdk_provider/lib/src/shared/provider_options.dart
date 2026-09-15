import 'dart:async';

import 'package:dio/dio.dart';

/// Resolves a provider credential immediately before request dispatch.
typedef CredentialProvider = FutureOr<String?> Function();

/// Resolves provider-managed request headers immediately before dispatch.
typedef RequestHeadersProvider = FutureOr<Map<String, String>> Function();

/// Joins a provider base URL and an absolute request path without changing
/// interior path segments or producing double slashes at the join point.
String providerEndpoint(String baseUrl, String path) {
  final normalizedBase = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '$normalizedBase$normalizedPath';
}

/// Builds a provider [Dio] client with a trailing slash trimmed from
/// [baseUrl] and a JSON response type.
Dio createProviderDio({
  required String baseUrl,
  Map<String, String> headers = const {},
}) {
  final trimmedBaseUrl = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return Dio(
    BaseOptions(
      baseUrl: trimmedBaseUrl,
      headers: headers,
      responseType: ResponseType.json,
    ),
  );
}
