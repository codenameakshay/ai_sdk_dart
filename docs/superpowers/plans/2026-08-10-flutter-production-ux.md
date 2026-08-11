# Flutter Production UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default Flutter chat surface cancellable, race-safe, accessible, performant, and complete for errors, approvals, tools, and sources.

**Architecture:** Controllers own request lifecycle and expose narrowly observable state. Widgets compose default production states with builder overrides and frame-coalesced rendering.

**Tech Stack:** Flutter Material, `ChangeNotifier`, widget/semantics tests, existing UI primitives.

---

### Task 1: Controller abort and supersession

**Files:**
- Modify: `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart`
- Modify: `packages/ai_sdk_flutter_ui/lib/src/completion_controller.dart`
- Modify: `packages/ai_sdk_flutter_ui/lib/src/object_stream_controller.dart`
- Test: corresponding controller tests

- [ ] Add failing tests proving Stop cancels the upstream token and a second send prevents stale first-request deltas, errors, and finish events from changing state.
- [ ] Give each invocation a cancellation token and monotonically increasing request ID.
- [ ] Abort and dispose the active invocation before replacement, reset, or controller disposal.
- [ ] Ignore events whose request ID is no longer active and run controller suites; commit.

### Task 2: Frame-coalesced notifications

**Files:**
- Create: `packages/ai_sdk_flutter_ui/lib/src/frame_notifier.dart`
- Modify: the three controller files
- Test: controller and scaffold tests

- [ ] Add a failing test that emits many synchronous deltas and expects one scheduled visual notification per frame while final state contains all text.
- [ ] Implement a scheduler-injected frame notifier with immediate terminal-state delivery.
- [ ] Split generation/composer status observation from conversation-data observation without changing high-level controller usability.
- [ ] Run tests and commit.

### Task 3: Reader-respecting scroll behavior

**Files:**
- Modify: `packages/ai_sdk_flutter_ui/lib/src/widgets/chat_message_list.dart`
- Modify: `packages/ai_sdk_flutter_ui/lib/src/widgets/scroll_to_bottom_button.dart`
- Test: `packages/ai_sdk_flutter_ui/test/widgets/chat_message_list_test.dart`

- [ ] Add failing tests for pinned-at-bottom streaming, scrolled-up streaming, manual return, and reduced motion.
- [ ] Track a bottom threshold from scroll notifications; auto-pin only when already inside it.
- [ ] Use an instant jump when animations are disabled and ensure one scroll operation per frame.
- [ ] Run widget tests and commit.

### Task 4: Complete default scaffold states

**Files:**
- Modify: `packages/ai_sdk_flutter_ui/lib/src/widgets/ai_chat_scaffold.dart`
- Reuse: `assistant_message_view.dart`, `chat_error_view.dart`, `tool_approval_card.dart`, `source_citations.dart`
- Test: `packages/ai_sdk_flutter_ui/test/widgets/ai_chat_scaffold_test.dart`

- [ ] Add failing tests for inline error/retry, pending approval actions, source/tool rendering, composer disabled state during approval, and custom builders.
- [ ] Compose existing production primitives into the scaffold and add narrowly typed error/approval/status builder overrides.
- [ ] Make retry repeat the last safe request and make dismissal explicit.
- [ ] Run scaffold/controller tests and commit.

### Task 5: Accessibility contract

**Files:**
- Modify: `chat_composer.dart`, `chat_message_list.dart`, `typing_indicator.dart`, `message_media.dart`, and affected action widgets
- Test: existing widget tests plus `ai_motion_test.dart`

- [ ] Add failing semantics tests for Send, Stop, message roles, image/file labels, approval actions, streaming status, and scroll-to-bottom.
- [ ] Add tooltips and semantic labels to every icon-only control.
- [ ] Mark messages with concise role semantics and announce generation state changes through a restrained live region rather than token-by-token text.
- [ ] Honor `MediaQuery.disableAnimations` for typing, cursor, expansion, and scrolling; verify focus traversal and minimum targets.
- [ ] Run the full Flutter UI suite and commit.

### Task 6: Example glitches and visual fixtures

**Files:**
- Modify: `examples/advanced_app/lib/pages/tools_chat_page.dart`
- Modify: example widget tests
- Create/update screenshot-driving fake states in the advanced example

- [ ] Add a failing test proving sources reset for a new turn and reduced motion prevents animated token scrolling.
- [ ] Fix per-turn source ownership and reuse the shared near-bottom behavior.
- [ ] Add deterministic routes/states for normal chat, approval, error, sources/tool, and long-history screenshots.
- [ ] Run both example suites and commit.

