## 3.1.0

- No changes. Released with the other AI SDK Dart packages at 3.1.0; sibling
  constraints now require `^3.1.0`.

---

## 3.0.0

- Add optional local Draft 7 and 2020-12 runtime validation for AI SDK Dart.
- Reject remote references, unsupported dialects, and out-of-bounds JSON trees.
- Enforce `maxNodes` before traversing additional siblings so broad inputs cannot exceed the configured work bound.
