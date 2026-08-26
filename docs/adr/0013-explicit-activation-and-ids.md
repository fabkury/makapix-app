# The active target moves only by explicit activation, and the shell addresses frames and layers by id

**Decided 2026-08-25 during the UI specification-gap grilling** (survey: `docs/ui-gaps/REPORT.md`,
root cause 4, gaps G-30…G-36; vocabulary — Active target, Move group — in `CONTEXT.md`).

Two shipped features pulled in opposite directions. The stay-open sheets and the layer sheet's live
mini-stack let the artist operate on a frame or layer that is *not* active — the mini-stack's
contract is explicitly "tap to retarget, no `SetActiveLayer`". But the engine's structural verbs are
index-based and unconditionally activate their result. So arranging or duplicating from a
retargeted sheet silently stole the drawing target (G-34); reorder and delete left the move-group
pointing into a different frame's layer stack (G-31, G-32); deleting an item *below* the active one
shifted which frame or layer was active (G-35); "Edit duration…" switched the active frame even when
the dialog was cancelled (G-36); and a one-member move-group showed its amber badge while the Move
tool quietly moved the active layer instead (G-33).

Two commitments:

- **The active target changes only when the artist activates it.** Structural actions preserve it
  **by identity**, not by index. A sheet is a remote control: acting through it never relocates
  where the next stroke will land. This is the rule the mini-stack was shipped with; the engine now
  honors it rather than contradicting it.
- **The shell holds frames and layers by id wherever a reference outlives a mutation.** The
  move-group in particular becomes a set of layer ids, which makes a one-member group simply real
  (G-33 dissolves rather than needing a rule) and retires the entire index-drift class. The
  move-group is **transient**: cleared on frame change and on document change, because a move-group
  is a selection and selections do not survive navigation anywhere else in the Editor.

Alternatives rejected:

- **Acting activates** (retargeting the sheet also sets the active target, so the strip's blue
  border follows the sheet): simpler and matches the engine as built, but the drawing target then
  moves under the artist while the sheet is open, and closing the sheet leaves them painting on a
  layer they did not choose.
- **Explicit-only, compensated in the shell** (the shell re-sets the active target after each
  structural verb instead of the engine preserving it): keeps engine verbs frozen, at the cost of
  more call sites and a fresh drift surface — rejected once ADR 0015 accepted engine-side changes.
- **Per-frame move-group memory** (each frame remembers its own group): powerful for repetitive
  multi-layer edits, but it reintroduces persistent invisible state, which is the species of bug
  this survey catalogued.

Consequences: this is one of the three policies that changes engine semantics, and therefore rides
the replay fork accepted in ADR 0015 — a replayed frame delete or reorder now leaves a different
frame active than it did before. G-30 (the opacity slider recording one undo step per drag tick,
evicting the frame's 128-record history) is *not* closed by this policy; it needs a new
non-recording preview verb and is tracked as a point fix.
