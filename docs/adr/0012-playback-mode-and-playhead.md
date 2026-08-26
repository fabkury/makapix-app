# Playback is a mode; the Playhead is a pure preview that leaves the editing position alone

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`,
root cause 3, gaps G-20…G-29; vocabulary — Playhead — in `CONTEXT.md`).

The engine has always separated the two: `Session::current_play_frame()` advances with the clock
while `doc.active_frame` — the frame strokes actually land on — stays put. Nothing in the shell's
vocabulary named that separation, and the consequences accumulated. Canvas inertness was keyed to
the Play *tool* being selected rather than to playback *running*, so keyboard-started playback left
the whole editing surface live: the artist painted invisibly onto the active frame while the
animation played over it (G-21), Ctrl+V built an invisible paste Draft and silently reassigned
Enter and Esc (G-22), and Undo emptying the timeline parked the clock for up to an hour (G-20).
Auto-pause, meanwhile, was a per-call-site convention, so equivalent routes to one action disagreed
— found independently by three of the seven finder agents (G-24, G-25, G-26).

Two commitments:

- **Playback is a mode, enforced at the `_act` funnel.** Any editing intent pauses playback before
  it runs, and inertness keys on `_playing`, not on which tool is selected. One predicate at one
  chokepoint replaces roughly fifteen per-call-site pauses, and the next structural verb inherits
  the rule instead of forgetting it.
- **The Playhead is a pure preview.** Playback begins at the active target and pause **returns to
  it** — the artist's editing position is never moved by playback itself. The visible cost is
  accepted: pausing snaps the view back from whatever frame was on screen to the frame being
  edited.

A film-roll tap during playback still pauses **and** activates the tapped frame (G-27). That is not
an exception to the rule above: a tap on a tile is explicit activation under ADR 0013, and explicit
activation is the only thing that may move the active target.

Alternatives rejected:

- **Pause adopts the Playhead** (the frame you were watching becomes the frame you edit): removes
  the snap-back and matches "I saw a problem, pause, fix it" — but it lets playback quietly relocate
  the artist's editing position, which is exactly the class of invisible state change this survey
  exists to remove.
- **Playback as a live preview** (edits apply to the active target while it runs): more powerful,
  far more UI work, and it keeps "painting where you cannot see it" possible *by design*.
- **Status quo, audited** (keep per-call-site pausing, fix each disagreeing site): fifteen point
  fixes, and the next new call site restarts the drift.

Consequences: G-23 (the overscan gutter offset displacing the animating canvas) is *not* closed by
this policy — it is a rendering bug wearing a playback costume — and is tracked as a point fix.
Auto-pause is silent; a paused playback is visibly paused (ADR 0011's silence rule).
