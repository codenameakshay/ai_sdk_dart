# ai_sdk_json_schema

Optional runtime validation for AI SDK Dart. Core and Flutter UI do not depend on this package.

```dart
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';

final weatherSchema = validatedJsonSchema<Map<String, dynamic>>(
  schema: {
    'type': 'object',
    'required': ['city'],
    'properties': {'city': {'type': 'string'}},
    'additionalProperties': false,
  },
  fromJson: (json) => json,
);
```

Use the returned schema with `tool(inputSchema:)`, `generateObject`, `streamObject`, or `Output.object`. Validation runs before the decoder. Invalid tool arguments do not execute application code. `SchemaValidationException.issues` carries instance and schema paths; its `toString()` omits input values.

Supports JSON Schema Draft 7 and 2020-12 through `json_schema` 5.2.2. When `$schema` is absent, the adapter selects 2020-12. Unsupported dialect declarations fail during construction. `format` is treated as an annotation, not an assertion. Local `$ref` references resolve inside the supplied schema. External references are disabled; this package never fetches schemas or starts authentication flows.

By default, schema and value trees are limited to 64 levels and 100,000 nodes. `maxDepth` and `maxNodes` can be set at construction. Non-JSON values and nonfinite numbers fail validation. The schema sent to the provider is a frozen snapshot of the compiled schema.

Core `Schema` without a `validator` remains decoder-controlled; `Schema.decoderOnly` makes that choice explicit. JSON Schema sent to a provider does not by itself validate local data.

`streamObject.partialObjectStream` emits unvalidated JSON snapshots. Only its `object` future and `stream` decode a final typed value. Applications should render incomplete snapshots without treating them as a complete domain object.

The adapter does not certify all optional JSON Schema vocabularies or every provider's native schema subset. Provider-specific schema restrictions remain separate from local validation.
