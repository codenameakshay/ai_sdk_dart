## 0.2.0

- Initial release.
- `ChatController` — manages a chat message list, streams assistant replies, handles optimistic UI updates.
- `CompletionController` — single-turn text completion with streaming support.
- `ObjectStreamController` — streams partial structured objects with live UI updates.
- Full hook parity: `append`, `reload`, `clear`/`reset`, `isStreaming`, `onFinish`, `onError`.
