import 'json_value.dart';

/// Provider-specific metadata returned alongside model results.
///
/// The outer key is the provider name (e.g., 'openai', 'anthropic').
/// The inner map contains provider-specific key-value data.
typedef ProviderMetadata = Map<String, JsonObject>;
