# Stable ids and turn metadata for ChatController messages

Status: accepted and implemented as Option A in `ai_sdk_flutter_ui`. The change is additive. `ChatController.messages` keeps its type and contents.

## Problem

`ChatController.messages` is a `List<ModelMessage>`. A `ModelMessage` has no id. It does not record the model that generated it, and it does not record that `stop()` cut a turn short. An app that shows "answered by Claude Opus" or a "stopped" marker must keep its own maps keyed by list index.

Index keys break when the list changes under them. A review of one multi-model chat app found six bugs from this bookkeeping:

- A marker moved to the wrong message after `stop()`, after a retry, or after a stop with no partial text.
- A regenerated answer took the old answer's state.
- Fast taps raced the index updates.

The JS AI SDK gives each `UIMessage` an `id` for this reason.

## Constraints

- Existing `List<ModelMessage>` consumers must not change. Widgets, `onFinish`, and the agent call keep `ModelMessage`.
- ADR 0005 keeps two shapes apart. `ModelMessage` is the prompt shape that `ChatController` sends to the agent. `ConversationMessage` in `ai_sdk_conversation` is the persistence shape, with part ids, validation, and a schema version. "A persistence codec is not a provider-prompt converter."
- `ConversationChatController` extends `ChatController` and reads a `Conversation` snapshot. Its messages already have ids and a `ConversationMessageStatus`. The new API must report those, not new ids.

## Options

### Option A. A `ChatMessage` entry next to `messages` (chosen)

```dart
class ChatMessage {
  final String id;
  final ModelMessage message;
  final ConversationMessageStatus status; // complete, or interrupted after stop()
  final String? provider;                 // agent.model.provider
  final String? modelId;                  // agent.model.modelId
  final LanguageModelV4FinishReason? finishReason;
}

List<ChatMessage> get chatMessages;       // new
List<ModelMessage> get messages;          // unchanged, derived from chatMessages
ChatController({..., String Function()? generateId}); // new optional argument
```

The controller stores one list of entries. `messages` maps each entry to its `ModelMessage`. The two views can not drift, because there is one list.

Reuse from `ai_sdk_conversation`:

- `ConversationMessageStatus` is the status type. A stopped turn is `interrupted`, the same value the conversation schema persists. `ChatController` re-exports this enum.
- `ConversationChatController.chatMessages` returns each snapshot message's `id` and `status` directly.

### Option B. Expose `List<ConversationMessage>` from `ChatController`

`ChatController` converts each `ModelMessage` to a `ConversationMessage` with generated part ids. It puts the model and finish reason in the untyped `metadata` map.

Rejected:

- It needs a full `ModelMessage` to `ConversationPart` converter for every content part type. ADR 0005 keeps that conversion out of the prompt path.
- Each turn would carry two id systems (message and part), and only the message id is useful here.
- Model and finish reason become string keys in a `Map<String, dynamic>`. A typo compiles and fails silently.
- Apps that want full `Conversation` snapshots already have `ConversationController`.

## Behavior

| Operation | Ids | Metadata |
| --- | --- | --- |
| `sendMessage` | New id for the user message. New id for the answer when it completes. | Answer has `provider`, `modelId`, `finishReason`. Status `complete`. |
| `stop()` with partial text | The partial answer gets a new id. | `status` is `interrupted`. `provider` and `modelId` are set. `finishReason` is null, because the model did not report one. |
| `stop()` with no text | No entry is added. | Nothing can attach to the next turn. |
| `reload` / `regenerate` | The old answer's id leaves the list. The new answer gets a new id. | Metadata of the agent that ran the reload. |
| `clear()` | `initialMessages` return with their first ids. Later ids are new. | |
| Error, then retry | The error adds no entry. The retry answer gets a new id. | Metadata of the retry. |
| Tool approval resume | One answer entry, added when the resumed turn completes. | Metadata of the resumed run. |
| `append` | New id. | No model metadata. |

An id never comes back after it leaves the list. State keyed by a removed id can not land on another message.

## Out of scope

- Caller-chosen ids for `append` and `initialMessages`. Ids are stable for the controller's lifetime. Apps that persist chats across restarts should use `ConversationController`.
- Model metadata for `ConversationChatController`. A `Conversation` snapshot does not store the model or finish reason, so those fields are null there.
- Per-message usage. `lastUsage` still covers the latest turn.
- A placeholder entry for the in-flight answer. `streamingContent` still carries the live text.
