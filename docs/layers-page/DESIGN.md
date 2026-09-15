# The Layers page — design

**Decided 2026-09-14** in a design interview (every decision below is the user's; assumptions are
marked). **Implemented 2026-09-15** (see "As built"). Doctrine: ADR 0033. Brainstorm and rationale
for the proposal set: `BRAINSTORM.md` in this folder. Companion and model: the Frames page
(`docs/frames-page/DESIGN.md`, ADR 0031) — wherever a layer set behaves like a frame set, this page
copies that decision rather than restating it.

Motivation: the cap is 128 layers per frame (ADR 0032) and both layer controls — the film strip
and the layer sheet — act on one layer at a time. "Hide the twelve guide layers", "merge these
five sketch layers", "delete every empty layer", "move the shading layers above the line art" is a
dozen taps each, or a scroll-and-hunt through 128 rows.

## As built (2026-09-15; deviations from and refinements of the decisions below)

- **Merge takes one contiguous run.** The interview's answer was "contiguous runs only"; the
  verb refuses a set with a gap rather than merging several runs at once (the ADR's reading,
  simpler to explain and to undo). A run of one member is a no-op. The page pre-checks the gap
  and the locked members on its status line before the verb is sent.
- **Layer ids in `frame_detail`.** Every layer entry now carries `"id"` (additive); the page's
  selection is keyed by it. An older engine without ids falls back to the index.
- **Locked members grey out the Content chips** in the More sheet and the first fixed slot
  reads "N selected layers are locked — these refuse"; the page also refuses on its status line
  if a content op reaches it. Duplicate and Insert blank grey out at the cap with the cap note.
