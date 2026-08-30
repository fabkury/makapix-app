# The Redo tile repeats the last repeatable op when there is nothing to redo

**Decided 2026-08-30**, reviving the 2026-08-08 analysis with its locked decisions intact
(overloaded Redo tile, engine `Repeat()` verb, snapshot-at-commit). Engine:
`RepeatOp` + `Session::repeat` in `crates/engine/src/session.rs`; shell: the Repeat face in
`app/lib/editor/editor_page.toolgrid.dart`.

At the head of history — redo stack empty — the pinned Redo tile changes face (icon →
repeat glyph, label → "Repeat", the Office Ctrl+Y precedent) and re-executes the **last
repeatable committed operation** against the **live target**: the active frame, layer, and
selection at Repeat time. Apply Levels to one frame, step to the next, tap Repeat — the same
curve lands there. The keyboard Redo command rides the same dispatch, so Ctrl+Y repeats too.

**The repeatable set** (closed — extending it is a new decision, not a drive-by):

- Adjustment bakes: Levels, HSV, Brightness/Contrast — with their Layer/Frame scope.
- Layer-scoped geometry: Flip H/V, Rotate (quarter-turns and the Angle-draft commit, which share
  one commit path), Scale/Resize (ditto). Canvas-scoped ops (`Rotate`, `FlipCanvas*`,
  `ResizeCanvas`) and frame-scoped flips are **excluded**.
- Paste-stamp: `PasteCommit` — re-stamp at the same position on the new target.

Strokes remain out (they would need input replay), as decided 2026-08-08.

**Parameters snapshot at commit; pixels too.** The record stores the committed parameters —
adjustment values and scope, flip axis, rotation angle + drag offset + cleanEdge state, scale
factors — so later slider or settings drift can never change what Repeat does. Paste goes one
further and snapshots the **stamped pixels themselves** (user decision): re-copying between the
commit and a later Repeat does not change the stamp. Recording rides the existing commit funnels,
so the instant buttons and the draft commits arm the same record.

**Targeting is live.** Repeat applies the op the way the underlying verbs already work: the active
layer (selection-clipped when a selection exists), or every layer of the active frame for
frame-scoped records. No target identity is stored — "repeat on the next frame/layer" is the
feature, and a stale marquee clipping a repeat is the same behavior every verb has.

**Lifetime** (user decision): the record survives Undo/Redo stepping — undo an experiment here,
Repeat there — and dies with the document (`NewDocument`'s whole-session reset, `adopt_loaded_doc`
on load). Replay checkpoints carry it, so a journaled `Repeat()` replayed after a scrub seek sees
the record it saw live.

**Tile precedence** (shell): discard move draft > Redo > Repeat — the existing `_doToolAction`
order with one new arm; the face switches only when a tap would actually repeat. `can_repeat` /
`repeat_label` ride the state probe.

**Replay:** `Repeat()` is a new verb — old journals never contain it, and its outcome is a pure
function of the journaled history before it, so no `#mkpxj` epoch bump (ADR 0015 forks are for
changed semantics of existing verbs; an older app replaying a newer journal drops the unknown line,
the accepted precedent for every added verb).

Alternatives rejected in 2026-08-08 and reaffirmed: a dedicated Repeat tile (row-3 space is
precious; the empty-redo state is exactly when the tile is dead weight); re-running against live
settings (drift changes the result); deriving the repeat from the redo stack (history stores
absolute snapshots, not operations). An "All frames" adjustment scope was declined as a substitute
— Repeat is the general mechanism.
