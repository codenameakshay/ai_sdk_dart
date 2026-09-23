# Conversation E2E catalog

This catalog is the source of truth for the offline iOS Simulator suite in
`integration_test/conversation_e2e_test.dart`.

## Navigation

The app starts on the `Chat` tab. The bottom navigation labels are `Chat`,
`Completion`, and `Object`. The local and remote conversation pages are
registered as `/conversation` and `/remote`, but the shipped shell has no
visible control that opens either route. The integration tests therefore boot
each page directly in a test `MaterialApp`.

The page app bar titles are `Local conversation` and `Remote conversation`.

## Shared conversation controls

The prebuilt scaffold exposes these semantic labels:

| State | Label or text |
| --- | --- |
| Composer hint | `Message…` |
| Send control | `Send message` |
| Active response control | `Stop response` |
| Active response status | `Assistant is responding…` |
| Approval status | `Approve the tool call to continue.` |
| Assistant message | `Assistant message` |
| User message | `User message` |
| Error action | `Retry` |
| Error action | `Dismiss` |

Stable widget keys used by the tests are `chat-composer-field`,
`chat-composer-send`, `chat-composer-stop`, `tool-approval-approve`,
`tool-approval-deny`, `chat-error-retry`, and `chat-error-dismiss`.

The approval card also has the semantic container label
`Tool approval required for <tool name>`. Its default title is `Approve tool
call?`, and its buttons are `Approve` and `Deny`. The conversation scaffold does
not enable the optional reason field.

## Local conversation

`LocalConversationPage` uses a keyless scripted model and the always-approval
`deleteFile` tool. Sending any nonempty message shows the user message, then an
approval request for `deleteFile` with `{"path":"/tmp/example"}`. While the
request is pending, the composer is disabled and approval is the only active
decision.

- Approve executes the tool exactly once and ends with one assistant answer:
  `Tool result: deleted /tmp/example`.
- Deny executes the tool zero times and ends with one assistant answer:
  `Tool denied; no local action ran.`.
- Both decisions remove the approval card and return the composer to editable
  state.

The fixture does not accept a configurable path or tool name. It intentionally
checks the execution count and exact result text.

## Remote conversation

The JS reference backend in `../../remote_backend/js` is static and requires no
provider key. The app endpoint defaults to
`http://127.0.0.1:8081/chat`; CI passes the same value through
`REMOTE_BACKEND_URL`.

- Ordinary text ends with `Hello from the pinned AI SDK backend.`.
- A user message containing `approval` requests the `delete` tool for
  `/tmp/reference`.
- Approval ends with `The scripted tool call was approved and resumed.`.
- Denial ends with `The scripted tool call was denied and resumed safely.`.

Each completed flow should expose one final assistant message and an editable
composer.

## Error behavior

The harness also drives the conversation scaffold with a failing backend. The
error banner shows the backend error text, `Retry`, and `Dismiss`; dismissing it
removes the banner. The shipped conversation adapter currently exposes a retry
button while its `reload()` implementation is empty, so retry behavior is
cataloged as a follow-up app fix rather than asserted as a successful retry.

## Fixture limits

`ChatPage`, `CompletionPage`, and `ObjectStreamPage` construct OpenAI models from
`OPENAI_API_KEY`; they are suitable for offline navigation checks only. The
conversation suite does not require an API key. The JS server is pinned by its
`package-lock.json` to AI SDK `7.0.111` and must be started before remote tests.
