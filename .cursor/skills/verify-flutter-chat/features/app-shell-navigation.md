# App shell navigation

The app opens on a shell with a bottom navigation bar of five tabs: Chat, Completion, Object, Local and Remote. Each tab shows its screen in place. The Local and Remote screens are also reachable as the named routes `/conversation` and `/remote`, which push on top of the shell.

## Sub-features

- `nav-tabs` makes each tab show its screen heading: `Chat`, `Completion`, `Object Stream`, `Local conversation`, `Remote conversation`.
- `nav-selected` marks only the active tab as `[selected]` in the tablist.
- `nav-routes` makes `#/conversation` and `#/remote` open the conversation screens with a `Back` button and no tab bar.

## How to get to it (user POV)

- Load the app root. It starts on `Chat`.
- Choose a tab in the bottom navigation.
- Open a deep link to `#/conversation` or `#/remote`.

## Driving it with vfc

Preconditions:

- `$S doctor` prints no `FAIL` line.

- **Canned proof.** Run `$S scenario shell-nav`. Output `PASS shell-nav`. It saves `shell-nav-<tab>.{aria.txt,png}` for each tab and checks the expected screen heading and that the current tab is selected.
- **Root.** Run `$S browser open /`. The printed tree has `heading "Chat"` and a `tablist` with `tab "Chat" [selected]` and four other tabs.
- **Switch tab.** Run `$S browser tab Object`, then `$S browser aria`. The tree shows `heading "Object Stream"` and `tab "Object" [selected]`.
- **Named route.** Run `$S browser open /remote`. The tree starts with `button "Back"` and `heading "Remote conversation"`, and has no `tablist`.
- **Back.** Run `$S browser click --name Back`. `$S browser aria` shows the shell with the `Chat` tab selected.

## Gotchas

- The shell swaps the tab body and does not keep it alive. If you leave a tab, its conversation and inputs are lost when you return. Finish a flow on one tab before you change tabs.
- The heading for the Object tab is `Object Stream`, not `Object`.
