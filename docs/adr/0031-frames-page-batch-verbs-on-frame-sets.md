# The Frames page acts on frame sets through atomic batch verbs

**Proposed 2026-09-10 — DRAFT, not implemented.** Decided in a design interview (every choice is
the user's; the design and its edge-case policy live in `docs/frames-page/DESIGN.md`). To be
marked *Decided and implemented* with the engine/shell pointers when the work lands.

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
generalized refusal field beside the memory-specific ones in the state JSON (assumption: the
alternative changes `exec`'s signature), and additions to the shell's context-change and
frame-structure verb lists and to the replay classifier's event-tick set so a 300-frame delete is
one beat. The journal epoch stays at 3: these are new verbs with self-contained semantics, not
changed semantics of existing ones. One accounting hole surfaced by this design and provisionally
decided in `DESIGN.md`: a content batch's `DocStructure` record retains the old tiles of every
changed layer while history bills it by layer count and the document census walks only live
frames, so content-batch records must be billed by the unique payload they retain, and a content
batch is refused when that payload exceeds the document budget headroom. `Frame set` and `Frames
page` join CONTEXT.md; STATUS.md gains a row; the transient peak of a content batch joins the next
memlab device pass.
