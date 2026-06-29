# Product

> Scope: this document governs the **design surface** of the AI SDK Dart monorepo —
> the `ai_sdk_flutter_ui` package (controllers + prebuilt Material widgets) and the
> example apps that showcase it (`examples/flutter_chat`, `examples/advanced_app`).
> The other packages are non-UI providers and carry no design register.

## Register

brand

## Users

**Primary — Flutter/Dart developers building AI-powered apps.** Chat assistants,
copilots, structured-output features. Many arrive from the JavaScript/React AI SDK
world and expect the same `useChat` / `useCompletion` / `useObject` ergonomics. Their
context: they want to ship a credible, polished AI streaming UI *fast* — without
hand-rolling token streaming, tool-loop execution, human-in-the-loop approvals, and
error handling, and without the result looking generic or bolted-on. The job to be
done: drop in (or compose) an AI surface that feels native to their app and reads as
deliberately crafted straight out of the box.

**Ultimate audience — the people using those apps.** End users chatting with an
assistant on mobile, web, or desktop. The library's polish exists to earn *their*
trust: a stream that feels alive and responsive, states that never look broken.

## Product Purpose

`ai_sdk_flutter_ui` is the Flutter UI layer of AI SDK Dart. It pairs reactive
`ChangeNotifier` **controllers** (the Dart equivalents of the Vercel AI SDK React
hooks) with a small library of prebuilt, themeable **Material widgets** that render
their state. It exists so a developer can stand up streaming chat, single-turn
completion, and live structured-output UIs — with production behavior (token
streaming, tool calls, approvals, reasoning, source citations, usage) — in minutes.

Success: the default output looks *intentionally designed* rather than templated,
themes seamlessly into the host app, stays dependency-light, and composes from a
drop-in `AiChatScaffold` all the way down to individual primitives. The recognizable
craft of the widgets is itself the reason to adopt this over building it by hand —
that is what makes the design the product.

## Brand Personality

**Polished and opinionated.** Three working words: **precise, composed, unobtrusive.**

The library is opinionated about *craft* — spacing rhythm, motion, micro-interactions,
the choreography of streaming and loading states — and deferential about *identity*,
adopting the host app's `ColorScheme` and typography rather than imposing its own.
Confident defaults that feel like a senior engineer already made the right calls;
no flourish for its own sake. To the developer it should feel trustworthy and finished;
to the end user the AI surface should feel alive and responsive without feeling gimmicky.

## Anti-references

- **Heavy branded chat SDKs** (Intercom/Drift-style widgets, "powered-by" bubbles)
  that impose their own look and resist theming. We adopt the host's identity; we
  never stamp ours on top.
- **Dependency-bloated kits** that drag in image pickers, url launchers, markdown
  engines, or a state-management framework just to render a message. Heavyweight
  capabilities are callbacks and slots, not bundled dependencies.
- **Rigid, monolithic chat screens** — a single take-it-or-leave-it UI that can't be
  decomposed. Every layer must be replaceable or droppable.
- **The generic "AI made this" chat template** — gradient message bubbles,
  glassmorphism, novelty animation. Craft must read as deliberate, not as a slop default.

## Design Principles

1. **The host's identity wins; our craft shows in everything else.** Color and type
   come from `Theme.of(context)`. Our point of view lives in rhythm, motion, state
   choreography, and composition — never in imposed branding. This is how a *brand*
   register and a *deferential* widget can be the same thing.
2. **Opinionated defaults, escapable at every level.** Ship one confident, correct
   look out of the box; let developers override any piece (`messageBuilder`,
   `textBuilder`, the callbacks) or drop to raw primitives. Drop-in to à-la-carte is a
   continuum, never a cliff.
3. **Dependency-light by principle.** Every heavyweight capability — attachments,
   link-opening, markdown, file handling — is a slot or callback, not a dependency.
   The cost of adopting the kit stays near zero.
4. **Production behavior is the headline feature.** Streaming correctness, the
   tool-loop with human-in-the-loop approvals, first-error-wins handling, graceful
   fallbacks, disciplined subscription cleanup — the polish that survives real network
   conditions is the product, not a demo veneer.
5. **Make the stream feel alive, not busy.** Liveness — optimistic bubbles, the
   blinking cursor, the typing wave, auto-scroll — should read as responsive and
   trustworthy. Restraint over novelty; motion is intentional, never decoration.

## Accessibility & Inclusion

Target **WCAG 2.2 AA** in the surfaces the library controls, while trusting the host
app's `ColorScheme` for color.

- **Contrast:** choose color *roles* that preserve contrast regardless of the host
  palette — `onPrimary` on `primary`, `onSurfaceVariant` on surface containers,
  `onErrorContainer` on `errorContainer`. Never hardcode a light-gray body color.
- **Reduced motion:** every animation (typing dots, streaming cursor, expand/collapse,
  auto-scroll) must honor the platform reduced-motion setting
  (`MediaQuery.disableAnimations`) with a crossfade or instant fallback.
- **Screen readers & semantics:** meaningful semantics for message roles, streaming
  status, and tool-approval actions; semantic labels/tooltips on every icon-only
  control (send, stop, attach, approve/deny, scroll-to-bottom).
- **Targets & input:** Material's standard touch-target sizing on interactive
  controls; selectable text on message content.

We trust the host theme for color; we guarantee the structural accessibility ourselves.
