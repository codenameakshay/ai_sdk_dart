---
name: AI SDK Flutter UI
description: Flutter AI chat / completion / object-stream UI that adopts its host app's Material 3 theme.
colors:
  primary: "#6750A4"
  on-primary: "#FFFFFF"
  surface-container-high: "#ECE6F0"
  surface-container-highest: "#E6E0E9"
  on-surface: "#1D1B20"
  on-surface-variant: "#49454F"
  outline-variant: "#CAC4D0"
  tertiary: "#7D5260"
  error: "#B3261E"
  error-container: "#F9DEDC"
  on-error-container: "#410E0B"
typography:
  body:
    fontFamily: "inherited from host TextTheme (Material default: Roboto)"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  title:
    fontFamily: "inherited from host TextTheme"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.4
    fontFeature: "tnum (tabular figures on tool names)"
  label:
    fontFamily: "inherited from host TextTheme"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.3
  mono:
    fontFamily: "monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.4
rounded:
  tail: "4px"
  sm: "8px"
  md: "12px"
  bubble: "16px"
  field: "24px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
components:
  bubble-user:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.bubble}"
    padding: "10px 14px"
  assistant-turn:
    textColor: "{colors.on-surface}"
    typography: "{typography.body}"
  assistant-marker:
    backgroundColor: "{colors.surface-container-highest}"
    textColor: "{colors.primary}"
    size: "26px"
  bubble-tool:
    backgroundColor: "{colors.surface-container-highest}"
    textColor: "{colors.on-surface-variant}"
    rounded: "{rounded.bubble}"
    padding: "10px 14px"
  composer-field:
    backgroundColor: "{colors.surface-container-highest}"
    rounded: "{rounded.field}"
    padding: "12px 18px"
  composer-send:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    size: "40px"
  tool-card:
    textColor: "{colors.on-surface}"
    rounded: "{rounded.md}"
    padding: "12px"
  code-block:
    backgroundColor: "{colors.surface-container-highest}"
    textColor: "{colors.on-surface}"
    typography: "{typography.mono}"
    rounded: "{rounded.sm}"
    padding: "10px"
  error-banner:
    backgroundColor: "{colors.error-container}"
    textColor: "{colors.on-error-container}"
    rounded: "{rounded.md}"
    padding: "10px 12px"
  usage-pill:
    backgroundColor: "{colors.surface-container-highest}"
    rounded: "{rounded.sm}"
    padding: "4px 10px"
---

# Design System: AI SDK Flutter UI

## 1. Overview

**Creative North Star: "The Quiet Conductor"**

This is a Flutter UI library that conducts a genuinely rich performance — streaming text, reasoning, tool calls, human-in-the-loop approvals, source citations, token usage — and then steps out of the spotlight. It owns no palette and no typeface. Every color is a Material 3 `ColorScheme` role and every text style a `TextTheme` role, both resolved from the host app's `Theme.of(context)`. The library's craft lives not in chrome but in **structure, rhythm, restraint, and timing**: how a turn's parts are ordered, how a stream resolves into a settled message, how state changes flow instead of cut.

The transcript reads as a **natural conversation**, Claude-style: the user's message sits in a soft right-aligned bubble; the assistant answers **flush — no bubble** — as readable prose behind a small leading marker, so long answers and rich parts read as content, not chat chrome. The system is **calm and precise**: flat, tonally layered surfaces fenced by hairline `outlineVariant` borders, never drop shadows. The one accent on screen is the host's `primary`, spent sparingly on the user bubble, the send affordance, and interactive marks.

**Motion is a material here, not a finish.** It is Apple-grade by intent: continuity over popping (typing dots cross-fade into streaming text; send morphs into stop), gentle ease-out curves with no bounce, every control answering a press with a subtle scale and a light haptic, and a **first-class reduced-motion path** on every animation. All of it is built from core Flutter — no animation dependency — through one shared vocabulary (`AiMotion`, `AiHaptics`, `PressableScale`, `AiEntrance`, `StreamingCursor`).

It explicitly rejects the look of a **heavy branded chat SDK** that stamps its own identity over the host; the **dependency-bloated** aesthetic that drags in pickers, launchers, and markdown engines to render a message; and the **generic "AI made this" chat template** — gradient bubbles, glassmorphism, novelty animation.

**Key Characteristics:**
- Theme-deferential: zero owned colors or fonts; pure Material 3 role consumption.
- Natural transcript: user bubbles, flush assistant prose with a minimal marker.
- Flat and tonal: surface-container layering + hairline borders, no shadows (one functional FAB excepted).
- Motion as material: continuity, gentle ease-out, press + haptics, mandatory reduced-motion path — all core Flutter.
- Dependency-light: heavyweight capabilities are callbacks/slots, never bundled.

## 2. Colors

There is no palette. Every color is a Material 3 `ColorScheme` role resolved from the host app; the hex values below are **representative only** — sampled from the example apps' `ColorScheme.fromSeed(#6750A4)` — and shift to whatever the host theme provides.

