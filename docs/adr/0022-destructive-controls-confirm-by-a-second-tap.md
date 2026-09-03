# Destructive frame and layer controls confirm by a second tap, not a dialog

**Decided 2026-09-03.** Shell only: `app/lib/editor/tap_again.dart` (`TapAgainArm`,
`TapAgainDeleteButton`, `kTapAgainWindow`), `_sheetDelete` in `editor_page.sheets.dart` (the frame
and layer sheets), `deleteFrame` in `editor_page.keyboard.dart` plus `_frameDeleteArm` on the page
state and the disarm in `_send`. Pinned by `app/test/tap_again_test.dart`. No engine, journal, or
`.mkpx` change — `RemoveFrame` / `RemoveLayer` are sent exactly as before, once.

Deleting a frame or a layer is undoable, but an accidental tap on the sheet's bottom button still
costs a surprise and an Undo, and on a phone the button sits where a thumb lands. The palette page
reconfirms its destructive operations with a dialog because palette state is outside undo; a
dialog here would tax every intentional delete with an extra tap and a focus change.

**The button itself is the confirmation.** The first tap arms it: it relabels to "Tap again to
confirm" and fills red with white text, so the state change is unmistakable. A second tap within
3 s (`kTapAgainWindow`) performs the delete; the sheet stays open as before, so delete-delete-delete
chains still work at two taps each. Silence disarms: the window expires and the button reverts
with no toast or dialog.

**A confirm can only land on what was armed.** The button is keyed by `(target index, _sendSeq)`.
Retargeting in the sheet's strip changes the index; every other sheet action sends engine traffic,
which bumps `_sendSeq` before the sheet rebuilds; closing the sheet unmounts the button. Any of
those disarms it. The one gap is deliberate: engine traffic that reaches the sheet without a
rebuild leaves the button armed until its window runs out.

**The keyboard command follows the same rule.** `frame.delete` arms on the first press (a 3 s toast
names the frame), deletes on the second press for the same frame. Any edit sent to the engine
disarms it (`_send`, `activity: true`); playback ticks do not, so arming during playback still
works. Frames only — there is no layer-delete command to mirror.

Consequences: destructive sheet buttons are a two-tap gesture everywhere the helper is used, and a
future destructive sheet action should use `TapAgainDeleteButton` rather than a dialog; the
palette page's dialogs stay, because their operations cannot be undone.
