# Flutter example apps verification map

This directory is the maintained source for verifying the user-facing behavior of `examples/flutter_chat` and `examples/advanced_app`, the apps that exercise the `ai_sdk_flutter_ui` prebuilt widgets. Read this index before you drive an app, then use the matching feature file as the recipe. Each feature file names its app.

## Baseline preconditions

- Use one run id from `vfc new` and put `VERIFY_RUN_ID=<id>` on every call. `S=.cursor/skills/verify-flutter-chat/scripts/vfc`.
- A run is built for one app. flutter_chat is the default. For advanced_app, put `VFC_APP=advanced_app` on the `$S build` call. The choice is recorded in the run state, and `$S doctor` prints `OK   app: <app>`. A scenario for the other app stops with an error. Use a new run id to check the other app.
- `$S build` and `$S up` were run for this id, and `$S doctor` prints no `FAIL` line. A `build is stale` failure means a fingerprinted app source, workspace config, or resolved package config changed after the build. Run `$S build` again, then `$S browser open <route>` to reload the running app. Do not rerun `$S up` while this run's processes are already live.
- For flutter_chat, the reference backend for this run is up (`doctor` shows the backend owns its port), unless a recipe says to stop it. advanced_app has no backend.
- Never drive an instance that another run id started.

## Driving conventions

- Start each recipe with `$S browser open <route>` or a `$S scenario`. Both load a fresh app instance with no conversation history. flutter_chat routes are hash routes (`/remote`). advanced_app pages are query pages: `$S browser open widget-gallery` loads `/?page=widget-gallery`.
- Flutter builds only the rows near the viewport. On a long page, run `$S browser scroll --to <name> --substring` before you read or click a lower element.
- Short-lived UI such as a snack bar is only visible for about one second. Prove it inside a scenario (tight poll), not with a separate `aria` call.
- Use ARIA roles and accessible names from the Flutter semantics tree. Never use coordinates or CSS.
- Treat every command as literal. Keep quoted text, names and flags unchanged, including the `…` character in `Message…`.
- `$S browser type` and `$S browser send` select all existing text in the target field, then type the new text key by key. They replace the field value; they do not append at the caret.
- Wait for text with `--expect` or `$S browser wait-text`. Do not use a fixed sleep.

## Proof and skip reporting

- Capture the user action and the resulting state: the pending snapshot and the final snapshot, not only the last screen.
- UI proof is an `.aria.txt` snapshot and a `.png` that shows the screen title.
- Remote proof includes the `POST /chat` request and response from the scenario JSON or `events.jsonl`.
- After a completed turn, the conversation shows exactly one assistant message.
- Record the feature file, sub-feature ID and entry point (tab, named route, drawer item or `?page=` URL) with every artifact. A named route is not proof of the corresponding shell tab, or vice versa. An advanced_app drawer choice and its `?page=` URL are also separate entry points.
- If a path is unreachable (for example, no OpenAI, Anthropic or Google key was baked in), report the command you tried and the precondition that was not met.
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
- [Widget Gallery (advanced_app)](./widget-gallery.md): 12 prebuilt `ai_sdk_flutter_ui` widgets with sample data and no key (`widget-gallery`, `widget-gallery-dark`).
- [Advanced app pages (advanced_app)](./advanced-app-pages.md): the drawer, the Tools Chat fixtures, the Conversation controls and RTL, the missing-key guards, and the exact steps for the key-backed provider pages.
