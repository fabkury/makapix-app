# Committing text joins the Repeat set

**Decided 2026-11-19** (user decisions, from the Text tool design interview). **Implemented
2026-11-23** (`RepeatOp::Mask` in `crates/engine/src/session.rs`). Extends ADR 0017, whose repeatable set is closed and grows one decision at a time
(ADR 0024 added the Bucket fill the same way). The Text tool itself is ADR 0039.

**What.** Committing a Text Draft arms Repeat. Pressing Repeat stamps the same text again on the
live target: commit a caption on one frame, step to the next, press Repeat.

**Why.** Stamping one text onto a whole frame set was kept out of the Text tool's first version.
Repeat gives the common case (the same caption, at the same place, on several frames) for almost
nothing, because the commit already is a self-contained mask and a position.

**What is snapshotted, and what is live:**

- **Snapshot at commit:** the plain glyph mask, its position, and the primary color. Color follows
  the ADR 0017 rule ("same thing, same color, on the next frame").
- **Live at Repeat time:** the active frame and layer, the selection, **and Symmetry and the
  Pattern.** The alternative, storing the finished pixels with their mirrored copies and pattern
  gaps so Repeat is pixel-identical, was offered and declined: the user wants a repeated text to
  take whatever Symmetry and Pattern are active when Repeat is pressed.

The last point is the surprising one. Paste's Repeat snapshots the stamped pixels themselves, and
the Bucket snapshots its settings; text snapshots only its content and color. A caption repeated
across frames therefore stays identical only while Symmetry and the Pattern are left alone
between presses.

**Consequences.** A new `RepeatOp` variant. **No Journal epoch bump**, contrary to what this ADR
first said: an epoch marks a change in what an EXISTING journal replays to (ADR 0024 bumped it
because a recorded `Repeat()` after a fill started to mean something else). No journal written
before this change contains a `MaskStamp`, so none replays differently, and an older app skips
the unknown line as it skips any other.
This ADR adds exactly the text commit; it does not open the set to other mask-shaped operations.
