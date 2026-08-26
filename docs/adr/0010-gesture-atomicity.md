# A gesture is atomic: competing input ends it before it applies

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`,
root cause 1, gaps G-01…G-12; vocabulary — Gesture — in `CONTEXT.md`). Closes the worst findings
in the sweep, including the one where half a Pencil stroke becomes permanently un-undoable.

Before this decision the Editor had exactly one guard that asked "is a gesture in flight?" — the
hold-Alt eyedropper spring in `keyboard/dispatcher.dart`. Every other input route (keyboard tap
Commands, row-3 tiles, film-roll and layer-strip taps, row-1 controls, second-finger touches)
dispatched freely into an open gesture, and the engine executed whatever arrived. The rule is now
one sentence: **a gesture is atomic — nothing else reaches the engine until it ends, and competing
input ends it first.**

Three commitments follow:

- **Finish, don't refuse and don't discard.** A competing command first ends the gesture as if the
  artist lifted, then applies. The stroke commits, the command runs, and the next stroke uses the
  new tool or frame. Neither the artist's paint nor the artist's keystroke is thrown away, which
  matters because left-hand-on-keyboard-while-right-hand-draws is the normal desktop workflow.
- **The in-flight predicate covers five gesture families, not two.** Canvas drag and pinch (today's
  `pointerActive`) plus control drags, trackpad pan/zoom gestures, and precision pen-down. A gate
  that knows about two of five families does not remove drift, it relocates it — G-08 (a slider
  drag writing into the next tool's memory), G-10 (a trackpad transform dumped in one jump at
  stroke end) and G-43's pen half all live outside the old predicate.
- **Esc, Undo and Redo cancel the gesture and consume the keystroke.** They are the one carve-out
  from finish-then-do. Mid-stroke, the thing the artist means by Ctrl+Z is *this stroke*; finishing
  first would churn a history record for a no-op and, with the wrong timing, undo the previous
  action instead — G-05's resurrection bug in a new costume.

Cancel means different things per family, and the split is deliberate: **value gestures revert,
view gestures only end.** A control drag finishes by committing its current value and cancels by
restoring its pre-drag value; a pinch or trackpad gesture has no cancel at all, because the view is
not undoable state and reverting a navigation the artist deliberately performed would be hostile.

Alternatives rejected:

- **Refuse competing input while a gesture is live** (the gesture is sovereign, chords are
  swallowed): zero corruption and the simplest predicate, but a keystroke that silently vanishes
  reads as the app ignoring the artist, constantly, in the workflow where this state is hit most.
- **Cancel-then-do** (discard the partial stroke, then apply): safest for history, but it throws
  away paint the artist already laid down for the crime of pressing a key.
- **Per-class rules** (view Commands allowed, everything else refused): more precise on paper, but
  it is a table to maintain, and zoom *does* change a stroke's meaning by shifting the
  screen-to-canvas mapping (G-06) — so the genuinely safe class is nearly empty.

Consequences: the gate lives at the `_act` funnel (`editor_page.engine.dart:471`) and the input
routes, not at ~40 call sites, which is the whole point of making it a policy; every new input
surface inherits it for free and must not invent its own guard. Nothing about this is announced to
the artist — a force-finished stroke is visibly on the canvas (see ADR 0011 for the silence rule).
