# The Frames page — design

**Decided 2026-09-10** in a design interview (every decision below is the user's; assumptions are
marked). **Implemented 2026-09-11** (see "As built"). Doctrine: ADR 0031. Motivation: the film
roll is the only way to manipulate animation frames, and it is a one-frame-at-a-time control —
"delete frames 12 to 32" or "shift frames 20–28 right by 2" is twenty-one taps, or impossible.

## As built (deviations from the decisions below, each asked and approved on 2026-09-10/11)

- **Content batches are never refused on memory grounds.** The provisional policy (refuse when the
  retained payload exceeds the document headroom) was replaced by: bill every `DocStructure`
  record by the tables and tiles its before-side pins beyond the live document
  (`history::frames_delta_bytes`, the checkpoint store's census, now shared), let the 96 MiB
  history budget evict, and **warn unobtrusively** — a fixed 20 px amber slot in the More sheet's
  Transform section reads "Undo will hold about N MB" above 64 MiB. Nothing blocks.
- **Move group: the narrow rule.** Cleared only when the active frame's id changed (`RemoveFrames`
  removed it) or the active frame's active-layer id changed (`RemoveLayersNamed` removed it) —
  what the shipped single verbs do. Copy/show/hide/lock across frames leave it alone.
- **The mask is never touched**, including by a batch flip or rotation whose set contains the
  active frame (the single `FlipFrame` mirrors it, `RotateFrame` clears it). One rule; a marquee
  over a flipped active frame may sit misaligned until reselected.
- **Double-tap is detected by hand** (a second tap on the same tile within the double-tap window)
  so the first tap toggles instantly; `onDoubleTap` would delay every tap ~300 ms.
- **Refusals and reports use the fixed 22 px status line** between the grid and the action bar,
  not a SnackBar (a SnackBar would cover the bar for 4 s and double the editor's own memory-gate
  snackbar, which still surfaces on this page — accepted).
- **The refusal channel** is `refusal_seq` / `last_refusal` in `state_json` (memory refusals bump
  it too); `exec` keeps its signature. `NewDocument` resets it like `mem_refusals`.
- **Frame-set parse errors** (empty set, reversed range, an index at or beyond the 1024 cap) are
  script errors like any bad argument; an in-cap index beyond the roll is a refusal at execution.
- **Undo inside the page takes the editor's tile path** (ADR 0017): a pending Move draft is
  discarded first, exactly as the editor's own Undo tile does.
- **Grid density lives in the page's overflow menu** ("Bigger tiles" / "Smaller tiles") and in a
  two-finger pinch; persisted editor-wide (`editor.framesColumns_v1`).
- **Undo/redo inside the page re-validate only the visible tiles** through the (now memoized)
  frame hash; the single-frame sheet opened from a tile does the same on return.
- **The rotate note** ("Not square: a rotated overhang parks in the gutter") is a second fixed
  slot in the Transform section, shown only for a non-square canvas.

The page's name is **Frames** (UI label "Frames", menu item "Frames…", code `FramesPage`). The
codename "Timeline" was retired before design: CONTEXT.md gives the Animator pillar a timeline of
tracks and keys, ADR 0029 made the replay index "a Replay timeline", and the film roll's part file
is already `editor_page.timeline.dart`. "Contact sheet" (the photographer's grid of every frame on
a roll) is a fine name for the grid *widget* in code, nothing more.

## What it is

A full-screen page, pushed over the editor like the palette, crop, and artwork-colors pages, that
shows **every frame of the animation as a grid** and lets the artist **select any set of frames**
— contiguous, discontiguous, or both — and **apply one operation to the whole set at once**:
delete, duplicate, repeat, insert holds, shift, reverse, retime, flip, rotate, invert, and copy /
remove / show / hide / lock / unlock a layer across frames.

