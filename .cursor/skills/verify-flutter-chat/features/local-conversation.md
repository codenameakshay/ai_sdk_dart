# Local conversation

The Local screen runs a full conversation with no network and no key. Any message makes the scripted model call the `deleteFile` tool for `/tmp/example`. An approval card asks the user to approve or deny. The composer stays locked until the user decides, and the assistant then answers with the actual tool result or with the denial.

## Sub-features

- `local-send` shows the user message and a `deleteFile` tool call card.
- `local-pending` shows the approval card and the status text, and disables the composer and Send while the approval is pending.
- `local-approve` runs the tool once and answers `Tool result: deleted /tmp/example`.
- `local-deny` runs the tool zero times and answers `Tool denied; no local action ran.`
- `local-settle` removes the card, shows one assistant message, and makes the composer editable again.

## How to get to it (user POV)

- Choose the `Local` tab in the bottom navigation.
- Open the `/conversation` named route (`#/conversation` on web). It shows a `Back` button and no tab bar.

## Driving it with vfc

Preconditions:

- `$S doctor` prints no `FAIL` line for this run.
- Nothing else is necessary. This feature uses no backend and no key.

- **Canned proof, approve.** Run `$S scenario local-approve`. It uses the `/conversation` named route at 1280×900 and approves with the keyboard (focus + Enter). Output `PASS local-approve`. `local-approve.json` shows `approval pending` with `composerEditable:false, sendEnabled:false` and `final` with `assistantRows:1`; `local-approve-pending.{aria.txt,png}` captures the pending state.
- **Canned proof, deny.** Run `$S scenario local-deny`. It uses the `/conversation` named route at 390×844 and clicks Deny. Output `PASS local-deny`. `local-deny-final.aria.txt` contains `Tool denied; no local action ran.`
- **Tab entry.** Run `$S browser open /`, then `$S browser tab Local`. `$S browser aria` shows heading `Local conversation` and the selected tab `Local`.
- **Send.** Run `$S browser send "Run the example"`. `$S browser aria` shows `group "Tool call: deleteFile"` and `group "Tool approval required for deleteFile"` with the buttons `Deny` and `Approve`.
- **Pending lock.** Run `$S browser state`. The result has `"composerEditable": false`, `"sendEnabled": false`, `"approvalPending": true`.
- **Approve by mouse.** Run `$S browser click --name Approve`, then `$S browser wait-text "Tool result: deleted /tmp/example"`. `$S browser state` shows `approvalPending:false`, `assistantRows:1`, `composerEditable:true`.
- **Proof.** Run `$S browser snapshot --name local-tab-approve`. The PNG shows the user bubble, the tool card and the result line, with no approval card. This is tab-entry evidence, distinct from canned named-route evidence.

## Gotchas

- The tool does not delete anything. Do not look for filesystem changes. The exact result text is the proof, because the scripted model throws if the tool ran a number of times other than one (approve) or zero (deny).
- A second message in the same session starts a new tool call. Use `open` to start from a clean state.
- Local retry (after a failed turn) is covered by the iOS integration suite. The app has no UI path that makes a local turn fail.
- The approval card has no reason field in this app. Do not look for one.
- `Send message` shows a tooltip after a click. It is visible in screenshots and is not a defect.
