## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Package renamed from `ai_sdk_flutter` → `ai_sdk_flutter_ui` to avoid conflicts with existing pub.dev packages. Depends on `ai_sdk_dart` 1.0.0.

- `ChatController` — manages a chat message list, streams assistant replies, handles optimistic UI updates. Implements `Listenable` for use with `ListenableBuilder`.
- `CompletionController` — single-turn text completion with streaming and status tracking.
- `ObjectStreamController<T>` — streams partial structured objects, providing live partial updates as JSON arrives.
- Full hook parity with Vercel AI SDK v6 React hooks: `append`, `reload`, `clear` / `reset`, `isStreaming`, `onFinish`, `onError`.

---

## 0.2.0

- Initial release.
- `ChatController` — manages a chat message list, streams assistant replies, handles optimistic UI updates.
- `CompletionController` — single-turn text completion with streaming support.
- `ObjectStreamController` — streams partial structured objects with live UI updates.
- Full hook parity: `append`, `reload`, `clear`/`reset`, `isStreaming`, `onFinish`, `onError`.