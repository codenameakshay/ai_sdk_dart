# v3 execution and qualification ledger

Baseline: `b702929811281ac6be4c5ea2c10004b412b74924`. Scope and acceptance criteria: [approved report](v3.0.0-report.md). A passing focused test does not satisfy release qualification. No package publication or merge is authorized by this ledger.

| Work | Scope | Status | Evidence / outstanding gates |
|---|---|---|---|
| W01 | Stream settlement and response-message correctness | Implemented; review pending | Parent core snapshot699 passed before current approval changes; targeted cleanup/replay tests pass; final suite pending |
| W02 | Embedding integrity and batching | In progress | Core integrity, provider cardinality, indexed OpenAI parsing, queue tests; cancellation and provider-limit qualification pending |
| W03 | v3 contract and migration decisions | Decision recorded; verification pending | `docs/adr/0005-v3-public-contract.md` freezes results/events/context/files/lifecycle/persistence and migration alias policy; compiled generation/custom-provider examples and field matrix exist; canonical streams/files and final migration audit pending |
| W04 | Uniform request lifecycle and schema validation | In progress | Core nontext abort/deadline propagation, structured-stream terminal fixes, optional schema adapter implemented; text startup/step/meaningful-first-chunk deadlines corrected and parent-tested; provider observer lifetime, final integration and migration gates pending |
| W05 | V7 result/event/tool policy alignment | In progress | Aggregate collections/usage and finalStep landed; parent corrected finish-event usage and per-step messages/metadata with tests. Canonical instructions/callbacks landed; exact approvals and distinct typed contexts are under review; legacy fixture migration and canonical streams pending |
| W06 | OpenAI Responses | In progress | Responses adapter and fixtures in review; duplicate-call fix, complete hosted-tool lifecycle and default migration qualification pending |
| W07 | Claude/Gemini current reasoning and native output | In progress | Real Gemini function-call ID/thought-signature and Anthropic signed/redacted reasoning replay fixtures landed; parent flagship190 passed before newer Files edits; wider capability/live qualification pending |
| W08 | Other provider correctness and capability descriptors | Pending | See report acceptance criteria |
| W09 | Typed conversation/persistence codec | Implemented; integration qualification pending | Deep JSON immutability/bounds, codec/IDs/extensions corrected after review; parent ran 8 tests and JSON persistence example, clean analysis. Remote/UI/local-agent integration remains |
| W10 | Remote/Vercel transport companion | In progress | Parent reference-server run passes 15 tests; auth cancellation, peer socket closure and detachable caller observation added; local/UI integration remains |
| W11 | Modern MCP and replay-safe requests | Implemented; qualification incomplete | Parent reran full MCP suite; modern/legacy fixture review and broader external conformance remain |
| W12 | MCP auth/progress and selected extensions | In progress | Issuer/protected-resource discovery and duplicate challenge rejection corrected; parent full MCP 139 passed, analysis clean; host owns login/PKCE/storage; selected extensions still need requirement audit |
| W13 | Structured-stream and Flutter performance | In progress | Persistent array snapshots and benchmark counters implemented; parent public consumer tests prove no snapshot allocation for element-only listeners and correct late-subscriber prefixes; fair timings and Flutter profiling remain |
| W14 | Framework recipes and accessibility | In progress | Dev-only Riverpod/Bloc recipes and disabled-stop fix exist; parent rejected reactive/lifecycle gaps; real framework tests and platform evidence pending |
| W15 | Observability and body minimization | In progress | Typed default-off body policy added to text/object and agent APIs; callback/provider-stream/error surfaces and fixture migration under review. Metrics/exporter and final privacy gates remain |
| W16 | Model catalog, docs, compatibility automation | In progress | Parent tooling tests 7 passed; analysis clean; catalog check validates 16 records/9 providers. Weekly offline freshness check added; broader compatibility coverage and release docs pending |
| W17 | Files and first batch adapter | In progress | Parent Files suite20 passed after lifecycle/metadata corrections; batch draft rejected for unusable request input and valid result decoding failures; corrections, unlistened/cleanup tests and live qualification pending |
| W18 | Realtime voice preview | Implementation in review | Optional package registered in workspace/test matrix; first draft rejected for missing transport auth and lifecycle gaps. Authenticated loopback handshake added; lifetime, bounds, identities, typed events and device proof remain incomplete |
| W19 | Enterprise/new provider expansion | Admission review recorded; demand/owner pending | `docs/proposals/provider-admission.md` records candidate-specific prerequisites and proof; no named adopter/owner or new verified-support claim |
| W20 | Durable workflow/harness/A2A/MCP Apps | Separate proposals written; admission pending | `docs/proposals/` defines boundaries, adopter/ownership gates, failure semantics and prototype proof for all four; no named adopter exists, no support claim, and these remain outside core GA per approved plan |

## Execution constraints

Initial Luna requests failed before execution with `model_not_found`. Fresh `gpt-5.6-luna` workers now execute successfully and own the active implementation tasks. `poteto-mode` was not found in the installed skill directories.

## Release gates

- [ ] Full tests, analysis, formatting, benchmark, coverage, package dry-runs
- [ ] Requirement-by-requirement core/provider/protocol fixtures
- [ ] Pinned upstream differential checks and remote reference server
- [ ] Live-provider canaries, with dated evidence and controlled spend
- [ ] Platform, UI accessibility, and realtime device qualification
- [ ] Before/after measurements and documented tradeoffs
- [ ] Independent standards/spec and no-comments review
- [ ] Commit, push, PR with evidence; do not merge or publish

