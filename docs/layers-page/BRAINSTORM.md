# The Layers page — brainstorm

**Proposals, 2026-09-14. Nothing here is decided or built.** Framing fixed by the user before the
brainstorm: the page covers **the active frame's stack only**; layers are **list rows, top of the
stack first**; the reach is **bulk versions of what a single layer can already do** (no new layer
concepts); reordering is **rigid shift by buttons** (no drag); **Merge acts on contiguous runs
only**. Everything else below is a proposal, with the questions a design interview would settle
listed at the end. Companion: the Frames page (`docs/frames-page/DESIGN.md`, ADR 0031), whose
model this page copies wherever a layer set behaves like a frame set.

Motivation: the cap is now 128 layers per frame (ADR 0032) and the two layer controls — the film
strip and the layer sheet — are one-layer-at-a-time. "Hide the twelve guide layers", "merge these
five sketch layers", "move the shading layers above the line art", "delete every empty layer" is a
dozen taps each, or a scroll-and-hunt through 128 rows.

## What it is

A full-screen page, pushed over the editor like the Frames page, that lists **every layer of the
active frame** top-down and lets the artist **select any set of layers** — contiguous or not — and
**apply one operation to the set at once**. Every batch is **one engine verb on a layer set, one
undo step, one journal line, all-or-nothing**, refused with a reason when it cannot apply whole.

Workflows the page exists for:

- **Survey** — read the whole stack at once: names, what is hidden or locked, which layers are
  empty, which carry a blend mode or reduced opacity, what each contains (thumbnail).
- **Reach** — make a far layer active in two taps instead of scrolling the strip.
- **Tidy** — delete the empty layers, merge the sketch layers, rename a family, collapse a stack
  before publishing.
- **Stage** — hide or lock a family of layers while working on another; show everything again.
- **Restructure** — move a group of layers up or down the stack as one body, reverse a run,
  insert a blank above each member.
- **Batch-set properties** — one opacity or one blend mode on many layers.
- **Batch content** — flip, rotate, invert, or clear the pixels of chosen layers only (the frame
  twins act on every layer).
- **Hand off** — turn the selection into the Move group (the existing multi-layer drag), or copy
  the selected layers into chosen frames.

## Operations (proposed)

Tiers: **A** = the page is not worth shipping without it · **B** = cheap and clearly useful,
in v1 unless cut · **C** = wanted, but a follow-up. `S` is the selected set; the active frame is
implied throughout.

### Structural

| Tier | Operation | Semantics on S | Refusal / edge policy |
|---|---|---|---|
| A | **Delete** | Remove every member | Refused when S covers every layer (the single Delete refuses at one layer) — *or* a blank layer replaces the stack, the `RemoveLayersNamed` policy; **question 2**. Tap-again confirm (ADR 0022) |
| A | **Duplicate** | Each copy lands **right above its source**; the copies become the selection | Refused when `n + |S| > 128` (pre-checked, engine authoritative) |
| A | **Merge** | Each **contiguous run** of S composites top-down into the run's **bottom member**, which keeps its id, name, opacity and blend; the other members vanish. A run of one is a no-op | Refused when S has a gap ("select a contiguous run") and when any member is locked (**question 3**). Semantics = repeated `MergeDown` within the run, so byte-identical to doing it by hand |
| A | **Shift ▲ ▼ by N** | Rigid body (gaps kept, unselected layers flow around), clamped to the room; the nudge buttons hold-to-repeat and disable at the edge | Clamp to zero = no-op, no undo record |
| B | **Top / Bottom** | Shift by the maximum room (a shift, not a gather: gaps kept) | — |
| B | **Reverse** | The members swap places among the selected slots | `|S| < 2` = no-op |
| B | **Insert blank above / below** | One blank layer per member, adjacent to it, default name, becomes nothing's active layer | Cap pre-check |
| C | **Gather ("Move here")** | Collect a discontiguous set into one block at a slot | Declined for Frames; same stance until asked |

### Properties

