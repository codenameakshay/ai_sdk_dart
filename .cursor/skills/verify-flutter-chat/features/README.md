# flutter_chat verification map

This directory is the maintained source for verifying the user-facing behavior of `examples/flutter_chat`, the app that exercises the `ai_sdk_flutter_ui` prebuilt widgets. Read this index before you drive the app, then use the matching feature file as the recipe.

## Baseline preconditions

- Use one run id from `vfc new` and put `VERIFY_RUN_ID=<id>` on every call. `S=.cursor/skills/verify-flutter-chat/scripts/vfc`.
- `$S build` and `$S up` were run for this id, and `$S doctor` prints no `FAIL` line. A `build is stale` failure means a fingerprinted app source, workspace config, or resolved package config changed after the build. Run `$S build` again, then `$S browser open <route>` to reload the running app. Do not rerun `$S up` while this run's processes are already live.
- The reference backend for this run is up (`doctor` shows the backend owns its port), unless a recipe says to stop it.
- Never drive an instance that another run id started.

## Driving conventions

- Start each recipe with `$S browser open <route>` or a `$S scenario`. Both load a fresh app instance with no conversation history.
- Use ARIA roles and accessible names from the Flutter semantics tree. Never use coordinates or CSS.
- Treat every command as literal. Keep quoted text, names and flags unchanged, including the `…` character in `Message…`.
- `$S browser type` and `$S browser send` select all existing text in the target field, then type the new text key by key. They replace the field value; they do not append at the caret.
- Wait for text with `--expect` or `$S browser wait-text`. Do not use a fixed sleep.

## Proof and skip reporting

- Capture the user action and the resulting state: the pending snapshot and the final snapshot, not only the last screen.
- UI proof is an `.aria.txt` snapshot and a `.png` that shows the screen title.
- Remote proof includes the `POST /chat` request and response from the scenario JSON or `events.jsonl`.
- After a completed turn, the conversation shows exactly one assistant message.
- Record the feature file, sub-feature ID and entry point (tab or named route) with every artifact. A named route is not proof of the corresponding shell tab, or vice versa.
- If a path is unreachable (for example, no OpenAI key was baked in), report the command you tried and the precondition that was not met.
- Do not report an entry point as verified through a different path. A tab and its named route are separate entry points.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph that describes the behavior that the user sees. Then it has exactly four H2 sections in this order:

1. `Sub-features`: one line per short ID.
2. `How to get to it (user POV)`: every user entry point.
3. `Driving it with vfc`: starts with `Preconditions:`, then labeled bullets. Each bullet pairs a user action with an exact command and the result to observe.
4. `Gotchas`: traps that can waste or invalidate a verification run.

## Features

- [Local conversation](./local-conversation.md): the keyless tool-approval loop (approve, deny, composer lock) on the Local tab and the `/conversation` route (the canned scenarios use the named route).
- [Remote conversation](./remote-conversation.md): text and tool approval through the pinned JS backend, plus the unreachable-backend banner (the canned scenarios use the named route).
- [Arabic / RTL strings toggle](./rtl-language-toggle.md): the app bar language button that swaps the scaffold strings and mirrors the layout.
- [App shell navigation](./app-shell-navigation.md): the five bottom tabs and the two named routes.
- [Live provider screens](./live-provider-screens.md): Chat, Completion and Object, which call OpenAI and need a key baked in at build time.
