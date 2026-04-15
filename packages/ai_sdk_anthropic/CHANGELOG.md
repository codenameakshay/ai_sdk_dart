## 1.1.0

### New Features

- **`AnthropicThinkingOptions`** — typed options for Claude's extended thinking (reasoning) API.
  - `budgetTokens` — maximum tokens to allocate for the thinking block.
  - `enabled` — whether thinking is active (default `true`).
  - `speed: 'fast'` — convenience shorthand that disables the thinking block for lower-latency responses.
  - Use via `providerOptions: {'anthropic': AnthropicThinkingOptions(budgetTokens: 5000).toMap()}`.
- **`AnthropicLanguageModelOptions`** — top-level wrapper for Anthropic provider options; currently wraps `AnthropicThinkingOptions`.

---

## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Depends on `ai_sdk_dart` 1.0.0.

- `anthropic('claude-sonnet-4-5')` factory — create language model instances.
- Full SSE streaming with `thinking` content block → `ReasoningPart` mapping.
- `tool_use` content block → `ToolCallPart` mapping.
- Tool choice mapping (Anthropic wire format).
- Tool input examples forwarding via description enrichment.
- Usage extraction from both `message_start` and `message_delta` events.
- Source, file content, and raw finish reason forwarding.
- Configurable `baseUrl`.

---

## 0.2.0

- Initial release.
- `anthropic(modelId)` factory for language model instances.
- Full SSE streaming with extended thinking support.
- Tool choice mapping (Anthropic wire format).
- Tool input examples forwarding via description enrichment.
- Source and file content extraction.
- Provider metadata and raw finish reason forwarding.