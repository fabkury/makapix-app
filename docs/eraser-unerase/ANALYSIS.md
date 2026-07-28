# Eraser "keep RGB" + Un-erase toggle — feasibility analysis

**Status: analyzed, NOT committed.** No implementation exists or is scheduled; this document
records the proposal, the decisions taken during analysis, and the pros/cons/costs/risks so the
work can be picked up (or declined) later without redoing the investigation. Analyzed 2026-07-28
against the code as of commit `446db12`; the `file:line` references below are from that revision.

## The proposal

1. The Eraser never touches RGB values — it only sets alpha to 0, leaving RGB in place.
2. The Eraser gains a row-1 toggle, **"Un-erase"**, default OFF.
3. With Un-erase ON, the Eraser sets alpha to 255 instead of 0, visually "un-erasing" pixels
   (revealing whatever RGB was left behind by an earlier erase).

## Decisions taken during analysis (user-confirmed)

| Question | Decision |
|---|---|
| Scope of "never touch RGB" | **All erase paths** (Eraser, Cut, Clear/Delete selection, Move lift, `clear_region`), not just the Eraser tool |
| Persistence | Hidden RGB **must survive save/load** (`.mkpx`) — a durable document property |
| Un-erase on a pixel with no hidden color | **Always set a=255** (literal spec: empty pixels become opaque black) |
| Alpha target of Un-erase | **Always 255** (original partial alpha is not remembered; not a true inverse of erase) |

## Why it's cheaper than it sounds

Two things are already true in the engine:

1. **Pixels are stored as straight RGBA, not premultiplied** (`crates/engine/src/buffer.rs:3` —
   "losslessness-first; compositing premultiplies transiently"). A tile can physically hold
   `(R,G,B,0)` today.
2. **The `.mkpx` codec already preserves it.** Save writes every present tile's raw bytes verbatim
   (`crates/engine/src/io.rs:543-548`), and the one function that canonicalizes all-`a=0` tiles
   back to absent — `RgbaBuffer::compact()` (`buffer.rs:239`) — is called only from a test, never
   in production. "Must survive save/load" therefore costs almost zero codec work. Hidden RGB
   under `a=0` can *already* be created today (Pencil in Replace mode with a transparent primary
   color writes `(R,G,B,0)` into an existing tile) and already round-trips through save.

The real work is in the tool layer, the UI toggle, and the second-order effects below.

## Pros

- **Erase becomes non-destructive.** Un-erase is effectively a "recover brush": content comes back
  within the session, after undo history is exhausted, and even after save/reload.
- **Matches the engine's philosophy.** Straight-RGBA storage exists precisely for losslessness;
  erasing to `(0,0,0,0)` is the one remaining place that deliberately destroys channel data.
- **Zero rendering cost.** Compositing skips `src.a == 0` (`buffer.rs:209`), so hidden RGB is
  invisible for free. Display, thumbnails, and PNG/GIF export all go through compositing, so
  exported *images* neither change nor leak.
- **Enables alpha-as-a-channel workflows** — stenciling, cutting a silhouette out of a painted
  sheet and re-revealing parts. Un-erase with a shaped brush is a poor man's layer mask.
- **Mechanically small and centralized.** `PaintMode::Erase` resolves in exactly one `match` arm
  (`crates/engine/src/tool.rs:256`); erase-like paths (`clear_region` at `tool.rs:583`, Cut, Move
  lift) funnel through `plot`/`set`. A new `PaintMode::Unerase` plus a `SetEraserUnerase(bool)`
  DSL verb follows the `SetSelectColorSource` precedent; the row-1 chip has existing patterns
  (Fill/Outline, Select mode).

## Cons

- **Two invisible kinds of "transparent."** `(0,0,0,0)` and `(R,G,B,0)` render identically but
  behave differently under Un-erase, Bucket, Select-by-Color, hashing, and file size. Invisible
  state that changes behavior is a support/confusion generator.
- **Un-erase is not the inverse of erase** (accepted decisions): a 40%-alpha pixel erased and
  un-erased comes back at 100%, and un-erasing virgin canvas paints opaque black. With the toggle
  ON, the Eraser is functionally a black Pencil on empty areas. Both will be reported as bugs by
  some users.
- **A sticky mode on a destructive tool.** Eraser left in Un-erase mode and forgotten paints
  opaque pixels instead of erasing. Row-1 visibility helps; it's still a foot-gun.
