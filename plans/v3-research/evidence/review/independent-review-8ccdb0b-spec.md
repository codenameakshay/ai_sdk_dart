# Independent SPEC review: `8ccdb0b`

Scope: read-only implementation review against W01-W20, ADR 0005 and the v3 contract matrix. W19/W20 are admission/proposal work only. Local coverage is reported as 13,563/13,695 (99.04%) at this head; CI on `8ccdb0b` was still running, so this is not a CI coverage claim.

## Requirements missing or partial

- **W06/W07, W08: protocol and provider qualification remains partial.** The matrix says “hosted lifecycle semantics incomplete” and calls for “actual two-turn provider fixtures” (docs/v3-contract-matrix.md:21,36,40-41). Capability declarations and offline tests do not close real-model/cancellation/continuation qualification. The execution ledger also leaves provider capability tables and actual HTTP cancellation open (plans/v3-execution.md:14,37-38,141).
- **W09: lossless persisted provider metadata remains partial.** “Metadata preservation across persisted conversation replay remains under repair”; opaque/custom content and redacted reasoning replay still need qualification (docs/v3-contract-matrix.md:37-44). This is distinct from the codec's local round-trip tests.
- **W13/W14/W18 and release evidence remain partial.** The plan requires “demonstrated allocation/frame improvement” (plans/v3.0.0-report.md:604), platform “profile/accessibility runs where required” and selected live canaries (lines 567-568). Current checkpoint leaves Flutter frame/raster evidence, credentialed canaries, realtime device audio and browser rebuild open (plans/v3-execution.md:141). Live canaries and device audio are external qualification gaps, not grounds to drop those requirements. iOS debug runs do not establish profile-mode frame/raster results.

## Scope creep

None confirmed. W19 says demand/ownership must precede expansion, and W20 explicitly must not block core GA (plans/v3.0.0-report.md:610-611); the ledger records proposals/admission only, with no support claims (plans/v3-execution.md:25-26). Batch and realtime are within their explicitly scoped W17/W18 work packages.

## Implemented but wrong

- **Streaming request metadata omits prior assistant/tool messages.** `streamText` constructs `request.messages` by filtering normalized history to user/system roles (packages/ai_sdk_dart/lib/src/core/stream_text.dart:1060-1069), while `generateText` retains the full first-step messages (packages/ai_sdk_dart/lib/src/core/generate_text.dart:819-821). The matrix requires “Final-step and aggregate views [to] agree across streaming and non-streaming generation” (docs/v3-contract-matrix.md:68). With assistant/tool history, the public request metadata therefore disagrees across the two APIs.
