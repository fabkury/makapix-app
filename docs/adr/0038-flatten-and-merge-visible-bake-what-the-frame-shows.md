# Flatten and Merge visible bake what the frame shows

**Decided and implemented 2026-11-17** (the choices are the user's, from a design proposal and a
question round). Engine: `crates/engine/src/session/frames.rs` (`collapse_frames`, behind the two
verbs `FlattenFrames` and `MergeVisible`). Shell: the layer sheet and the frame sheet
(`app/lib/editor/editor_page.sheets.dart`), and the Frames page's More sheet
(`app/lib/editor/frames/`). This is the first half of inventory item B24
(`docs/editor-gaps/INVENTORY.md`); "move a layer to another frame" is not part of it.

**Why.** Merging existed one layer at a time (`MergeDown`, layer sheet) and as one contiguous run
within one frame (`MergeLayers`, Layers page, ADR 0033). Nothing turned a frame into a single
layer, nothing merged "everything I can see", and nothing did either across several frames.

**What.** Two verbs, each taking a frame set (the ADR 0031 grammar), one undo record, one journal
line, all-or-nothing:

- **`FlattenFrames(set)`** — every member ends up with ONE layer that looks exactly like the frame
  did. Hidden layers are discarded.
- **`MergeVisible(set)`** — every member's VISIBLE layers become one layer, in the lowest visible
  layer's slot. Hidden layers stay where they are, untouched.

There is no single-frame twin: the sheets send the set verb with one index (`FlattenFrames(3)`).

**Decisions, and why:**

- **The result is the compositor's own output.** The merged pixels are `render::composite_frame`
  over the whole storage, so blend modes and opacities are baked exactly as the frame displays
  and exports, and pixels parked outside the canvas (ADR 0030) are kept. The merged layer is
  visible, Normal, opacity 255. This is what separates the two verbs from `MergeLayers`, whose
  survivor keeps its own opacity and blend: a stack whose bottom layer sits at 50 % changes its
  look when merged by hand, and never when flattened.
- **The survivor is the lowest merged layer**: it keeps its id, its name, its lock state and its
  place in the stack (the `MergeLayers` rule that the bottom member survives). With every layer
  hidden, Flatten keeps the bottom layer, blank.
- **Locks refuse** (the ADR 0033 rule that the lock guards pixels): a locked layer that the verb
  would merge or discard refuses the whole set, naming the first such frame. A locked HIDDEN
  layer does not stop Merge visible, which leaves it alone.
- **No confirmation**, as Merge and Merge down have none: one Undo brings everything back, and
  the Frames page status line says how many frames changed. (Tap-again, ADR 0022, was offered
  for Flatten because it discards hidden layers, and declined.)
- **Members with nothing to do are skipped, not refused**: a one-layer frame for Flatten, a frame
  with fewer than two visible layers for Merge visible. A set where every member is skipped is a
  no-op with no undo record. The shell disables the buttons and rows in that case, and the status
  line counts only the frames that changed.
- **The active layer keeps its identity when it survives**, else the merged layer becomes active;
  the Move group clears only when the active frame's active layer was merged away. The selection
  mask is never touched (the frame-set rule).
- **Not Repeatable** (ADR 0017), like every batch verb.

**Where it is in the UI.** One at a time: **Merge visible** and **Flatten frame** sit side by side
in the layer sheet (under Merge down, acting on the active frame) and in the frame sheet (a
Layers section, acting on the frame the sheet shows); both sheets stay open. In bulk: Frames page
→ More → Layers → **Merge visible layers** and **Flatten**, over the selected frames.

**Declined.** "Merge down layer named…" across frames (proposed, not wanted). A row on the Layers
page: Select all + Merge already collapses a stack there, with Merge's rules.