- **Weakens "hash equality = visual equality."** `content_hash` covers all four channels of
  present tiles (`buffer.rs:253-269`) and the doc hash goes into the file HEAD (`io.rs:535`). Two
  visually identical documents with different erase histories now hash differently; `hash:F:L`
  CLI probes and goldens built on "erase restores the hash" (e.g. the test at `buffer.rs:586-590`)
  change meaning.

## Costs

- **Engine:** small. One new `PaintMode` variant; the Erase arm becomes read-modify-write (`get`
  then `set` with RGB kept, alpha forced); a settings flag; a parse verb. The `set()` sparsity
  guard (`buffer.rs:196-199` — writing `a=0` into an absent tile is a no-op) keeps working
  unchanged for keep-RGB erase.
- **Bucket/Select special-casing (the one real algorithmic cost):** flood fill and Select-by-Color
  match with `max_channel_delta` over all four channels (`tool.rs:345,357`). Today every erased
  pixel is `(0,0,0,0)`, so transparent regions are uniform; afterward a Bucket fill on "empty"
  background at low threshold would stop at invisible hidden-RGB boundaries. The rule *"two
  pixels with `a==0` match regardless of RGB"* is almost certainly required in the match
  predicate — small change, but a documented semantic change to two tools with its own tests.
  (Select-by-Color's default Frame-composited source is unaffected; the Layer source and
  single-layer Bucket are the exposed paths.)
- **Test/golden churn — the largest single line item.** Every test asserting an erased pixel
  equals `Rgba8::TRANSPARENT`, plus scenario goldens and roundtrip expectations, needs review.
  Budget more time for this than for the feature itself.
- **UI/Dart:** a row-1 chip, tool-options state, optional persistence of the toggle — routine.
- **Docs:** `docs/mkpx-format/` must state that RGB under `a=0` is *significant, preserved data*.
  No format version bump (the bytes already carry it), but the semantic guarantee constrains every
  future writer and must be written down.
- **File size:** erased-but-painted tiles no longer collapse to the single all-zero dictionary
  entry (content-based dedup at `io.rs:476-519`), and RLE/INDEXED compress varied bytes worse.
  Moderate for typical pixel art; a heavily painted-then-erased document grows.

## Risks

- **Privacy/content leak — the hardest flag.** Composited exports (PNG/GIF) are safe, but `.mkpx`
  files now durably contain everything the user ever erased. The Club "layers file attachment"
  feature uploads the `.mkpx` verbatim, publicly downloadable: a user who erases something
  sensitive and publishes has silently shipped it. If this proceeds, consider a "flatten
  transparency" scrub step in the publish/attachment path — itself a small extra feature.
- **Forward-compatibility lock-in.** Once users rely on hidden RGB surviving, `compact()`-style
  sparsity maintenance and any future "normalize transparent pixels" memory or file-size
  optimization becomes a data-loss bug. Undo/dictionary dedup gets strictly worse, never better —
  a class of optimizations the memlab work might someday want is permanently given up.
- **Audit surface for "who else reads RGB at a=0".** Known-safe: compositing, export,
  painting-over (`over()` weights dst RGB by dst alpha). Needs a pass before implementing:
  - **cleanEdge** (color-similarity based) — hidden RGB near sprite edges could perturb
    Rotate/Resize output and fork those goldens;
  - **importers** (`crates/codec`);
  - **Eyedropper** — would pick `(R,G,B,0)` instead of `(0,0,0,0)`; probably fine, mildly
    surprising;
  - **`from_premul`** (`crates/engine/src/color.rs:88`) returns `TRANSPARENT` for `a=0` — any
    path that bounces pixels through premul and back silently strips hidden RGB, creating
    inconsistency between code paths.
- **Move-tool ghosts.** With "all erase paths keep RGB," Move's lift leaves the moved content's
  RGB behind at the source; Un-erase there resurrects a copy of what was moved away. Coherent
  under the model, surprising in practice.
- **Accepted UX risks** (opaque black on empty, 255-alpha flattening, sticky toggle) — the
  likeliest sources of "eraser is broken" reports.

## Bottom line

Mechanically cheap (storage and format already cooperate; a small feature plus a large test-churn
tax), genuinely novel as a capability, and rendering-safe. Three items should drive the go/no-go:

1. the **`.mkpx` privacy leak on Club attachments** (needs a mitigation, not just acceptance);
2. the **Bucket/Select `a==0` matching rule** (must be specced and implemented alongside, or the
   feature visibly breaks other tools);
3. the **permanent format-semantics commitment** that erased data is preserved data.

If those three are consciously accepted, the rest is routine.