- **Copy to frames…** takes a 1-based frame range with "All frames" and "Other frames" chips
  (the Frames page's range parser); the report says how many layers went to how many frames.
- **Use as Move group** pops with the ascending indices; the editor sends `SetActiveLayers(S)`
  (the first member becomes active) and mirrors the group on the strip's chips. Make active pops
  with the index. A plain close clears the Move group only when the stack's ids or the active
  layer's id changed under the page.
- **Row density** is one switch ("Bigger rows" / "Smaller rows", 44 vs 60 px), persisted
  editor-wide (`editor.layersRoomyRows_v1`), not a stepper.
- **The sweep clamps to the list's ends** (a finger past the top or bottom means "up to the
  edge"); there is no rubber-band (rows fill the width) and no pinch (no columns).
- **The layer sheet completes when it closes** (`_layerOptions` returns the sheet's future) so
  the page's "Layer options…" can re-sync afterwards, as the Frames page does with the frame
  sheet.
- **Refusals** ride `refusal_seq` / `last_refusal`; the editor's generic refusal toast (ADR 0032)
  is suppressed around the page's verbs, since the status line narrates them.
- **Rename** shows a live preview ("Sketch 1, … Sketch 5") under the field; names are capped at
  64 characters as in the single-layer dialog.
- **Blend…** commits on pick (no live preview over the set); the picker pre-checks the current
  mode when every member shares one.
- **Shift+Y** is the Command `page.layers`; ☰ → Layers… and the layer sheet's top "Layers…" button
  are the other entries.

## What it is

A full-screen page, pushed over the editor like the Frames page, that lists **every layer of the
active frame**, top of the stack first, and lets the artist **select any set of layers** —
contiguous or not — and **apply one operation to the set at once**: delete, duplicate, merge,
shift, reverse, insert blanks, show/hide, lock/unlock, opacity, blend, rename, reset, flip, rotate,
invert, clear, copy to frames, and hand the set to the Move group.

Every batch is **one engine verb on a layer set, one undo step, one journal line, all-or-nothing**,
refused with a reason when it cannot apply whole. The page covers **the active frame only**; reach
across frames stays with the Frames page's name-based family and with "Copy to frames…".

Workflows the page exists for:

- **Survey** — read the whole stack at once: names, what is hidden or locked, which layers are
  empty, which carry a blend mode or reduced opacity, what each contains.
- **Reach** — make a far layer active in two taps.
- **Tidy** — delete the empty layers, merge the sketch layers, rename a family, reset properties
  before publishing.
- **Stage** — hide or lock a family while working on another; show everything again.
- **Restructure** — move a group of layers as one body, reverse a run, insert a blank above each
  member.
- **Batch-set properties** — one opacity or one blend mode on many layers.
- **Batch content** — flip, rotate, invert, or clear chosen layers only.
- **Hand off** — turn the selection into the Move group; copy the selection into chosen frames.

## Decisions (2026-09-14)

### Framing (fixed before the brainstorm)

| Question | Decision |
|---|---|
| Scope | **The active frame's stack.** No layer × frame matrix; no "also on all frames" switch on batches |
| Presentation | **List rows, top of the stack first** (thumbnail, name, badges, opacity, blend). Not a grid |
| Reach | **Bulk versions of existing per-layer capabilities.** No groups, linked layers, alpha lock, clipping, solo |
| Reorder | **Rigid shift by buttons** (▲ ▼ hold-to-repeat, Top, Bottom), the Frames rule. No drag |
| Merge | **Contiguous runs only**; a set with a gap is refused |

### Model

| Question | Decision |
|---|---|
| Name | **Layers.** Page title "Layers · N", menu "Layers…", `LayersPage`, this folder |
| Batch model | **Engine batch verbs**, each taking a **layer set** on the active frame; **one undo step per batch**; one journal line; one replay tick |
| Failure policy | **Refuse the whole batch and explain** (the Frames rule). The page pre-checks the layer cap, "would empty the frame", locked members, and gaps in a Merge set and disables or annotates the control before the tap; the engine's refusal is the authority |
| Numbering | **From the bottom.** Row numbers, Range entry and the wire count the bottom layer as 1 (0 on the wire) — the layer sheet's "Layer N of M" and every existing layer verb already do. On screen the numbers run downward (top row = the highest number) |
| Delete covering every layer | **One blank layer replaces the stack** — the `RemoveLayersNamed` rule, not the single Delete's refusal: fresh id, "Layer 1", visible, unlocked, opacity 255, Normal; it becomes the active layer |
| Locked members | **Content batches and Merge refuse** when any member is locked ("3 selected layers are locked — unlock them first"; all-or-nothing). **Property batches (show/hide, lock/unlock, opacity, blend, rename, reset) and reorder ignore the lock** — the lock guards pixels, as the single verbs treat it |
| Badges | **Display only.** Every tap on a row is a selection tap; visibility and lock change through the action bar on the set. One gesture model |
| Merge preview | **None.** Merge applies at once; the status line reports; Undo is one tap away |
| Rename | **One name, with `{n}`**: a name containing `{n}` expands to the member's 1-based rank in the set, **top first** ("Sketch {n}" → Sketch 1 … Sketch 5 from the top down). No other tokens in v1 |
| Selection helpers | **Replace by default, with one persistent "Add to selection" switch** on the Select sheet that turns every helper into an add |
| Copy to frames | **Both paths stay.** The layer sheet keeps its one-tap lenient "Copy to all frames" (`DuplicateLayerToFrames`, skips full frames, parses forever); the page's strict "Copy to frames…" takes the set and a frame range |
| Active target | **Changes only when its layer is removed or merged away** (ADR 0013 applied to sets; the Frames rule). After a Delete that removes it: **the layer now at the same index, clamped** — the single `RemoveLayer` rule. After a Merge whose run contains it: **the run's survivor** (the run's bottom member keeps its id). Batches that duplicate, reorder, rename or retag never move it |
| Selection identity | A **set of layer ids**, never indices, so it survives reorders, undo, and redo. **Discarded when the page closes** — transient like the Move group |
| Pixel-selection mask | Batch verbs **never touch the marquee**; content transforms are whole-storage per member, mask ignored — the frame-verb semantics restricted to the chosen layers |
| Move group | Cleared whenever the active frame's stack changed (the single verbs' rule) — **except by "Use as Move group"**, which sets it to S and pops to the editor |
| Wiring | Layer sheet top button **"Layers…"** · **☰ → Layers…** · keyboard Command `page.layers`, **Shift+Y** (Y opens the layer sheet; T / Shift+T set the pairing precedent). Not a strip button (the ⊞ lesson). "Use as Move group" and Make active **pop to the editor** |