Every batch is **one engine verb, one undo step, all-or-nothing.** The engine gains a first-class
**frame set** argument and a family of batch verbs; the shell gains the page, an id-keyed selection
model, and two engine prerequisites (point-sampled thumbnails, a cached frame hash) without which a
grid of 40–100 tiles cannot be drawn at a usable rate on a 512² document.

Workflows the page exists for:

- **Survey** — see the whole animation at once, find a frame by its content, spot holds, holes, and
  duplicates, read the rhythm from the duration badges.
- **Jump** — reach a far frame in two taps instead of scrolling the strip or typing into Go to.
- **Restructure in bulk** — delete a range, duplicate a segment to extend a cycle, repeat a segment
  as a block, insert holds, reverse a segment, nudge a segment earlier or later.
- **Retime in bulk** — one duration or an fps preset on many frames, or scale a segment's timing.
- **Transform in bulk** — mirror a walk-cycle segment, rotate or invert a set of frames.
- **Layer housekeeping across frames** — copy the active layer into chosen frames; hide, show,
  lock, unlock, or remove a same-named layer across chosen frames.

## Decisions (2026-09-10)

### Model

| Question | Decision |
|---|---|
| Name | **Frames.** Page title "Frames · N", menu "Frames…", `FramesPage`, this folder. Not Timeline (three collisions), not Contact sheet (unfamiliar), not Frame sheet (collides with the bottom sheets) |
| Batch model | **Engine batch verbs**, each taking a **frame set**; **one undo step per batch**; **one journal line**; one replay tick |
| Failure policy | **Refuse the whole batch and explain.** Nothing changes; the reason is shown. The page pre-checks the frame cap, the layer cap, and "would delete every frame" and disables or annotates the control *before* the tap; the engine's refusal is the authority |
| Active target | **Changes only when its frame is removed** (ADR 0013 applied to sets): batches that create, duplicate, reorder, or retime frames never move it. When a delete removes it: **the first surviving frame at or after the old active index, else the last survivor** — identical to today's single-frame rule whenever the set is one frame |
| Selection identity | The page holds the selection as a **set of frame ids**, never indices, so it survives reorders, undo, and redo (restored frames keep their ids). **Discarded when the page closes** — a transient selection, like the Move group |
| Pixel-selection mask | Batch verbs **never touch the marquee**; content transforms are **whole-frame, every layer, mask ignored** — exactly the single-frame `FlipFrame*` / `RotateFrame` / `InvertFrame` semantics |
| Rigid shift | Discontiguous sets move **as a rigid body** (gaps kept, unselected frames flow around). The delta is **clamped to the room**; a clamp to zero is a **no-op with no undo record**. Gather-to-a-target is *out of scope* (see below) |
| Durations that clamp | **Apply and report:** the batch lands with the engine's 16.6–1000 ms clamp; a toast says "N frames pinned at 16.7 ms" (or 1000 ms). A scale still means a scale |
| Layer identity across frames | **Match by name**, exact and case-sensitive, **topmost hit per frame**; the sheet shows the hit count ("14 of 20 selected frames have a layer named Shading") before the tap. Frames without a hit are skipped by the verb (the artist saw the count) |
| A remove-by-name that empties a frame | **A blank layer replaces it** instead of blocking the batch: fresh id, the default new-layer name, visible, unlocked, opacity 255, Normal blend; it becomes that frame's active layer |
| Layer cap on copy-to-frames | **A new strict verb, `CopyLayerToFrames(S)`, refuses** when any target already holds 64 layers. The shipped `DuplicateLayerToFrames` (skips such targets) keeps parsing forever and stays behind the layer sheet's "Copy to all frames" |

### Operations (v1)

