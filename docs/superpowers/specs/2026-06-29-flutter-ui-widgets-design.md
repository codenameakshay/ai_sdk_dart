# ai_sdk_flutter_ui — fill the prebuilt-widget gaps

Date: 2026-06-29
Status: Approved
Package: `packages/ai_sdk_flutter_ui`

## Problem

The package ships 3 controllers (`ChatController`, `CompletionController`,
`ObjectStreamController`) and 8 prebuilt widgets. A gap analysis found that the
controllers expose state no widget renders, and several common chat-UI surfaces
are missing entirely. This work fills those gaps.

## Constraints (existing package philosophy — must hold)

- **Zero heavy dependencies.** Only `flutter`, `ai_sdk_dart`, `ai_sdk_provider`.
  Attachments, link-opening, pickers, and markdown stay out via callbacks/slots.
- **Theme-driven.** Everything reads `Theme.of(context)`.
- **Two widget shapes already in the codebase:** pure data+callback widgets
  (e.g. `ToolCallCard`, `SourceCitations`) and controller-bound widgets
  (e.g. `ChatMessageList`). New widgets follow one of these.
- **Additive & backwards-compatible.** No behavior change to existing widgets,
  controllers' existing paths, or their tests. The repo enforces a coverage
  gate, so every new unit ships with tests.

## Decisions

- **Markdown:** builder/slot only (`textBuilder` on `AssistantMessageView`, an
  optional `contentBuilder` on `ChatMessageBubble`). No built-in renderer, no
  dependency.
- **Scope:** widgets **plus** additive controller surfacing so the widgets are
  plug-and-play.
- **Reasoning/sources/tools/usage** are captured as **latest-turn** controller
  state (not retained per historical message) to avoid changing how assistant
  messages are stored.

## Controller surfacing (additive)

`ChatController`:
- `ChatStatus.awaitingApproval` — new enum value (does not flip `isLoading`).
- `List<LanguageModelV3ToolApprovalRequestPart> pendingApprovalRequests`.
- Pause/resume: a turn that stops for approval does **not** commit a partial
  assistant message; it exposes the requests and sets `awaitingApproval`.
  `addToolApprovalResponse(...)` removes the matched request and, once all
  pending requests are answered, **replays** the turn via
  `agent.stream(messages:, toolApprovalResponses:)`.
- Latest-turn capture: `lastUsage`, `streamingReasoning` (live, from
  `fullStream` reasoning deltas) + `reasoningText` (final), `lastSources`,
  `lastToolCalls`, `lastToolResults` — gathered in a finalize step that awaits
  the `StreamTextResult` futures.

`CompletionController`:
- `lastUsage`.

`ObjectStreamController`: no change (already exposes `value`/`isStreaming`/`error`).

## New widgets (`lib/src/widgets/`, exported from `widgets.dart`)

| Widget | Kind | Inputs |
|---|---|---|
| `ChatErrorView` | pure | `error`, `onRetry?`, `onDismiss?` |
| `ToolApprovalCard` | pure | `request`, `onApprove(reason?)`, `onDeny(reason?)` |
| `AssistantMessageView` | pure | `message` (reads `.parts`), `textBuilder?`, `onSourceTap?`, approval callbacks |
| `MessageImage` / `MessageAttachment` (`message_media.dart`) | pure | `LanguageModelV3ImagePart` / `LanguageModelV3FilePart` |
| `ObjectStreamView` | controller-bound | `ObjectStreamController`, optional `builder` |
| `MessageActionsBar` | pure | `onCopy?`/text, `onRegenerate?`, optional 👍/👎 |
| `ScrollToBottomButton` | pure | `ScrollController` |
| `PromptSuggestions` | pure | `List<String>`, `onSelected` |
| `TypingIndicator` | pure | optional `label` |
| `UsageView` | pure | `LanguageModelV3Usage` |

## Multimodal rendering

`LanguageModelV3ImagePart`/`FilePart` carry `LanguageModelV3DataContent`, a
sealed union of `DataContentBytes` (→ `Image.memory`), `DataContentBase64`
(→ `Image.memory(base64Decode(...))`), and `DataContentUrl` (→ `Image.network`).
All renderable with core Flutter — no dependency.

## Out of scope

- No new dependencies; no built-in markdown parser.
- No changes to the `advanced_app` example or the already-modified iOS files.
- One commit at the end.

## Testing

Widget tests (pump + find) for every widget; controller unit tests for every
addition, including a sequenced mock model + a `requiresApproval` tool to
exercise the approval pause → resume loop. Build proceeds test-first (TDD).
