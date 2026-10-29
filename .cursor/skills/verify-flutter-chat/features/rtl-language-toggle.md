# Arabic / RTL strings toggle

The Local and Remote screens have a language button in the app bar. It swaps the scaffold's `AiSdkUiStrings` between English and a demo Arabic set, and mirrors the layout right-to-left. The conversation continues with no data loss when the user switches language.

## Sub-features

- `rtl-strings` changes the composer hint to `رسالة…`, Send to `إرسال الرسالة`, and the approval buttons to `موافقة` / `رفض`.
- `rtl-mirror` moves the Send button to the left of the field and the title to the right.
- `rtl-approval` makes an approval decision work with the Arabic labels.
- `rtl-revert` makes the button (now `Switch to English`) restore English and keep the messages.

## How to get to it (user POV)

- On the `Local` or `Remote` tab, or on the `/conversation` or `/remote` route, choose the globe button in the app bar. Its accessible name is `التبديل إلى العربية` in English mode and `Switch to English` in Arabic mode.

## Driving it with vfc

Preconditions:

- `$S doctor` prints no `FAIL` line.
- For the Remote screen, the run's backend is up.

- **Canned proof.** Run `$S scenario rtl-toggle`. Output `PASS rtl-toggle`. This scenario uses the `/conversation` named route. `rtl-toggle.json` shows `english layout` with `sendX > fieldX`, `arabic layout` with `sendX < fieldX`, an Arabic approval with `assistantRows:1`, and `back to english` with `assistantRows:1`.
- **Toggle manually.** Run `$S browser open /conversation`, then `$S browser click --name "التبديل إلى العربية"`. `$S browser aria` shows `textbox "رسالة…"`, `button "إرسال الرسالة"` and `button "Switch to English"`.
- **Send in Arabic.** Run `$S browser send "Run the example" --lang ar`, then `$S browser click --name "موافقة"`, then `$S browser wait-text "Tool result: deleted /tmp/example"`. `$S browser state --lang ar` shows `assistantRows:1`.
- **Proof.** Run `$S browser snapshot --name rtl-arabic`. The PNG shows the title on the right, the back arrow on the right, and Send on the left of the field.
- **Revert.** Run `$S browser click --name "Switch to English"`. `$S browser state` shows `composerPresent:true` and `assistantRows:1`.

## Gotchas

- Use `--lang ar` with `send` and `state` in Arabic mode. Otherwise they look for the English labels and report the composer as missing.
- The tool card label (`Tool call: deleteFile`) and the tool result text stay in English. The demo string set does not translate them, so this is not a defect.
- Each screen has its own toggle state. Switching on Local does not change Remote.
- `open` resets the language to English.
