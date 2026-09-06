# Replay pacing follows clamped working time, with floors and ceilings on event ticks

**Decided and implemented 2026-09-06.** Design and alternatives: `docs/replay/PACING.md`;
vocabulary (Tick, Working time) in `CONTEXT.md`; code in `app/lib/editor/replay/visible_index.dart`
(the timeline) and `timelapse_plan.dart` (the pacing), shared by the Replay viewer and the Timelapse
export.

The Replay viewer and the Timelapse export stepped through the visible-change index with equal
time per visible tick. That already hid draft fiddling and settings churn, but it made a Pencil
stroke cost one tick per cell crossed while a Levels apply, a bucket fill, a shape or paste commit
cost exactly one tick, one 33 ms frame: single-line impactful changes flashed by and stroke-heavy
passages owned the whole preset. Pure wall clock is no better, because the recorded gaps between
lines include minutes of thinking and days between sessions.

The decision: **the axis is working time, clamped.** Every visible position is a tick, classed as a
STREAM tick (one step of a gesture: a stamp-tool contact, a held-pen move, a cursor plot or spray) or
an EVENT tick (everything else visible). A tick's working time is the sum of the recorded `+ms`
deltas of every journal line since the previous tick, each gap clamped at 2 s, so invisible lines
flow into the next tick (the seconds spent dragging the Levels slider land on the Apply; handle
dragging lands on the shape's commit) and a pause counts as one short beat. The preset (15/30/60 s)
is water-filled: stream ticks dwell in proportion to working time; event ticks are clamped into a
floor, `max(6 frames, T/100)`, and a ceiling, `T/12`, with the floor shrinking once floors alone would
claim more than 60 % of the preset. A run of one event verb repeating within 300 ms (held-arrow
nudges, a film-roll scrub, an undo storm) is demoted to stream steps after its first event, so it
flows at the speed it was performed instead of claiming a floor per repeat. A journal with no timing
paces uniformly, exactly as before. The viewer's sweep and slider move in the same video time, so
scrubbing previews the exported Timelapse frame for frame, and the duration chips re-pace in place
while keeping the tick on screen.

Everything is shell-side Dart over the journal text. Nothing in the Journal format, the recorder,
the epoch, the engine, or the FFI changed, so every journal ever recorded gets the new pacing; a
re-export of an already-published Timelapse times its frames differently but renders the same
pixels, which is a presentation change, not the pixel fork ADR 0015 guards.

Alternatives rejected:

- **Static per-verb weights** (the seed idea): cheap, but blind to magnitude and to tuning effort, and
  a second per-verb table beside the visibility triage with no oracle to validate it.
- **Measured pixel impact from the engine** (the undo system's changed-tile patches through one FFI
  getter): the most principled magnitude signal, deferred by the shell-only decision and noted as the
  natural second step if a class of ops proves mis-paced.
- **Composite-hash deltas per action**: O(pixels) per action, billions of pixel visits on a long
  journal.
- **Strokes per cell, events by working time**: two rules instead of one, and it recreates the
  scribble problem.
- **Dwell only** (repeat the frame after each event on the uniform index): a 40-line fallback that
  fixes the flash-by half and nothing else.

Consequences: the four constants (gap clamp, floor, ceiling, floor share) plus the burst window are
literal pins in tests and are expected to be tuned after watching real drawings on a phone; tuning
is a constant change, not a redesign. The viewer's slider now denotes video time, not tick index,
so a dense stretch of quick strokes occupies less of the bar than it used to.