| Tier | Operation | Semantics on S | Notes |
|---|---|---|---|
| A | **Show / Hide** | Set visibility on every member | Two buttons, not a toggle, so a mixed set lands in one state |
| A | **Lock / Unlock** | Set the lock on every member | As above |
| A | **Opacity…** | The existing opacity slider dialog applied to S (0–255) | A "relative" mode (±N, ×k) is C |
| A | **Blend…** | The existing 10-mode picker applied to S | Preview while picking = the single-layer `PreviewLayerBlend` path over the set, if cheap; else commit-on-pick |
| B | **Rename…** | One name for all, or a pattern with `{n}` (1-based rank in S) / `{i}` (stack index) / `{name}` (old name): `Sketch {n}`, `{name} (old)` | Names cap at 64 characters, as today |
| B | **Reset** | Opacity 255, Normal blend, visible, unlocked in one tap | A "clean slate before merge/publish" helper |

### Content (pixels of the member layers only)

| Tier | Operation | Semantics on S | Notes |
|---|---|---|---|
| A | **Flip H / Flip V** | Whole storage (canvas + gutter) of each member, as `FlipFrameH/V` does per layer | Locked members: refuse or skip — **question 3** |
| B | **Rotate 90 / 180 / 270** | About the storage center, overhang parks in the gutter (the frame rule); factored into the pure per-layer rotation the frame verb already uses, pinned byte-identical | Non-square note as on Frames |
| B | **Invert** | Per member | — |
| B | **Clear** | Erase every pixel of each member (the layer stays, empty) | No single-layer twin exists in the DSL (Select all + Delete does it); a one-line verb |
| C | **Trim / Crop to content**, **Palettize**, **Outline** on the set | The tool-page operations over many layers | Later; each is a real feature, not a batch twin |

### Across frames (the Frames page's name-based family, from the other side)