### Primary
- **Host Accent** (`primary`, #6750A4): the single accent. Fills the user message bubble, the filled send button, the assistant marker glyph, and interactive marks (tool-result check, source-chip icon). Paired always with `on-primary` (#FFFFFF) for text/icons on top.

### Tertiary
- **Trust Mark** (`tertiary`, #7D5260): used once, for the shield icon on the tool-approval card — a deliberately distinct hue that flags "this needs your decision" without competing with the primary accent.

### Neutral
- **Assistant Surface** (`surfaceContainerHigh`, #ECE6F0): background of the reasoning panel and standalone assistant/system bubbles — one tonal step above the page.
- **Recessed Surface** (`surfaceContainerHighest`, #E6E0E9): the assistant marker, tool bubbles, composer field fill, code blocks, usage pills — the "input / quoted content / chrome" tone.
- **Primary Ink** (`onSurface`, #1D1B20): body text, including flush assistant prose.
- **Muted Ink** (`onSurfaceVariant`, #49454F): the workhorse — secondary text, labels, icons, captions, metadata.
- **Hairline** (`outlineVariant`, #CAC4D0): the only border in the system; 0.5–1px, used to bound cards and code tiles.

### Status
- **Error** (`error`, #B3261E): error icons and the error-result accent in tool cards.
- **Error Surface / Ink** (`errorContainer` #F9DEDC / `onErrorContainer` #410E0B): the inline error banner and error-result code blocks. Always used as a pair.

### Named Rules
**The Borrowed Color Rule.** The library defines no color. Every surface, text, and accent is a `ColorScheme` role from `Theme.of(context)`. A hardcoded color literal is a bug, not a style choice.

**The On-Pair Rule.** A role is never used without its `on-` counterpart (`primary`/`onPrimary`, `errorContainer`/`onErrorContainer`, `surfaceContainerHigh`/`onSurface`). This is what guarantees contrast survives any host palette — light, dark, or custom seed.

**The One Accent Rule.** Only `primary` carries accent weight, on ≤10% of any screen. Its rarity is what makes the send button and user bubble read as "the live edge" of the conversation.

## 3. Typography

**Display / Body Font:** inherited from the host `TextTheme` (Material default: Roboto). The library chooses no typeface.
**Mono Font:** generic `monospace` (the one explicit family, used only for serialized tool I/O).

**Character:** the type voice is the host app's. The library's only typographic act is to assign Material roles consistently and set comfortable reading line-height. Restraint, not expression.

### Hierarchy
- **Body** (`bodyMedium`, 400, 14px, line-height 1.5): message content. Flush assistant prose carries the turn, so it gets a comfortable reading measure; the user bubble caps at ~78% of viewport width.
- **Title** (`titleSmall`, 500, 14px): tool names and card titles — set on **tabular figures** so identifiers and ids stay aligned.
- **Label** (`labelMedium`, 500, 12px): section labels ("Sources", "Reasoning"), usage values, result/error tags.
- **Label Small** (`labelSmall`, 500, 11px): the smallest metadata — attachment media types, usage labels.
- **Mono** (`monospace`, 400, 12px, line-height 1.4): pretty-printed JSON tool input and tool output only.

### Named Rules
**The Inherited Voice Rule.** Type comes from the host. The library assigns roles and reading line-height; it never sets a font family (except `monospace` for serialized data) and never hardcodes a font size outside the Material scale.

**The Tabular Numerics Rule.** Tool names and token counts always use tabular figures. Conversational prose never does.

## 4. Elevation

The system is **flat by default**. Depth is conveyed entirely through Material 3 **tonal layering** — the page sits below `surfaceContainerHigh` (reasoning, standalone assistant bubbles) which sits below `surfaceContainerHighest` (marker, tool bubbles, fields, code) — and bounded by **hairline `outlineVariant` borders** (0.5–1px) on cards and code tiles. Cards render at `elevation: 0`. There is no drop-shadow vocabulary.

### Shadow Vocabulary
- **None, by doctrine.** Cards, bubbles, banners, chips, and the composer are all shadowless.
- **Scroll-to-bottom FAB** (Material `FloatingActionButton.small` default elevation): the single exception, and only because it genuinely floats above scrolling content. Its elevation is functional, not decorative; it scales and fades in on appear.

### Named Rules
**The Tonal-Not-Shadow Rule.** Depth is layered tonally and fenced with hairlines — never with shadow. If a surface needs to feel "raised," step its tonal role up; do not add a `box-shadow`. The only elevated element in the entire library is the scroll-to-bottom FAB.

## 5. Components

The feel across every component is **calm and precise**: restrained surfaces, hairline structure, type and tonal role doing the work — and motion that conveys state without drawing attention to itself.

### Buttons
- **Shape:** circular for icon actions (`IconButton.filled`), standard pill for text actions (`FilledButton` / `TextButton`).
- **Send / Stop:** a single `primary` filled control that **morphs** between send (arrow-up) and stop (square) via a cross-fade + scale `AnimatedSwitcher` — it reads as one object changing state. Disabled when the field is empty or the surface is non-interactive. A light haptic fires on send and on stop.
- **Approve / Deny:** `FilledButton` (primary) for Approve right of a `TextButton` tinted `error` for Deny — affirmative action leads, destructive recedes. Both press-scale and fire a selection haptic.
- **Press feedback:** every button is wrapped so it scales to ~0.96 on pointer-down and springs back on release (suppressed under reduced motion).

### Conversation turns (signature)
- **User bubble:** 16px corners (`{rounded.bubble}`) with a single 4px tail (`{rounded.tail}`) toward bottom-right; `primary` / `onPrimary`; selectable text; capped at ~78% width.
- **Assistant turn (flush):** **no bubble.** A 26px circular marker (`surfaceContainerHighest` with a `primary` glyph) leads full-width prose in `onSurface` at line-height 1.5. Rich parts — reasoning, tool cards, sources — stack in this flush column. New turns ease in once (fade + 6px lift), tracked by identity so scrolling never replays the entrance.
- **Streaming:** before the first token a typing indicator breathes (staggered fade + rise); it **cross-fades** into the streaming text, which carries an inline `StreamingCursor` — a caret on a soft ~900ms cosine pulse, not a hard blink.
- **Tool bubble:** left-aligned `surfaceContainerHighest` / `onSurfaceVariant` (standalone `ChatMessageBubble` only).

### Chips
- **Source citations & prompt suggestions:** Material `ActionChip`, compact density, press-scaled, selection haptic on tap. Source chips carry a `link` icon in `primary`. Prompt suggestions ease in on a short capped **stagger** (≤6 steps).

### Cards / Containers
- **Tool call & approval cards:** Material `Card` at `elevation: 0`, 12px corners (`{rounded.md}`), bounded by an `outlineVariant` hairline, 12px padding. Serialized I/O renders in an 8px `surfaceContainerHighest` code tile. A tool result's status icon scale-springs in (no bounce).
- **Reasoning panel:** a 12px `surfaceContainerHigh` container with a tappable header (chevron rotates) and an `AnimatedSize` disclosure that eases open; selection haptic on toggle.
- **No nesting:** a card never contains another card; the code tile inside a tool card is a tonal block, not a bordered card.

### Inputs / Fields
- **Composer field:** filled `surfaceContainerHighest`, **24px pill** (`{rounded.field}`), borderless, 12×18px padding, 1–5 auto-growing lines. The pill radius is intentional for an input; it is the one place full-pill rounding is correct.
- **Reason field (approval):** standard dense `OutlineInputBorder` text field, shown only when reasons are collected.

### Media
- **Image:** core `Image` widget (bytes/base64 → `MemoryImage`, URL → `NetworkImage`); fades in on decode; falls back to a broken-image tile rather than throwing.
- **File attachment:** a tonal tile (type icon + filename + media-type subtitle); press-scaled, opens via a host callback.

## 6. Do's and Don'ts

### Do:
- **Do** resolve every color from `Theme.of(context).colorScheme` and every text style from `textTheme` — nothing hardcoded.
- **Do** pair each role with its `on-` counterpart so contrast holds on any host theme (the On-Pair Rule).
- **Do** render the assistant flush (no bubble); reserve bubbles for the user (and standalone tool messages).
- **Do** convey depth tonally and fence it with `outlineVariant` hairlines; keep cards at `elevation: 0`.
- **Do** cap card corners at 12px; reserve full-pill rounding for the composer input and chips/tags only.
- **Do** set tabular figures on tool names and token counts.
- **Do** treat motion as a material: continuity (cross-fade / morph, not hard swap), ease-out only, press + light haptic on controls.
- **Do** give every animation a reduced-motion fallback (`MediaQuery.disableAnimations` → instant/crossfade, haptics suppressed) and build it from core Flutter.
- **Do** expose attachments, link-opening, and markdown as callbacks/slots — never as bundled dependencies.

### Don't:
- **Don't** hardcode a color or font — the library must never "stamp its own identity over the host."
- **Don't** put the assistant in a bubble in the default transcript — flush prose is the voice.
- **Don't** build toward a **heavy branded chat SDK** look (Intercom/Drift-style, "powered-by" bubbles) that resists theming.
- **Don't** add dependencies for image pickers, url launchers, markdown engines, or animation — that is the **dependency-bloated** anti-reference.
- **Don't** ship the **generic "AI made this" chat template**: gradient message bubbles, glassmorphism, or novelty animation.
- **Don't** use bounce or elastic easing, or a hard on/off blink — motion is gentle ease-out, the cursor breathes.
- **Don't** use drop shadows for depth (the Tonal-Not-Shadow Rule) — the only elevated element is the scroll-to-bottom FAB.
- **Don't** nest a card inside a card, or use a `border-left`/side-stripe accent — full hairline borders or tonal fills only.
- **Don't** over-round: a 24px+ radius on a card or tool tile is forbidden (the composer pill input is the sole intentional exception).
