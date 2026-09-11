# The Frames page acts on frame sets through atomic batch verbs

**Decided 2026-09-10 in a design interview, implemented 2026-09-11** (every choice is the
user's; the design, its edge-case policy, and the as-built deviations live in
`docs/frames-page/DESIGN.md`). Engine: `crates/engine/src/session/frames.rs` (`FrameSet` + the
sixteen verbs), the `Action` variants and parser arms in `session/parse.rs`, the generic
refusal channel (`Session::refuse`, `refusal_seq` / `last_refusal` in `state_json`), the
retained-bytes billing of `DocStructure` records (`history::frames_delta_bytes`), the
`flip_storage` / `frame_rotate_draft` / `apply_rotation_to_frame` extractions in
`session/canvas.rs`, `render::FrameSampler` and the memoized `RgbaBuffer::content_hash`.
Shell: `app/lib/editor/frames/` (the page, the id-keyed selection, the frame-set helpers, the
grid geometry, the LRU), `editor_page.frames.dart` (the host and the route), the ⊞ roll button,
☰ → Frames…, the `page.frames` Command on Shift+T, the batch verbs in the context-change and
frame-structure lists and in the replay classifier's event set.

The film roll is the Editor's only frame control, and it is a one-frame-at-a-time control: tap to
activate, long-press for a sheet whose Move / Duplicate / Delete / Duration act on that frame.
Anything the artist wants done to twenty frames — delete a range, shift a segment by two, retime a
cycle, mirror a walk — is twenty round trips through the sheet, or impossible. The engine mirrors
the limitation: every frame verb is single-frame and index-addressed (`RemoveFrame(i)`,
`ReorderFrame(from, to)`, `SetFrameDuration(i, ms)`), and the one cross-frame verb,
`DuplicateLayerToFrames`, takes a flat index list and applies partially.

Four commitments:

- **A frame set is a first-class DSL argument.** One argument, whitespace-separated items, each an
  index or an inclusive range, 0-based on the wire (`12-32 40`); the parser canonicalizes any order
  or overlap, an empty set is a parse error, and an index beyond the frame count refuses the whole
  verb at execution. Whitespace rather than commas keeps the set one argument of the existing comma
  splitter, so free-text layer names may still trail it as `RenameLayer`'s name does.

- **A batch is one verb, one undo record, all-or-nothing.** `RemoveFrames`, `DuplicateFrames`,
  `RepeatFramesAfter`, `InsertBlankFrames`, `ShiftFrames`, `ReverseFrames`, `SetFrameDurations`,
  `ScaleFrameDurations`, `FlipFramesH/V`, `RotateFrames`, `InvertFrames`, `CopyLayerToFrames`,
  `RemoveLayersNamed`, `SetLayersVisibleNamed`, `SetLayersLockedNamed` each run inside one
  `edit_doc` and record one `DocStructure` record. A batch that cannot fully apply — the 1024-frame
  cap, the 64-layer cap, a delete that would empty the roll, the document memory budget — **changes
  nothing and reports why**; there is no "apply what fits". The shell pre-checks the caps and
  disables the control, but the engine's refusal is the authority and replays identically because
  every refusal is a pure function of the document. Exceptions by decision: a rigid shift **clamps**
  its delta to the room (zero → no-op, no record), a duration scale **clamps and reports** the
  pinned count, and a remove-by-name that would leave a frame empty **substitutes a blank layer**
  rather than refusing.

- **The active target survives a batch by identity** (ADR 0013 applied to sets). No batch that
  creates, duplicates, reorders, or retimes frames moves it; a batch delete that removes it lands
  on the first surviving frame at or after the old active index, else the last survivor — the
  single-frame rule whenever the set is one frame. Batch verbs never touch the pixel-selection
  mask; content batches are whole-frame, every layer, the storage rotating about its center as
  the single-frame twins do. None is Repeatable (ADR 0017).

- **The shell holds the page's selection by frame id, transiently.** Ids survive reorders and
  undo/redo (restored frames keep theirs); the selection is discarded when the page closes, like
  the Move group. After Duplicate or Repeat the selection becomes the copies. The page is a route
  over the editor that talks to a host (the palette-page pattern), routes every verb through the
  editor's `_act`, offers undo/redo in place, and never hashes per build: thumbnails are keyed by
  id and invalidated by the page's own knowledge of what changed.

Two engine prerequisites ride the decision because a 40–100-tile grid is unusable without them:
**point-sampled thumbnails** (composite only the sampled source pixels; byte-identical output,
~28× less work at 512²) and a **cached per-layer content hash** cleared by every mutation path,
guarded by a fuzz-style test that the cached value always equals a recomputation.

Alternatives rejected:

- **Shell loops over the existing single-frame verbs** (no engine change): a 20-frame delete
  becomes 20 undo steps and 20 journal lines, the order of application is the shell's problem, and
  a batch can stop half-way at the cap or the budget — partial results are exactly what the page is
  meant to make impossible.
- **A generic transaction verb** (`BeginBatch` / `EndBatch` coalescing any verbs into one record):
  most general, but it adds nesting and abort rules to history, a new tick class to replay pacing,
  and still leaves each inner verb index-addressed and partially applicable.
- **Apply what fits and report the remainder**: one undo step, but the document no longer matches
  the request; rejected in favor of atomic refusal with a pre-check.
- **Gather-to-a-target moves** ("Move to…", collecting a discontiguous set into one block): rigid
  shift only for v1; recorded as a follow-up in the design.
- **Fixing the shipped `DuplicateLayerToFrames`** to refuse: it is a journaled verb with shipped
  skip semantics, so it keeps parsing forever and a strict twin, `CopyLayerToFrames`, carries the
  page's doctrine.
- **Naming the page "Timeline"**: the word already names the Animator's track timeline, the Replay
  timeline (ADR 0029), and the film roll's part file. The page is **Frames**.

Consequences: sixteen new verbs and a frame-set parser in `crates/engine/src/session/parse.rs`, a
generalized refusal field beside the memory-specific ones in the state JSON (`exec` keeps its
signature; memory refusals bump the generic counter too), and additions to the shell's
context-change and frame-structure verb lists and to the replay classifier's event-tick set so a
300-frame delete is one beat. The journal epoch stays at 3: these are new verbs with
self-contained semantics, not changed semantics of existing ones. One accounting hole surfaced by
this design: a content batch's `DocStructure` record retains the old tiles of every changed layer
while history billed it by layer count and the document census walks only live frames. **Decided
2026-09-10: every `DocStructure` record is billed by the tables and tiles its before-side pins
beyond the live document** (the checkpoint store's census, now shared), so the 96 MiB history
budget evicts such records properly — and the batch is **never refused** on that account; the
More sheet shows an unobtrusive "Undo will hold about N MB" note above 64 MiB instead. The
transient peak (old tiles in the record + new tiles live) stays invisible to the document gate and
joins the next memlab device pass. `Frame set` and `Frames page` join CONTEXT.md; STATUS.md gains
a row.

Refinements decided during implementation (2026-09-10/11): the Move group clears only when the
active frame's id or its active layer's id changed (the shipped single verbs' rule, narrower than
the design's sentence); the pixel-selection mask is never touched, even by a batch flip or
rotation whose set contains the active frame (the single twins mirror or clear it — one rule beats
two special cases); a memory-gate refusal is reported twice, by the editor's snackbar and by the
page's status line (accepted); `NewDocument` resets `refusal_seq` like `mem_refusals`.