| Family | Operation | Semantics on the set S |
|---|---|---|
| Structural | **Delete** | Remove every member. Refused when S covers every frame. Tap-again confirm (ADR 0022) |
| | **Duplicate** | Each member's copy lands **right after its source** (3,5 → 3,3′,5,5′). Afterwards **the copies are the selection**, ready to be nudged or retimed |
| | **Repeat after** | Copies of S, in order, as **one contiguous block right after the last member**. Afterwards the block is the selection. "Loop this segment twice" in one tap |
| | **Insert blank before / after** | One blank frame per member, before or after it (a hold pattern). Default duration, one blank layer, like the strip's New frame |
| | **Shift ◀ ▶ by N** | Rigid, clamped; the nudge buttons hold-to-repeat and disable at the edge; "by N…" shows the clamped value before the tap |
| | **Reverse** | The members swap places among the selected slots: on a discontiguous set the slots stay, the occupants reverse |
| Duration | **Set…** | The existing duration dialog (field, slider, 60/30/24/12/8 fps chips) applied to S instead of "this frame / all frames" |
| | **Scale ×** | ×0.5 · ×2 chips and a free factor; integer math in µs, clamped, pinned count reported |
| Content | **Flip H / Flip V** | Batch twins of `FlipFrameH/V`: whole storage (canvas + gutter), every layer |
| | **Rotate 90 / 180 / 270** | Batch twin of `RotateFrame`: about the storage center, so on a non-square canvas the overhang **parks in the gutter** as today (recoverable with Move) |
| | **Invert** | Batch twin of `InvertFrame` |
| Layers | **Copy active layer to frames** | Strict verb; the copy is pushed on top of each target's stack (as the shipped verb does; assumption) |
| | **Remove layer named…** | Topmost hit per frame; blank-layer replacement when a frame would be emptied |
| | **Show / Hide / Lock / Unlock layer named…** | Topmost hit per frame |
| Navigation | **Go to** | Double-tap a tile (or the tile menu): `SetActiveFrame` + pop to the editor |

Not in v1 (asked and declined for now): ramp durations A→B, nudge ± ms, Clear frames, Same-duration
selection helper, playback tools (loop mode, total duration, play-range preview, onion range), the
gather move ("Move to…"), select-identical-frames, a persistent selection. See "Out of scope".

### Interaction

