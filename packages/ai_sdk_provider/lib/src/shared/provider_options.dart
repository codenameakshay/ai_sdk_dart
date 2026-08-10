import 'dart:async';

/// Resolves a provider credential immediately before request dispatch.
typedef CredentialProvider = FutureOr<String?> Function();

/// Resolves provider-managed request headers immediately before dispatch.
typedef RequestHeadersProvider = FutureOr<Map<String, String>> Function();