| Tier | Operation | Semantics | Notes |
|---|---|---|---|
| A | **Copy to frames…** | The selected layers, in stack order, pushed on top of each chosen frame; a frame-range entry (1-based, like the Frames page's) with "All frames" | Strict: refused when any target would pass 128. Generalizes `CopyLayerToFrames` from the active layer to S |
| B | **Show / Hide / Lock / Unlock / Remove same-named on all frames** | For each member, apply the existing `SetLayersVisibleNamed` / `SetLayersLockedNamed` / `RemoveLayersNamed` with the frame set = every frame | Reuses shipped verbs; the sheet shows hit counts per name before the tap. An "also on all frames" switch on every batch was considered and set aside (framing) |
| C | **Move layers to another frame** | Cut from this frame, push onto another | Gaps inventory B24; later |

### Selection helpers

| Tier | Helper | Selects |
|---|---|---|
| A | **All · None · Invert** | — |
| A | **Range entry** | 1-based text (`1-4, 9, 20-25`), same parser as Frames; numbering direction is **question 1** |
| B | **Visible / Hidden**, **Locked / Unlocked** | By flag; each *adds to* the current selection when it is non-empty, else replaces (or a 3-way "replace / add / subtract" chip row) |
| B | **Empty** | Layers with no present tile (the state JSON already carries `present_tiles`) — the "delete every empty layer" workflow in two taps |
| B | **Non-Normal blend**, **Translucent** (opacity < 255) | By property |
| B | **Above / Below the active layer** | The stack half, for "hide everything above" |
| B | **Same name prefix as the active layer** | `Sketch 1..12` — the family selector; exact match is a subset |
| C | **Every Nth** | Copied from Frames; less useful for layers |
| C | **Same content** | Needs the cached layer hash (the frame hash's per-layer memo exists since ADR 0031, so this is cheap now) |

### Bridges

| Tier | Feature | Why |
|---|---|---|
| A | **Use as Move group** | `SetActiveLayers(S)` — the page becomes the way to pick a 20-layer Move group; pops to the editor with the group set |
| A | **Make active** (double-tap / menu) | `SetActiveLayer` + pop, like Frames' Go to |
| B | **Layer options…** (menu) | Opens the single-layer sheet for one row |
| B | **Frames…** cross-link | The More sheet links to the Frames page and vice versa, so "this layer across frames" is one hop away |

## Interaction (proposed, mirroring Frames wherever a row behaves like a tile)

- **Row** (top of stack first): thumbnail of *that layer only* on the checker · name · eye and
  lock badges · opacity as a percentage when < 100 · blend token when non-Normal · an "empty"
  tag when the layer has no pixels · the active-layer marker in the strip's blue · **amber**
  wash + border + check when selected. Rows are dense enough for 128 entries with names; a
  "Bigger rows" / "Smaller rows" density toggle in the overflow menu, persisted editor-wide.
- **Tap** toggles selection. **Sideways slide** sweeps (the first row flips, every row crossed
  takes that state; an up/down slide scrolls — the Frames arena rule). **Long-press** opens the
  row menu: Make active · Select to here · Layer options… . **Double-tap** = Make active and pop.
  **Right-click** = the row menu on desktop.
- **Badge taps.** Tapping a row's eye or lock could flip that one layer immediately (the strip's
  fast path); it competes with "tap toggles selection" — **question 4**.
- **Action bar** (fixed height, bottom, enabled with a non-empty selection): **Delete · Merge ·
  ▲ ▼ (one "Shift" label) · More**. The More sheet in sections: **Stack** (Duplicate, Top, Bottom,
  Reverse, Insert blank above/below) · **State** (Show, Hide, Lock, Unlock, Opacity…, Blend…,
  Reset) · **Content** (Flip H, Flip V, Rotate…, Invert, Clear) · **Across frames** (Copy to
  frames…, the same-named family) · **Name** (Rename…) · **Move group** (Use as Move group).
- **Selection helpers** in the app bar's overflow, as on Frames; the by-property helpers as chips
  in a "Select" sheet.
- **Desktop:** Shift-click range, Ctrl-click toggle, Ctrl+A, Esc clears (pops when empty),
  Delete arms (ADR 0022), **↑ ↓ shift the selection**, Ctrl+Z / Ctrl+Y, Enter = Make active when
  exactly one row is selected. Same selection model as touch.
- **Entry points:** the layer sheet's top button **"Layers…"** (the frame sheet's "Frames…"
  precedent) · ☰ → Layers… · keyboard Command `page.layers`, proposed **Shift+Y** (Y opens the
  layer sheet; T / Shift+T set the pairing precedent). Not a strip button (the strip has no width
  to spare — the ⊞ lesson).
- **Undo / redo inside the page**, app-bar buttons + keys; the selection survives by id.
- **Status line** (fixed 22 px) between the list and the bar for refusals and reports ("3 layers
  pinned at 255"), never a SnackBar (the Frames rule).
- Playback pauses on entry; pushing the page is not a context change; a batch verb is.

## The model (sketch)

**Layer set.** One DSL argument with the frame set's grammar (`LAYERSET := ITEM (' ' ITEM)*`,
`ITEM := N | N-M`), **0-based bottom-first on the wire** like every existing layer verb, canonical
form emitted by the shell, a parse error when empty, a refusal at execution when an index is at or
beyond the frame's layer count. The UI's numbering direction is open (**question 1**).

**Verbs** (all on the active frame, all inside one `edit_frame` or `edit_doc`, one record):

```
RemoveLayers(S)                          refuse: S covers every layer (or blank replacement, q2)
DuplicateLayers(S)                       copies above their sources; refuse: n+|S| > 128
MergeLayers(S)                           contiguous runs only; refuse: gap, locked member (q3)
ShiftLayers(S, delta)                    rigid; clamped; 0 → no-op, no record
ReverseLayers(S)                         |S| < 2 → no-op
InsertBlankLayers(S, above|below)        refuse: cap
SetLayersVisible(S, 0|1)  SetLayersLocked(S, 0|1)
SetLayersOpacity(S, 0..255)  SetLayersBlend(S, Mode)
RenameLayers(S, pattern)                 trailing free text; {n} {i} {name} tokens
ResetLayers(S)                           255 · Normal · visible · unlocked
FlipLayersH(S)  FlipLayersV(S)  RotateLayers(S, quarters)  InvertLayers(S)  ClearLayers(S)
CopyLayersToFrames(S, F)                 strict; refuse: any target past 128
SetActiveLayers(S)                       exists — the Move-group bridge
```