### Operations (v1 — everything below ships; the declined rows are under "Out of scope")

| Family | Operation | Semantics on the set S (active frame implied) |
|---|---|---|
| Structural | **Delete** | Remove every member; when S covers every layer, one blank layer replaces the stack. Tap-again confirm (ADR 0022) |
| | **Duplicate** | Each copy lands **right above its source**, named as the single Duplicate names it; afterwards **the copies are the selection**. Refused when `n + |S| > 128` |
| | **Merge** | Each **contiguous run** of S composites **top-down into the run's bottom member** — repeated `MergeDown` inside the run, so byte-identical to doing it by hand: a hidden or opacity-0 member contributes nothing, every other member composites with its own blend and opacity; the survivor keeps its id, name, visibility, lock state, opacity and blend. A run of one member is a no-op for that run. Refused when S has a gap ("Merge needs a contiguous run") or any member is locked. The status line reports "Merged 5 layers into Sketch" |
| | **Shift ▲ ▼ by N** | Rigid body (gaps kept, unselected layers flow around), clamped to the room; ▲ moves toward the top of the stack. Hold-to-repeat; disabled at the edge. A clamp to zero is a no-op with no undo record |
| | **Top / Bottom** | Shift by the maximum room (gaps kept — a shift, not a gather) |
| | **Reverse** | The members swap places among the selected slots; `|S| < 2` is a no-op |
| | **Insert blank above / below** | One blank layer per member, adjacent to it ("Layer N" default name, visible, unlocked, 255, Normal); the active layer does not move. Refused past the cap |
| State | **Show / Hide** | Set visibility on every member (two buttons, not a toggle, so a mixed set lands in one state) |
| | **Lock / Unlock** | Set the lock on every member |
| | **Opacity…** | The existing opacity dialog (slider, 0–255) applied to S |
| | **Blend…** | The existing 10-mode picker applied to S; commit on pick (no live preview over the set — assumption) |
| | **Reset** | Opacity 255, Normal, visible, unlocked on every member |
| Name | **Rename…** | One name for every member; `{n}` expands to the top-first rank. 64-character cap as today |
| Content | **Flip H / Flip V** | Whole storage (canvas + gutter) of each member — the per-layer half of `FlipFrameH/V` |
| | **Rotate 90 / 180 / 270** | Each member rotates about the storage center through the same resampler as `RotateFrame`, so the overhang parks in the gutter on a non-square canvas; pinned byte-identical to rotating the frame with the other layers untouched |
| | **Invert** | Per member — the per-layer half of `InvertFrame` |
| | **Clear** | Every pixel of each member erased; the layer stays, empty. A new verb (no single-layer twin exists in the DSL) |
| Across frames | **Copy to frames…** | The members, in stack order, pushed **on top** of each chosen frame's stack (the `CopyLayerToFrames` placement); a 1-based frame-range entry with an "All frames" chip. Strict: refused when any target would pass 128. The source frame may be in the range (it gets copies of its own layers on top; the artist chose it) |
| Bridges | **Use as Move group** | `SetActiveLayers(S)` — the first member becomes active, the set becomes the Move group — and pop to the editor |
| | **Make active** | Double-tap a row, or the row menu: `SetActiveLayer` + pop |
| | **Layer options…** | The row menu opens the single-layer sheet for that row |

### Selection helpers (v1)

| Helper | Selects |
|---|---|
| **All · None · Invert** | — |
| **Range entry** | 1-based bottom-first text (`1-4, 9, 20-25`), the Frames parser; reversed ranges swapped; out-of-range rejected inline |
| **Empty** | Layers with no present tile (`present_tiles == 0` in `frame_detail`) |
| **Hidden · Visible · Locked · Unlocked** | By flag |
| **Non-Normal blend · Translucent** | Blend ≠ Normal; opacity < 255 |
| **Add to selection** (switch) | When on, every helper above adds to the current selection instead of replacing it; persisted for the page's lifetime only (assumption) |