Detailed current proof and tradeoffs: [reliability evidence](v3-research/reliability-implementation-evidence.md).

Luna service recovery: a fresh explicitly selected `gpt-5.6-luna` worker launched and completed a remote-auth cancellation review on 2026-09-23. Earlier startup failures do not describe current availability. It now owns the confirmed remote cancellation corrections.

Independent review findings: [checkpoint log](v3-review-checkpoints.md).

Environment qualification: `fvm flutter devices` currently reports Linux desktop only. OPENAI_API_KEY, ANTHROPIC_API_KEY and GOOGLE_API_KEY are not configured (presence only checked, no values printed). Live canaries and iOS/Android device qualification remain missing evidence, not replaced by mocks. `git fetch origin` found no commits beyond the baseline on main; draft PR #4 remains the only open PR.

Additional parent verification: provider contract suite 30 tests passed; conversation suite 8 passed; aggregate-result review regressions 2 passed. Conversation persistence and custom embedding provider examples ran successfully. These focused results are not a current full-matrix pass. An attempted full run encountered a conversation file mid-edit and was stopped; rerun when owners finish.

Historical checkpoint, superseded by later runs below: the pinned JavaScript reference server (`ai` 7.0.111) was started locally after `npm ci`; `AI_SDK_REMOTE_REFERENCE_URL=http://127.0.0.1:8081/chat fvm dart test packages/ai_sdk_remote/test` passed all 9 tests, including request validation and approval history. `fvm dart test packages/ai_sdk_mcp/test` passed all 138 tests, including protected-resource and authorization-server discovery. The core worker reports 689 core tests passing after strict final-JSON expectation corrections; an independent final run remains pending. Review found that text deadlines do not cancel provider work and remote auth-header acquisition is not cancellable; both are assigned for correction before release qualification.

Parent integration observation (2026-09-23): `make analyze` failed in Flutter UI test helpers because new agent named parameters and required result `finalStep` were not migrated. Core also reported three lint infos. Owners have the diagnostics; this is not a green final matrix. Open draft PR #4 remains unchanged and is the sole open PR.

Additional verified packaging/example checkpoint: conversation and remote package dry-runs both exited0 with zero warnings. The new `packages/ai_sdk_remote/example/example.dart` ran against the pinned JS reference backend and printed its expected greeting; focused analysis and format check passed. The approval replay prevalidation regression passed after fingerprint recomputation was corrected. Files focused suite20 passed independently. None of these substitute for final full-matrix gates.

Web compilation checkpoint: `fvm dart compile js packages/ai_sdk_remote/example/example.dart -o /tmp/v3-remote-example.js` exited0. This verifies the pure Dart remote example compiles for web; browser runtime/auth/cancellation qualification remains separate. `git diff --check` passed at this checkpoint.

Current ownership: fresh Luna `approval_contract_completion` replaces the stopped `responses_adapter` for remaining W05 tests/context/replay corrections; `provider_readiness` owns Flutter lifecycle/helper migration and subsequent local approval resume; `luna_availability_check` owns OpenAI Files edge cases and experimental batch. W15/canonical stream, W03 media variants, W08 provider lifecycle, W13 final benchmarks, W18 implementation and final release gates remain pending; preserve their scope.

Latest ownership supersedes the preceding historical entry: `approval_contract_completion` owns core W15 and the remote pre-listen cancellation correction; `flutter_resume_completion` owns Flutter/conversation approval replay, framework lifecycle and media integration; `luna_current_probe` owns final OpenAI Files/Batch corrections and the W18 session implementation. All three use working Luna workers.

Parent lifecycle checkpoint: `fvm dart test packages/ai_sdk_openai/test/openai_batch_test.dart packages/ai_sdk_openai/test/openai_files_test.dart packages/ai_sdk_openai/test/openai_batch_wire_regression_test.dart packages/ai_sdk_openai/test/responses_cancellation_test.dart` passed **41** tests (`/tmp/v3-openai-lifecycle-parent-current.log`). This includes the formerly failing pre-cancelled Responses auth regressions. Full OpenAI and Flutter suites still need reruns after W15 signature migrations settle. Parent duplicate-approval regression initially failed to load because Flutter fake agents lacked the new `bodyInclusion` argument; it is not yet runtime proof.

Subsequent parent checkpoint: full core **714 passed** (`/tmp/v3-core-w15-parent-tests.log`), full OpenAI **111 passed** (`/tmp/v3-openai-parent-after-w15.log`). The two parent Flutter race regressions also passed (`/tmp/v3-ui-parent-races-current.log`): duplicate approval during a gated tool execution runs the tool once, and concurrent Bloc replacement leaves the final subscription active. The duplicate test first failed to compile, then ran after the worker's guard was present; do not claim a reproduced runtime failure. Core analysis compiles but reports four lint infos. W15 assertions still need direct provider-stream, object, callback and raw-inclusion proof; these counts do not close those requirements.

Browser checkpoint: the advanced Flutter example built for web successfully and its offline approval fixture passed real Chromium keyboard-approval and pointer-denial checks at desktop/narrow viewport sizes, with zero captured page errors. Screenshots and exact limitations are in `v3-research/evidence/browser/README.md`. This is fixture UI proof, not persisted-tool execution, live-provider evidence, mobile-device evidence, or final-build qualification. The source is still changing.