**Rules copied from Frames:** the active layer changes only when its layer is removed or merged
away (then the layer now at the same index, clamped — today's single `RemoveLayer` rule; a merge
run's survivor keeps the bottom member's id, so an active layer inside the run moves to the
survivor); the selection is a set of **layer ids**, transient, discarded on close; the marquee is
never touched; content batches are billed by the tiles they retain (already the case for
`DocStructure`) and warned about, never refused on memory grounds; refusals ride
`refusal_seq` / `last_refusal`; the Move group is cleared whenever the active frame's stack changed
(the single verbs' rule) — except by "Use as Move group", which sets it.

**Locks.** Today a locked layer refuses pixel edits and `MergeDown` refuses when the layer *below*
is locked. A batch content verb over a set with locked members can refuse ("3 selected layers are
locked — unlock them first", all-or-nothing, the Frames doctrine) or skip them with a report; the
property verbs (visibility, opacity, blend, rename) ignore the lock because the lock guards
pixels, and reorder ignores it as the single Move up/down do. **Question 3.**

**Thumbnails.** `mkpx_layer_thumb` renders one layer; the page needs it point-sampled like the
frame thumb (ADR 0031's sampler works per layer trivially) and an id-keyed LRU sized for the page.
The strip's index-keyed cache self-heals through the memoized layer hash on return.

## Out of scope for v1 (proposed follow-ups)

Drag-to-reorder · a layer × frame matrix view · "also on all frames" on every batch · groups and
folders, linked layers, alpha lock, clipping masks, solo/isolate (new document semantics; gaps
inventory D1, D2, A3, B12) · gather move · move layers to another frame (B24) · relative opacity ·
per-set tool-page operations (trim, palettize, outline) · a persistent selection · a resizable
in-editor panel for wide viewports.

## Effort (rough, if the A tier plus the cheap B rows ship)

| Piece | Estimate |
|---|---|
| Layer-set argument (shared parser with the frame set) + ~14 verbs + tests + `assert.undo` scripts | 2 days |
| Point-sampled layer thumbnails + id-keyed cache | ½ day |
| Selection model (reuse `FrameSelection` generically) + page + rows + action bar + helpers + desktop | 3 days |
| Verb-list wiring, replay classifier, layer-sheet button, menu item, Command, docs, ADR | ½ day |
| Windows mouse pass + Pixel pass (a 128-layer 512² frame) | 1 day |

## Questions for the design interview

1. **Numbering.** The list shows the top of the stack first, but the layer sheet says "Layer N of
   M" counting from the bottom and the wire is bottom-first. Range entry and the row number: count
   from the bottom (consistent with the sheet) or from the top (consistent with the list)?
2. **Delete covering every layer.** Refuse (the single Delete's rule), or replace the stack with
   one blank layer (the `RemoveLayersNamed` rule)?
3. **Locked members in content batches and Merge.** Refuse the batch, or skip them and report?
4. **Badge taps.** Do the eye and lock badges act on the single row immediately, or is every tap
   a selection tap (badges display-only)?
5. **Merge preview.** Should the Merge row show what the run will produce before the tap (a
   composite thumbnail), or is the refusal-and-undo path enough?
6. **Rename pattern.** Tokens `{n}` `{i}` `{name}` as proposed, or just "one name for all" in v1?
7. **Selection-helper arithmetic.** By-property helpers replace, add to, or subtract from the
   current selection (a 3-way chip), or always replace?
8. **Copy to frames.** Should the page's "Copy to frames…" replace the layer sheet's "Copy to all
   frames" (which keeps the lenient skip-full-frames verb)?