### Interaction

| Question | Decision |
|---|---|
| Row | Top of the stack first. Thumbnail of **that layer only** on the checker (the strip's rendering) · name · eye and lock badges (display only) · opacity as a percentage when < 100 · blend token when non-Normal · an "empty" tag when the layer has no pixels · the active-layer marker in the strip's blue · **amber** wash + border + check when selected · the bottom-first row number |
| Tap | **Toggles selection** |
| Sideways slide | **Sweeps**: the first row flips, every row crossed takes that state (a paint); an up/down slide scrolls — the Frames arena rule. Edge auto-scroll while sweeping; a second finger cancels the sweep and restores the selection (the Frames pinch rule) |
| Long-press | **Row menu**: Make active · Select to here (from the anchor) · Layer options… . Right-click on desktop |
| Double-tap | **Make active** and pop (detected by hand, as on Frames, so the first tap toggles instantly) |
| Action bar | **Fixed height**, bottom, enabled only with a non-empty selection: **Delete · Merge · ▲ ▼** (one "Shift" label under the pair) **· More**. Never reflows the list |
| More sheet | Sections **Stack** (Duplicate · Top · Bottom · Reverse · Insert blank above · Insert blank below) · **State** (Show · Hide · Lock · Unlock · Opacity… · Blend… · Reset) · **Name** (Rename…) · **Content** (Flip H · Flip V · Rotate 90/180/270 · Invert · Clear; a fixed amber slot for the locked-member note and a second for the non-square rotate note) · **Across frames** (Copy to frames…) · **Move group** (Use as Move group). Fixed slots, no reflow (the Frames sheet's rule) |
| Select sheet | The helpers above as chips, plus the "Add to selection" switch |
| Row density | "Bigger rows" / "Smaller rows" in the page's overflow menu; persisted editor-wide (`editor.layersRowSize_v1`; assumption) |
| Desktop | **Shift-click** range from the anchor, **Ctrl-click** toggle, **Ctrl+A**, **Esc** clears (pops when already empty), **Delete/Backspace** arms (ADR 0022), **↑ ↓** shift the selection, **Ctrl+Z / Ctrl+Y**, **Enter** = Make active when exactly one row is selected. One selection model |
| Undo / redo inside the page | **Yes**: app-bar buttons + the keys; the selection survives by id; visible thumbnails re-validate through the memoized layer hash |
| Status line | The fixed 22 px line between the list and the bar carries refusals and reports; never a SnackBar (the editor's own refusal toast is suppressed around the page's verbs, as the Frames page does) |
| Drafts and playback | Playback pauses on entry. Pushing the page is not a context change; every batch verb is |

## The model

### Layer set

A **layer set** is one DSL argument with the frame set's grammar, **0-based bottom-first on the
wire** like every existing layer verb:

```
LAYERSET := ITEM (' ' ITEM)*
ITEM     := N | N-M            0 ≤ N ≤ M
```

The parser is the frame set's (canonicalize: sort, dedup, coalesce; an empty set is a parse
error; an index at or beyond 128 is a parse error; an in-cap index at or beyond the frame's layer
count refuses at execution). The shell always emits the canonical form. Whitespace separates
items so free text (a name) can follow after the first comma, as `RemoveLayersNamed` does.

### Verbs (all on the active frame)

```
RemoveLayers(S)                          S = every layer → one blank "Layer 1" replaces the stack
DuplicateLayers(S)                       copies right above their sources;   refuse: n+|S| > 128
MergeLayers(S)                           contiguous runs, top-down into each run's bottom member;
                                         refuse: a gap in S, a locked member
ShiftLayers(S, delta)                    rigid; + = toward the top; clamped; 0 → no-op, no record
ReverseLayers(S)                         |S| < 2 → no-op, no record
InsertBlankLayers(S, above|below)        one blank per member;               refuse: n+|S| > 128
SetLayersVisible(S, 0|1)  SetLayersLocked(S, 0|1)
SetLayersOpacity(S, 0..255)  SetLayersBlend(S, Mode)
ResetLayers(S)                           255 · Normal · visible · unlocked
RenameLayers(S, name)                    trailing free text; {n} = top-first rank in S
FlipLayersH(S)  FlipLayersV(S)  RotateLayers(S, quarters)  InvertLayers(S)  ClearLayers(S)
                                         refuse: a locked member
CopyLayersToFrames(S, F)                 F a frame set; strict; refuse: any target past 128
SetActiveLayers(S)                       exists (the Move group)
```

Every verb runs inside one `edit_frame` (or `edit_doc` for `CopyLayersToFrames`) and therefore
records **one undo record**, is subject to the post-mutation memory gate (rolled back wholesale
over the hard budget), and clears the Move group whenever the stack changed. None is Repeatable
(ADR 0017). Top / Bottom are `ShiftLayers` with `±128` (the clamp does the rest); the shell emits
the clamped value so the journal reads plainly (assumption).

**Rigid shift, precisely** — the Frames rule with the stack as the axis: `k = clamp(delta,
−min(S), (n−1) − max(S))`; each member `i` goes to slot `i + k`; the unselected layers fill the
remaining slots in their old order. The journal stores the requested delta; replay re-clamps
identically.

**Merge, precisely.** S must be one run of consecutive indices (a gap refuses). From the top
member down to the second-lowest: composite it onto the member below it exactly as `MergeDown`
does (skip when hidden or opacity 0; else `color::composite(blend, src, dst, opacity)` per pixel
over the whole storage), then drop it. The survivor is the run's lowest member; its properties
are untouched. Pinned byte-identical to a hand sequence of `MergeDown`
(`merge_layers_is_byte_identical_to_merge_down_and_moves_the_active_to_the_survivor`).

**Delete-all, precisely.** When S covers every layer, the frame's stack becomes `[blank]` with a
fresh id; `active_layer = 0`; the Move group clears. Journals replay it identically.

**Refusal channel.** `refusal_seq` / `last_refusal` in `state_json` (ADR 0031); the page shows
the reason on its status line and suppresses the editor's toast around its verbs (ADR 0032's
`_suppressRefusalToast`). A refused verb is still journaled and refuses identically on replay.

