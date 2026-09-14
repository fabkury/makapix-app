# The Layers page acts on layer sets of the active frame through atomic batch verbs

**Draft — decided 2026-09-14 in a design interview, not yet implemented** (every choice is the
user's; the design, its edge-case policy, and the interview's answers live in
`docs/layers-page/DESIGN.md`; the proposal set and its rationale in
`docs/layers-page/BRAINSTORM.md`). Accepted when implementation starts. Sibling of ADR 0031,
whose model it copies wherever a layer set behaves like a frame set.

**Why.** The cap is 128 layers per frame (ADR 0032) and the film strip and layer sheet act on one
layer at a time. Bulk manipulation of a stack — hide a family, merge a run, delete every empty
layer, move a group up — needs a set model, not more single verbs.

**What.** A full-screen **Layers page** lists the active frame's stack top-first and holds a
transient selection of **layer ids**. Every operation is **one engine verb taking a layer set**
(the frame set's grammar, 0-based bottom-first on the wire), runs inside one edit, records **one
undo step**, one journal line, one replay tick, and is **all-or-nothing**: a set that would pass
the cap, a Merge set with a gap, or a content batch with a locked member **refuses** through the
generic refusal channel and changes nothing. Sixteen verbs: `RemoveLayers`, `DuplicateLayers`,
`MergeLayers`, `ShiftLayers`, `ReverseLayers`, `InsertBlankLayers`, `SetLayersVisible`,
`SetLayersLocked`, `SetLayersOpacity`, `SetLayersBlend`, `ResetLayers`, `RenameLayers`,
`FlipLayersH/V`, `RotateLayers`, `InvertLayers`, `ClearLayers`, `CopyLayersToFrames`; the existing
`SetActiveLayers` is the bridge to the Move group.

**Decisions that differ from the single verbs or from Frames, and why:**

- **Numbering is bottom-first everywhere** (rows, Range entry, wire), matching the layer sheet
  and every layer verb, even though the list reads top-down. One numbering beats a conversion.
- **Deleting every layer replaces the stack with one blank layer** instead of refusing — the
  `RemoveLayersNamed` rule, chosen over the single Delete's refusal so "clear this frame's stack"
  is one batch.
- **Locks refuse content batches and Merge, and nothing else.** The lock guards pixels; property
  changes, reorder, duplicate and delete pass through as the single verbs already allow.
- **Merge acts on contiguous runs only**, composited top-down into each run's bottom member by
  the `MergeDown` rule, so the result is byte-identical to doing it by hand and blend modes never
  jump over an unselected layer. A gap refuses.
- **Rename takes one name with `{n}`** (top-first rank); no other tokens in v1.
- **Selection helpers replace by default; one "Add to selection" switch** turns them into adds.
- **Badges are display-only**; every tap selects. One gesture model, no mis-taps while sweeping.
- **Reorder is rigid shift by buttons**, never drag; **Merge has no preview**; the sheet's lenient
  "Copy to all frames" **stays** beside the page's strict "Copy to frames…".

**Consequences.** The engine gains a layer-set argument (the frame-set parser reused), sixteen
verbs pinned by `assert.undo` scripts and two byte-identity tests (Merge vs a `MergeDown`
sequence; Rotate vs `RotateFrame` with the other layers untouched), and a layer `id` in
`frame_detail`. No new thumbnail or hash work: layer thumbnails are already point-sampled and the
layer hash memoized (ADR 0031). The shell gains the page, the generalized selection model, the
sheets and dialogs, a "Layers…" button at the top of the layer sheet, ☰ → Layers…, and Shift+Y.
Journal epoch stays 3. Declined for v1 and recorded as follow-ups: the same-named-on-all-frames
family from this page, the above/below and name-prefix selectors, drag-to-reorder, gather move,
and every new layer concept (groups, linked layers, alpha lock, clipping, solo).
