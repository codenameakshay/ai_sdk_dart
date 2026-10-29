# ai_sdk_conversation

Immutable, versioned conversation snapshots and the JSON codec that saves and restores them (`Conversation`, `ConversationMessage`, the part classes and `ConversationCodec`). A developer builds a snapshot, stores the encoded map in any JSON store, and decodes it later. The package makes no network call and runs no tool. `ai_sdk_remote` and `ai_sdk_flutter_ui` build on it.

## Sub-features

- `conv-roundtrip` encodes a snapshot with every part type to a JSON map, and decodes it back to an equal value with identical JSON.
- `conv-files` stores file, image and redacted-reasoning bytes inline as base64, restores them byte for byte, and round trips URI and provider-reference files.
- `conv-version` accepts schema version 1 and raises `ConversationSchemaException` for any other, missing or non-integer version.
- `conv-validation` raises `ConversationValidationException` for duplicate message, part or call ids, orphan tool results or approvals, a pending-approval message without a pending approval, empty ids, bad statuses and non-object input.
- `conv-json` copies metadata, arguments and outputs into immutable containers, and rejects cycles, non-finite numbers, non-JSON values, depth above 64 and more than 10,000 nodes.
- `conv-extensibility` keeps unknown part types and extension fields on the conversation, messages and parts.
- `conv-states` round trips interrupted, pending, streaming, failed and pending-approval messages. Pending approval uses the wire name `pending_approval`.
- `conv-no-exec` decodes a snapshot with a pending approval, preserves the recorded call and creates no tool result.
- `conv-agent-turn` saves a `ToolLoopAgent` turn that stopped at an approval, restores it from JSON text, and resumes from the restored ids. An approval runs the tool once. A denial never runs it.

## How to get to it (user POV)

- Build a `Conversation(id:, messages:)` from `ConversationMessage` and part objects. Use `ConversationCodec.encode` to get a map and `ConversationCodec.decode` to read it back.
- `ai_sdk_remote` returns `Conversation` snapshots from `RemoteConversationTransport.send`. `ai_sdk_flutter_ui` keeps one as its controller state.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Only `conv-agent-turn` uses a fixture server, which answers in the Chat Completions format.

- **All checks.** Run `$V run conversation`. Output `9 passed, 0 failed, 0 skipped`.
- **Round trip.** Run `$V run conversation --check roundtrip-all-parts`. In `ai_sdk_conversation/roundtrip-all-parts.json`, `observed.schemaVersion` is `1` and `observed.partTypes` lists 13 part types in order.
- **Files.** Run `$V run conversation --check file-data-forms`. `observed.bytesWire` is `{kind: bytes, base64: ...}`, and `observed.badBase64Error` names the invalid base64.
- **Version.** Run `$V run conversation --check schema-version`. Each `version <x>.error` entry in `observed` is a `ConversationSchemaException`.
- **Validation.** Run `$V run conversation --check reject-malformed`. Each `<case>.error` entry in `observed` names the broken rule, for example `Duplicate tool call id "x"`.
- **JSON bounds.** Run `$V run conversation --check json-bounds-immutability`. `observed` has one error for each of `cycle`, `NaN`, `infinity`, `non-JSON object`, `depth 70` and `node count`.
- **Extensions.** Run `$V run conversation --check unknown-and-extension-preserved`. `observed.reencoded` still has `x-conv`, `x-message`, `x-part` and the `hologram` part.
- **States.** Run `$V run conversation --check interrupted-and-pending-approval`. `observed.wireStatuses` is `[interrupted, pending_approval, pending, streaming, failed]`.
- **Pending call.** Run `$V run conversation --check decode-does-not-execute-tools`. `observed.toolCall` retains the `delete` call, its `call-1` id and `/tmp/x` input. `observed.approvalStatus` is `pending`, and the decoded message has no tool result. The codec accepts no tool registry. Actual execution gating is checked by `agent-turn-snapshot-and-resume`.
- **Agent turn.** Run `$V run conversation --check agent-turn-snapshot-and-resume`. `exchanges` has three requests. `observed.executionsAfterDenial` is `0` and `observed.executionsAfterApproval` is `1`. The last request ends with a `tool` message for `call_verify_1`.

## Gotchas

- Not covered: `LocalConversationBackend` and `RemoteConversationBackend`. They live in `ai_sdk_flutter_ui`, which needs the Flutter SDK. The driver is a plain Dart package. `conv-agent-turn` drives the same `ToolLoopAgent` approval resume that `LocalConversationBackend` uses, with a snapshot built by the check.
- The codec has no `ConversationBackend` or HTTP part. The application assigns every id and decides when to save.
- Typed bytes are stored inline as base64, so the JSON grows with the file size. Strip or move the bytes before saving to a store with a size limit.
- Encoded maps compare by value, but key order follows insertion order. Compare parsed JSON, not strings, when the order does not matter.
- Restoring a pending approval does not authorize anything. The app must check the call and policy version before it resumes.
