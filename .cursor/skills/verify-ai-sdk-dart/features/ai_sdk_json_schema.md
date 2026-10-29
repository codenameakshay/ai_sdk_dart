# ai_sdk_json_schema

Optional runtime validation for tool inputs and structured outputs. `validatedJsonSchema` compiles a local JSON Schema (Draft 7 or 2020-12) into a core `Schema` that validates the value before the decoder runs. `JsonSchemaValidator` is the validator on its own. A bad tool input never reaches the tool, and a bad structured output never becomes a typed object.

## Sub-features

- `js-validate` accepts a valid nested value and throws `SchemaValidationException` for a wrong type, bad enum value, missing required field, extra property and nested violation. `format` is an annotation and is not asserted.
- `js-errors` gives each issue an instance path, a schema path and a message. `toString()` omits the rejected value.
- `js-dialects` supports Draft 7 and 2020-12 (the default), resolves local `$ref`, and refuses external `$ref` and unknown dialects at construction.
- `js-bounds` limits schema and value depth and node count with `maxDepth` and `maxNodes`, rejects non-finite numbers and cyclic schemas, and throws `ArgumentError` for non-positive limits.
- `js-snapshot` never runs the decoder for an invalid value, and freezes the schema so later edits to the source map change nothing.
- `js-tool-input` blocks a tool call with invalid input from running the tool, returns the error to the model, and runs the tool once for a valid call.
- `js-structured` validates `generateObject` and `Output.object` results, and wraps a violation in `AiNoObjectGeneratedError` with the `SchemaValidationException` as `cause`.
- `js-stream-object` emits unvalidated partial snapshots from `streamObject` and validates only the final object.

## How to get to it (user POV)

- Call `validatedJsonSchema<T>(schema: {...}, fromJson: ...)`. Pass the result to `tool(inputSchema:)`, `generateObject(schema:)`, `streamObject(schema:)` or `Output.object(schema:)` from `ai_sdk_dart`.
- Use `JsonSchemaValidator(schema).validate(value)` to get the list of issues without throwing.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. The integration checks use an in-process fixture server in the Chat Completions format.

- **All checks.** Run `$V run json_schema`. Output `9 passed, 0 failed, 0 skipped`.
- **Valid and invalid.** Run `$V run json_schema --check accepts-valid-rejects-invalid`. In `ai_sdk_json_schema/accepts-valid-rejects-invalid.json`, `observed` has an `.issues` list for each of the six invalid cases.
- **Issue detail.** Run `$V run json_schema --check issue-detail-without-values`. `observed.paths` has `/city` and `/days/0/temperature`. `observed.schemaPaths` has the matching `/properties/...` paths.
- **Dialects.** Run `$V run json_schema --check dialects-and-refs`. `observed` shows `dialect.default`, the Draft 7 and the 2020-12 runs as `validated`.
- **Bounds.** Run `$V run json_schema --check json-bounds`. `observed.deepIssue`, `observed.wideIssue` and `observed.nanIssue` all say `exceeds configured JSON limits`.
- **Snapshot.** Run `$V run json_schema --check validate-before-decode-and-snapshot`. The check passes only if the decoder ran once, for the valid value.
- **Tool input.** Run `$V run json_schema --check tool-input-rejected`. `observed.executions` is `0` for the invalid call and `toolResultIsError` is `true`. `observed.errorSentToModel` holds the tool message the second request carried.
- **Structured output.** Run `$V run json_schema --check generate-object-output`. The first request body has `response_format.type` `json_schema`. `observed.causePaths` is `[/city]`.
- **Output.object.** Run `$V run json_schema --check output-object-text`. `observed.errorType` is `AiNoObjectGeneratedError`.
- **Stream object.** Run `$V run json_schema --check stream-object-final-validation`. `observed.partials` has snapshots. `observed.errorType` names the final failure.

## Gotchas

- Not covered: provider-specific schema subsets. The package does not certify them, and each provider package owns its own limits.
- Partial snapshots from `streamObject` are never validated. Only `object` and `stream` are. A failed final object also ends `partialObjectStream` with the same error.
- `generateObject` has no `maxRetries` option. Use `generateText` with `Output.object` when a check needs retry control.
- `SchemaValidationException.toString()` shows only the issue count. Read `issues` for the paths.
