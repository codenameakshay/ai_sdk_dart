/// A JSON-compatible value type.
///
/// Represents any value that can be serialized to/from JSON.
typedef JsonValue = Object?; // null | bool | int | double | String | List | Map

/// A JSON object (map with string keys).
typedef JsonObject = Map<String, dynamic>;

/// Provider-specific options, keyed by provider name.
typedef ProviderOptions = Map<String, JsonObject>;