### Engine prerequisites

None new. Layer thumbnails are already point-sampled (`layer_thumb_bytes` samples the canvas
window of one layer, no composite) and the per-layer pixel hash is memoized since ADR 0031, so a
128-row list re-validates at a usable rate. The frame-set parser is reused for layer sets.

## Shell

- **`app/lib/editor/layers/`** — `layers_page.dart` (the route), `layer_selection.dart` (the
  Frames selection model generalized over ids — or the same class reused; pure Dart, testable
  without the engine), `layer_row.dart`, `layers_action_bar.dart`, `layers_more_sheet.dart`,
  `layers_select_sheet.dart`, `layers_host.dart`, `layers_dialogs.dart` (Range entry, Rename with
  `{n}`, Copy-to-frames range).
- **Host, not engine.** `LayersHost` built by the editor: `layerDetail` (the active frame's
  `layers` from `frame_detail`), `activeLayerId`, `activeFrame`, `frameCount`, `run(dsl)` (through
  `_act` with the refusal toast suppressed), `undo()`, `redo()`, `thumbBytes(layerIndex)`,
  `layerHash(layerIndex)`, `lastRefusal`. The page pops with an optional Make-active index or a
  Move-group set.
- **Thumbnails by id.** An LRU keyed by layer id, ≈150 entries; the editor's index-keyed strip
  cache self-heals through the memoized hash on return.
- **Verb lists.** The batch verbs join `_isContextChangeVerb`, the layer-structure list that
  clears the strip's group state, and the replay classifier's `_kAlwaysEvent` so a 50-layer merge
  is one event beat.
- **Delete** uses `TapAgainDeleteButton` with `armKey = (selection signature, _sendSeq)`.
- **Layer ids in `frame_detail`.** The state JSON's layer entries carry no id today (frames do);
  the page's id-keyed selection needs `"id"` per layer entry — an additive field, one line in
  `probe.rs`, and the only engine-side change beyond the verbs.