| Question | Decision |
|---|---|
| Tap | **Toggles selection.** The page exists for multi-select; no mode switch |
| Long-press | **Starts a range sweep**: every tile the finger crosses joins the selection; release without moving leaves just that tile selected; edge auto-scroll while sweeping |
| Double-tap | **Go to**: activates the frame and pops to the editor |
| Tile menu | A small **overflow on the tile** (touch) and **right-click** (desktop): Go to, Select to here (from the anchor), the single-frame sheet |
| Selection helpers | **All · None · Invert**, **Range entry** (1-based text `1-12, 20, 30-40`, normalized, rejected inline when out of range), **Every Nth** (N and an offset, within the current selection or the whole roll) |
| Desktop | **Shift-click** range from the anchor, **Ctrl-click** toggle, **rubber-band** on empty grid space, **Ctrl+A**, **Esc** clears (pops when already empty), **Delete/Backspace** arms (ADR 0022), **← →** nudge the selection, **Ctrl+Z / Ctrl+Y** undo/redo, **Enter** = Go to when exactly one frame is selected (assumption). Only input differs from touch; the selection model is one |
| Undo / redo inside the page | **Yes**: app-bar buttons + the keys. Selection survives by id; visible thumbnails re-validate after each undo/redo |
| Entry points | **⊞ button at the film roll's trailing end** (next to +, both orientations) · **☰ → Frames…** · **keyboard Command** `page.frames`, proposed **Shift+T** (T opens the frame sheet; O/Shift+O and P/Shift+P set the pairing precedent). Not the frame sheet's header |
| Grid density | 3–8 columns by **pinch or a stepper**; persisted editor-wide (assumption) |
| Tile | Thumbnail on the checker (artwork rect only, as the strip), 1-based number, duration badge, the active-frame marker in the strip's blue, a check overlay when selected |
| Action bar | **Fixed height**, bottom; enabled only with a non-empty selection: Delete · Duplicate · Duration · ◀ ▶ · More. Never reflows the grid (the import pages' no-reflow rule) |
| Drafts and playback | Playback pauses on entry. Pushing the page is **not a context change** (the palette-page precedent, ADR 0011): an open Draft survives the trip and dies only when a batch verb runs, because every batch verb is a context-change verb (assumption) |

## The model

### Frame set

A **frame set** is one DSL argument: whitespace-separated items, each a single index or an
inclusive range, **0-based on the wire** like every existing frame verb (the UI shows 1-based).

```
FRAMESET := ITEM (' ' ITEM)*
ITEM     := N | N-M            0 ≤ N ≤ M
```

The parser accepts any order and overlap and canonicalizes (sort, dedup, coalesce into maximal
ranges); the shell always emits the canonical form (`12-32 40`). An empty set is a parse error. An
index at or beyond the frame count makes the whole verb refuse at execution (never a silent clip).
Whitespace, not commas, separates items so the set stays one argument of the existing comma
splitter and free-text layer names can follow it (`RemoveLayersNamed(12-32 40, Shading, v2)` —
the name is everything after the first comma, as `RenameLayer` does after its index).

### Verbs

```
RemoveFrames(S)                         refuse: S covers every frame
DuplicateFrames(S)                      each copy right after its source; refuse: n+|S| > 1024
RepeatFramesAfter(S)                    block copy after max(S);            refuse: n+|S| > 1024
InsertBlankFrames(S, before|after)      one blank per member;               refuse: n+|S| > 1024
ShiftFrames(S, delta)                   rigid; clamped to the room; 0 → no-op, no record
ReverseFrames(S)                        |S| < 2 → no-op, no record
SetFrameDurations(S, ms)                clamped 16.6–1000 ms
ScaleFrameDurations(S, permille)        us' = (us·permille + 500) / 1000, clamped
FlipFramesH(S)  FlipFramesV(S)  RotateFrames(S, quarters)  InvertFrames(S)
CopyLayerToFrames(S)                    strict; refuse: any target at 64 layers
RemoveLayersNamed(S, name)              topmost hit; blank-layer replacement when emptied
SetLayersVisibleNamed(S, 0|1, name)
SetLayersLockedNamed(S, 0|1, name)
```

Every verb runs inside one `edit_doc` and therefore records **one `DocStructure` record**, is
subject to the existing post-mutation memory gate (rolled back wholesale over the hard budget),
and clears the Move group whenever the active frame or its layer stack changed (as the single verbs
do). None of them is Repeatable (ADR 0017); the nudge buttons repeat themselves.

**Rigid shift, precisely.** Let `k = clamp(delta, −min(S), (n−1) − max(S))`. Build a fresh
vector: each member `i` goes to slot `i + k` in ascending order; the unselected frames fill the
remaining slots in their old order. Targets are distinct and in range after the clamp, so the
result is total. The journal stores the *requested* delta; replay re-clamps identically because the
clamp is a pure function of the document.

**Refusal channel.** `exec` cannot return an error today: parse errors abort `run_script`, but a
verb that declines (frame cap, cross-budget import) reports through the state JSON's
`mem_refusals` / `mem_last_refusal` fields and the shell shows a snackbar. Batch refusals reuse that
channel, generalized: a sibling `last_refusal` (any verb's reason) beside the memory-specific
fields, bumped with `refusal_seq` so the shell can tell a new refusal from the last one
(assumption — the alternative, an `Err` from `exec`, changes the executor's signature for every
verb). A refused verb is still journaled verbatim (the recorder taps before run); replay refuses it
identically because every refusal is a pure function of the document.

### Engine prerequisites

- **Point-sampled thumbnails.** `frame_thumb_bytes` composites the whole frame and then samples;
  a 96×96 thumb of a 512² frame composites 262k pixels to use 9k. The new path composites only
  the sampled source pixels — the same integer compositor per pixel, so byte-identical output,
  ~28× less work at 512². Same FFI signature; the film roll speeds up too.
- **Cached frame hash.** `Frame::content_hash` walks every pixel of every layer on every call, and
  the roll calls it per visible tile per build. A per-layer memoized pixel hash, cleared by every
  mutation path (`snapshot`/`commit`, the direct writers, undo/redo restore), makes the hash O(1)
  after the first call. A missed invalidation means a stale thumbnail, so it ships with a fuzz-style
  test: after any random verb sequence the cached hash equals a recomputation.

## Shell

- **`app/lib/editor/frames/`** — `frames_page.dart` (the route), `frame_selection.dart` (a pure
  model: `Set<int> ids`, an anchor id for Shift ranges, `toIndices(frameDetail)`, `canonical()` →
  `"12-32 40"`, the helpers, the Every-Nth and Range-entry parsers — testable without the engine),
  `frame_grid.dart` (the contact-sheet widget), `frames_host.dart`.
- **Host, not engine.** Like `PalettePage`'s `EnginePaletteHost`, the page talks to a `FramesHost`
  the editor builds: `frameDetail`, `activeFrameId`, `run(dsl)` (routes through the editor's `_act`,
  so Drafts, playback pause, journal, autosave, and the active-frame reveal all apply), `undo()`,
  `redo()`, `thumb(id)`, and `lastRefusal`. The page pops with an optional Go-to index.
- **Thumbnails by id.** An LRU keyed by **frame id** sized for the page (≈300 entries ≈ 10 MB of
  96×96 images), generated **at most a few per frame callback, nearest the viewport first**, the
  flat gray placeholder meanwhile. No hashing per build: structural batches change no pixels
  (thumbs kept by id; new ids generate lazily), content batches invalidate S, undo/redo re-validate
  the *visible* tiles through the (now cached) hash.
- **State refresh.** After each batch the shell refreshes `frame_detail` as `_act` already does; at
  1024 frames that JSON is the per-batch cost to measure (it is a known hotspot), not the verb.
- **Verb lists.** The batch verbs join `_isContextChangeVerb` (Drafts die), `_isFrameStructureVerb`
  (the roll reveals the active frame on return), and the replay classifier's `_kAlwaysEvent`
  (`visible_index.dart`) so a 300-frame delete is one event beat, not an invisible tick.
- **Delete** uses `TapAgainDeleteButton` with `armKey = (selection signature, _sendSeq)`: any
  engine traffic or selection change disarms.
- **Exit reconciliation.** The roll's index-keyed cache self-heals through its hash check (cheap
  once cached); the layer group is cleared when the active frame changed.

## Edge-case policy (all decided; listed so nobody re-litigates them mid-implementation)

- **Cap and budget refusals are atomic.** Duplicate, Repeat, Insert pre-check `n + |S| ≤ 1024`
  before mutating; the memory gate rolls back wholesale. Duplicates share tiles copy-on-write, so
  the realistic refusal is the cap; the memory cost arrives when the artist paints on the copies.
- **Content batches and retained tiles** (surfaced during this design; provisional until the user
  confirms). A `DocStructure` record holds the *before* frames, so a flip over S retains S's old
  tiles until the record is evicted — but history bills `DocStructure` by layer *count*, and the
  document census walks only live frames, so neither budget sees them. One frame is harmless;
  500 frames of 512² is hundreds of MB against Android's ~1 GiB wall. Policy: **content batch
  records are billed by the unique payload of the layers they changed** (so the 96 MiB history
  budget evicts them properly), and **a content batch is refused when that payload exceeds the
  document budget headroom** (the transient peak is old + new tiles). The page shows the estimate
  amber before the tap, as the Place page does.
- **Active target after a delete that includes it:** first survivor at or after the old index,
  else last. Deterministic, journal-replayable.
- **Remove-by-name on the active frame's active layer:** the frame's active layer follows identity
  where it survives; when it was the removed one, the layer now at the same index (clamped), or the
  replacement blank — the single `RemoveLayer` rule.
- **Copy-to-frames when the active frame is in S:** the active frame gets a copy of its own layer
  pushed on top, as the shipped verb does; the artist selected it.
- **Duration clamping** reports the pinned count, never refuses. Scale on a one-member set is
  fine; Reverse and Shift on a one-member set are no-ops without a record.
- **Rotate on a non-square canvas** parks the overhang in the gutter (the storage rotates about its
  center). The More menu notes it when the canvas is not square.
- **Batch rotation must be byte-identical** to `RotateFrame` on the same frame (quarter turns are
  exact permutations): the frame-scoped rotation is factored into one pure function both paths
  call, pinned by a hash test.
- **Gestures.** Long-press means sweep, never menu, or the two fight; the tile menu lives on the
  tile's overflow and on right-click. Sweeping past the viewport auto-scrolls; long ranges are what
  Range entry is for.
- **Refused batch:** nothing changed, the selection stays. **Successful Duplicate / Repeat:** the
  selection becomes the copies, found by id in the refreshed state (the copy of the member ranked
  `r` in S sits at old index `+ r + 1` for Duplicate; the block follows `max(S)` for Repeat).
- **Undo inside the page:** restored frames keep their ids, so the id-keyed selection survives;
  members that no longer exist drop out silently.
- **1-based UI, 0-based wire.** Range entry parses 1-based and converts once; the journal shows
  0-based like every other frame verb. Reversed ranges in the entry are swapped, not rejected.
- **Journal epoch stays 3.** These are new verbs with self-contained semantics; the epoch marks
  changed semantics of existing verbs. An older build replaying a journal that contains them fails
  at that line, as it would for any verb added after it (Crop canvas, Symmetry).
- **Layer names with commas** survive: the name is the trailing free text after the fixed
  arguments, and the frame set has no commas by construction.
- **History budget on huge documents.** A structural record on a 1024-frame document costs on the
  order of a megabyte of metadata; ninety-odd batches would start evicting the oldest records under
  the 96 MiB budget. Known, not designed around.

## Out of scope for v1 (documented follow-ups)

- **Gather move ("Move to…")** — collect a discontiguous selection into one block at a target.
  Declined: rigid shift only.
- **Ramp durations A→B** and **nudge ± ms** — declined for v1; the verbs are one line each when
  wanted.
- **Clear frames** — no single-frame twin exists; declined for v1.
- **Same-duration** and **select-identical** helpers — the latter needs the cached hash first (a
  one-off scan of a large document blocks the UI thread for about a second without it).
- **Playback tools on the page** (loop mode, total loop duration, play-range preview, onion
  range) — declined; the total-duration readout is a candidate passive stat later.
- **Persistent selection across visits** — declined; transient like the Move group.
- **A resizable in-editor panel** for wide viewports (≥1000 px) instead of a route — later.
- **Migrating the layer sheet's "Copy to all frames"** to the strict verb — not needed; the old
  verb keeps parsing forever.

## Effort (rough)

| Piece | Estimate |
|---|---|
| Frame-set parser + 16 verbs + unit tests + CLI `assert.undo` scripts | 2 days |
| Point-sampled thumbnails + cached frame hash + tests | 1 day |
| Selection model + page + grid + action bar + helpers + desktop input | 3–4 days |
| Verb-list wiring, replay classifier, roll button, menu item, Command, docs | ½ day |
| Windows mouse pass + Android device pass (1024-frame 512² document on the Pixel) | 1–2 days |

## Documentation

- ADR 0031 (draft, this folder's doctrine) — accepted when implementation starts.
- CONTEXT.md: **Frame set** (a set of frames named by index on the wire and by id in the shell) and
  **Frames page**; note that the page's selection is transient like the Move group.
- STATUS.md: a "Frames page" row; the "Duplicate / reorder animation frame" row points at it.
- `docs/memlab/REPORT.md`: the content-batch transient peak joins the next device pass.
