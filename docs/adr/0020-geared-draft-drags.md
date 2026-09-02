# Geared draft drags are an input-space transform, never a verb

**Decided 2026-09-02.** Shell only: `app/lib/editor/drag_gear.dart` (`kDraftGearRatio`,
`kDraftGearCapPx`, `draftGearDivisor`, `TotalDragTracker`), the `_beginTotalDrag` /
`_totalDragDelta` pair in `editor_page.canvas.dart`, the shared `_slowChip` on the Move and
CopyPaste row-1 in `editor_page.controls.dart`, the `_slowDrafts` flag. Pinned by
`app/test/drag_gear_test.dart`. No engine change.

Users reported that positioning a Move draft to an exact pixel is cumbersome: at fit zoom on a
big canvas one canvas pixel is a few screen pixels, so a fingertip overshoots. The nudge arrows
already give 1-px steps, and zooming in is the intended precision path, but neither is what a
finger mid-drag wants.

**A "Slow" toggle at the end of row-1 gears the drag down.** With Slow ON, the Move draft, the
Move-selection mask drag and the Paste draft drag move less than the finger travels: 4 screen
px of finger per draft pixel's worth of canvas (`kDraftGearRatio`, deliberately below the 6× of
the row-1 sliders because a canvas drag covers far more distance). One flag serves both tools.
Default OFF, session-only (like Protect/Wrap — it is not persisted), and it takes effect on the
next drag: the divisor is captured at drag begin, and a second finger ends the drag, so the view
scale can never change under a geared drag.

**The gearing is capped by zoom.** A fixed 4× is right only for the coarse view; at 32 screen
px per canvas px it would cost 128 px of travel per pixel and read as broken. So the effective
finger cost of one canvas pixel is `min(4 × scale, max(scale, 32))`: full 4× below 8 px/px, a
flat 32 screen px per pixel between 8 and 32 px/px, and plain 1:1 past the cap. Gearing fades
out exactly where zoom has already made the pixel a fingertip wide.

**Why an input-space transform and not a verb.** These three drags are incremental: the engine
takes integer deltas (`MoveDraftMove`, `MoveSelection`, `PasteMove`) and never sees a pointer
position. The shell already tracks each drag's origin and the integer total it has sent, and
sends corrective deltas toward the intended total (that is how a held Shift axis-locks a drag
without off-axis drift). Gearing divides that total before rounding, so the fractional
remainder carries across events (four 1-px finger moves at 4× are exactly one draft pixel),
Shift composes for free (scaling is linear), and the Journal records the same deltas whether
Slow was on or off. Replays are faithful by construction. Making Slow a DSL verb would buy
nothing and add a retired-verb obligation forever (journals replay) — the same doctrine that
keeps Shift-constrain and the Ruler out of the engine, and the FZ-4 rule of recording content,
never input-space proxies.

**The two coordinate paths must not be mixed.** The 1:1 drag keeps its historical floored
canvas coordinates (a move starts when the finger crosses a whole-pixel boundary; hash pins and
feel unchanged). A geared drag reads sub-pixel positions for both its origin and every step: a
floored origin under a raw position would bias the geared total by up to a pixel. A divisor of
exactly 1 (Slow ON but zoomed past the cap) takes the floored path, so it is indistinguishable
from Slow OFF.

**Consequences.** Long moves at fit zoom take several swipes; the draft survives a lift, so the
user re-drags from wherever they land, or turns Slow off, or finishes with the nudge arrows. A
forgotten-ON Slow makes the next drag feel sluggish; the green `Slow ✔` chip and the session
reset bound that. On desktop the mouse cursor visibly separates from the draft, as it already
does on the geared row-1 sliders. No offset readout was added (declined).