## Edge-case policy (decided; listed so nobody re-litigates mid-implementation)

- **Cap refusals are atomic.** Duplicate, Insert, Copy-to-frames pre-check the cap before
  mutating; the memory gate rolls back wholesale.
- **Content batches and retained tiles** follow the Frames policy: billed by the tiles the record
  retains, evicted by the 96 MiB history budget, warned in the More sheet above 64 MB, never
  refused on memory grounds.
- **Locks.** A locked member refuses Flip, Rotate, Invert, Clear and Merge (the whole batch); it
  does not refuse Delete, Duplicate, Shift, Reverse, Insert, Show/Hide, Lock/Unlock, Opacity,
  Blend, Reset, Rename, Copy-to-frames, or the Move-group bridge. The More sheet's Content slot
  reads "N selected layers are locked" before the tap.
- **Merge with a hidden or transparent member** drops it (it contributes nothing), as `MergeDown`
  does; the status line's count includes it ("Merged 5 layers").
- **Active layer inside a Merge run** moves to the survivor; **inside a Delete** it follows the
  single `RemoveLayer` rule (same index, clamped); **when the Delete emptied the frame** it is the
  blank.
- **Duplicate names** the copies as the single Duplicate does (assumption: the same name — the
  engine's `duplicate_layer` rule), and the copies become the selection, found by id.
- **Rotate on a non-square canvas** parks the overhang in the gutter; the note shows in the
  Content section as on Frames.
- **Copy-to-frames with the source frame in the range** pushes copies of the members on top of
  the source's own stack; refused with the rest if that would pass 128.
- **Refused batch:** nothing changed, the selection stays.
- **Undo inside the page:** restored layers keep their ids, so the id-keyed selection survives;
  members that no longer exist drop out silently.
- **Journal epoch stays 3.** New verbs with self-contained semantics; an older build fails at the
  first such line, as for any verb added after it.
- **Names with commas** survive: the name is the trailing free text after the fixed arguments.
- **`{n}` in a name that is not a rename pattern.** A literal `{n}` cannot be given through the
  page's Rename; the single-layer sheet's Rename still takes any text. Accepted.

## Out of scope for v1 (declined in the interview, or deferred)

- **Same-named on all frames** (show/hide/lock/unlock/remove by name over every frame) from this
  page — declined; the Frames page has it from the frame side.
- **Above / Below the active layer** and **same name prefix** selectors — declined for v1.
- **Every Nth** and **same content** selectors — deferred.
- **Drag-to-reorder**, **gather move**, **move layers to another frame**, **relative opacity**,
  **per-set trim / palettize / outline**, **merge preview**, **badge fast-taps**, an **"also on
  all frames" switch**, a **layer × frame matrix**, **groups / linked layers / alpha lock /
  clipping / solo**, a **persistent selection**, a **resizable in-editor panel** — deferred, as
  listed in `BRAINSTORM.md`.

## Effort (rough)

| Piece | Estimate |
|---|---|
| Layer-set argument (shared parser) + 16 verbs + `id` in `frame_detail` + unit tests + `assert.undo` scripts + the Merge and Rotate byte-identity pins | 2 days |
| Selection model (generalized from Frames) + page + rows + action bar + More/Select sheets + dialogs + desktop input | 3 days |
| Verb-list wiring, replay classifier, layer-sheet button, ☰ item, Shift+Y Command, docs, ADR | ½ day |
| Windows mouse pass + Pixel pass (a 128-layer 512² frame) | 1 day |

## Documentation

- ADR 0033 (draft, this folder's doctrine) — accepted when implementation starts.
- CONTEXT.md: **Layer set** (a set of layers of one frame, named by bottom-first index on the
  wire and by id in the shell) and **Layers page**; the page's selection is transient like the
  Move group.
- STATUS.md: a "Layers page" row on implementation.
- `docs/memlab/REPORT.md`: a 128-layer merge and a 128-layer content batch join the next device
  pass.
