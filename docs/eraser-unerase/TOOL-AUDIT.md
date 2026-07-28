# Eraser Un-erase — pixel-reader audit (pressure test)

**Status: audit of a NOT-committed proposal.** Companion to [`ANALYSIS.md`](ANALYSIS.md), which
holds the feature description, the confirmed semantics decisions, and the overall
pros/cons/costs/risks. This document pressure-tests the claim "other tools keep working" by
walking every code path that *reads* pixel values and asking how it behaves once transparent
pixels may carry hidden RGB (`(R,G,B,0)` instead of always `(0,0,0,0)`). Audited 2026-07-28
against commit `df6f086` (same code as `446db12` for the engine); write-only tools (Pencil,
Brush, Line/Rectangle/Ellipse/Triangle, geometric selects) are exempt by construction.

Baseline: the **literal spec** (no mitigations); each finding proposes its minimal fix.

## Headline results

1. **cleanEdge is already safe — the mitigation the feature needs already exists there as
   precedent.** `similar()` explicitly treats any two `a==0` pixels as one color "regardless of
   its stored RGB" (`crates/engine/src/cleanedge.rs:79-84`, ported from the shader's
   `col1.a == 0 && col2.a == 0` clause). The previously flagged cleanEdge risk is retired.
2. **Bucket and Select-by-Color break as predicted** and need the same rule cleanEdge already
   has. The cleanest formulation, which *exactly preserves current behavior*: **for comparison
   purposes, a pixel with `a==0` is canonicalized to `(0,0,0,0)`** (see "The canonicalization
   rule" below).
3. **New leak finding: the raw layer exports bypass compositing.** `layer_rgba_bytes`
   (`session.rs:500`) feeds `mkpx_export_layer_png` / the lossless-WebP twin
   (`app/lib/engine_ffi.dart:328,348`) with the layer's raw stored pixels. Hidden RGB would be
   embedded byte-for-byte in exported layer PNGs/WebPs — a second leak path besides the `.mkpx`
   Club attachment. Frame/animation exports composite and stay clean.
4. **Systemic finding: hidden RGB survives only *in place*.** Roughly a dozen bulk operations
   skip `a != 0` source pixels as a sparsity optimization, so any *relocation* — move, nudge,
   paste, flip, rotate, merge, import — silently strips hidden RGB. "Must survive save/load" is
   achievable, but "survives editing" is not, without touching all of those sites. This
   changes the feature's reliability story more than any single tool does.

## Tool-by-tool findings

### Bucket (flood fill) — BREAKS, needs the canonicalization rule

`flood_fill` matches candidate pixels against the seed with `max_channel_delta` over all four
straight channels (`crates/engine/src/tool.rs:345,357`). Today every erased/empty pixel is
`(0,0,0,0)`, so transparent regions are uniform and a fill of "empty background" sweeps through.
With hidden RGB, an erased-red pixel vs. a never-painted pixel differ by up to 255 in a channel:
the fill stops at invisible boundaries. Exposure: filling the active layer directly, contiguous
or not. The "All layers" mode is *safe* — its reference is the composited frame
(`session.rs:1965-1968`), and compositing (`blend_over` skips `src.a == 0`, `buffer.rs:209`)
never lets hidden RGB through.

### Select-by-Color — BREAKS in Layer-source mode, same fix

`Mask::from_color` uses the same `max_channel_delta` matching
(`crates/engine/src/selection.rs:258`). The default **Frame** source composites first
(`session.rs:1933-1939`) and is safe; the **Layer** source clones the raw layer buffer and would
fragment exactly like Bucket. Additional subtlety: tapping an erased pixel as the *seed* makes
the target `(R,G,B,0)` instead of `(0,0,0,0)`, changing which faint-alpha pixels fall within
threshold even outside transparent regions. The canonicalization rule fixes both.

### Eyedropper — SAFE

Both pick paths no-op on transparent pixels: `eyedrop_cursor` requires `c.a != 0` before
adopting the color (`session.rs:1922-1927`), for the Layer source as well as the composited
Frame source. Hidden RGB can never be picked. Corollary worth noting: **no tool can reveal or
inspect hidden RGB** — users confused about what Un-erase will resurrect have no way to look.

### Dodge / Burn — SAFE (with a semantics footnote)

The stamp reads each pixel and applies the HSV value-shift only `if c.a != 0`
(`tool.rs:507-510`). Hidden RGB is neither read into results nor modified. Footnote: because
adjustments skip erased pixels, hidden RGB is *stale* — erase, then dodge the area, then
Un-erase resurrects the pre-dodge color. Consistent with "hidden RGB = last visible color
before erase," but worth stating in the feature's spec.

### HSV-shift / Brightness-Contrast / Invert (adjustment bakes) — SAFE, same footnote

`hsv_shift_region` and `map_region` both gate on `c.a != 0` (`tool.rs:530,549`), and
`color::hsv_shift` independently returns transparent input unchanged (`color.rs:194`). Same
staleness footnote as Dodge/Burn.

### Select-Layer / Select-by-alpha — SAFE

Pure alpha comparisons: `pixels.get(x, y).a > cutoff` (`session.rs:745,1999`). Hidden RGB is
invisible to them. Under the new scheme erased pixels still have `a == 0` and stay unselected.

### Gradient, Airbrush — SAFE (write-only in practice)

`apply_gradient` computes colors from the stop list and writes with `set` (`tool.rs:445-461`);
the airbrush plots `PaintMode::Over` dabs (`tool.rs:465-485`). Neither reads the buffer.
(Pre-existing quirk, unchanged: a gradient whose stops pass through `a=0` can *write*
`(R,G,B,0)` pixels into already-allocated tiles — one of the ways hidden RGB can exist today.)

### Move (drag draft, nudge) — CHANGED BEHAVIOR: strips hidden RGB, leaves ghosts

Reads are total (the float lifts full RGBA: `session.rs:1227-1228,2786-2787,2847-2848`), but
every re-application goes through `blit_over`/`blit_wrapped`, which skip `c.a != 0`
(`buffer.rs:419-450`; call sites `session.rs:193-215,781-786,1414-1418`), and layer-nudge
does `clear()` then copies only `c.a != 0` pixels (`session.rs:2746-2760`). Two consequences
under the literal spec: (a) hidden RGB **does not travel** with moved content — it is destroyed
at the destination side; (b) at the *source*, the vacated area is erased — under the "all erase
paths keep RGB" decision that erase would now leave the moved content's colors behind as hidden
RGB, so Un-erase there resurrects a copy of what was moved away ("ghost trails").

### Copy / Cut / Paste — ASYMMETRIC: Copy carries hidden RGB, Paste drops it

`copy()` clones full RGBA into the clipboard (`session.rs:2076-2091`), so the clipboard holds
hidden RGB; both the paste preview (`session.rs:681-683`) and the paste commit
(`blit_over`, `session.rs:2131`) skip `a == 0` — nothing hidden ever lands. Net: copy/paste of
a region silently discards its hidden RGB. `cut()` erases via `set(…, TRANSPARENT)`
(`session.rs:2104`) — under the new rule it keeps RGB, consistent with the Eraser.

### Flip / Rotate / Scale (layer, frame, document) — STRIP hidden RGB

All follow clone → `clear()` → copy back only `if c.a != 0`
(`session/canvas.rs:143-160,181-196`, selection-flip `canvas.rs:26-60`; the rotate/scale drafts
resample and re-place through the same style of guarded writes). Even without the guards,
`set()` itself drops `a==0` writes into not-yet-allocated tiles (`buffer.rs:196-199`), and the
rebuilt buffer starts empty — so transforms lose hidden RGB by construction. cleanEdge
resampling of the *visible* content is unaffected (headline #1).

### Import (PNG/GIF/…) — SAFE, and cannot introduce hidden RGB

Every import placement path gates `if c.a != 0` before writing (`import.rs:98-152`), so
external files whose transparent pixels carry RGB (common from other editors) are stripped on
entry. Two implications: imports neither break nor seed the feature, and a future implementer
must not "fix" these guards away thinking they're an oversight — they are also what keeps
imported garbage-RGB from becoming resurrectable content.

### Undo / Redo — SAFE

Patch-based: undo records swap whole tile `Arc`s (`buffer.rs:81-108`); bytes are restored
verbatim, hidden RGB round-trips exactly.

## Non-tool pixel readers

| Reader | Path | Verdict |
|---|---|---|
| Display / composite / frame thumbs | `render.rs` compositing, `frame_thumb_bytes` (`session.rs:446`) | **Safe** — `blend_over` skips `a==0`; hidden RGB is invisible |
| Layer film-strip thumbs | `layer_thumb_bytes` (`session.rs:469`) raw RGBA to the shell | **Visually safe** (alpha 0 renders invisible); bytes do cross the FFI |
| **Layer PNG / lossless-WebP export** | `layer_rgba_bytes` (`session.rs:500`) → `encode_png` | **LEAK** — raw straight RGBA embedded in the file; headline #3 |
| Frame/animation PNG/GIF export (publish) | composited before encode | **Safe** — no hidden RGB in published art |
| `.mkpx` save/load | verbatim tile bytes (`io.rs:543-548`) | Preserves hidden RGB (by design per the decisions); the Club attachment leak from ANALYSIS.md stands |
| `ascii` probe | `probe.rs:16-49` | **Safe** — `a==0` renders `.` before the color key is consulted |
| `stats` probe | `probe.rs:207` counts `a != 0` | **Safe** |
| `hash` probes, `content_hash` | all four channels hashed (`buffer.rs:253-269`) | **Changed meaning** — hash equality no longer implies visual equality (known from ANALYSIS.md; see below for the two-hash distinction) |
| cleanEdge | `similar()` (`cleanedge.rs:82-84`) | **Safe** — already canonicalizes transparent (headline #1). One residual: `dist2`/`cd` (`cleanedge.rs:93-128`) compare raw channels without the `a==0` clause; gated by `similar` in the paths reviewed, but the implementation should add a hidden-RGB-background rotation test to lock this in |

## The canonicalization rule (proposed engine invariant)

> **For any pixel *comparison* — fill matching, selection matching, similarity, visual
> hashing — a pixel with `a == 0` is treated as `(0,0,0,0)`. Storage keeps the real bytes.**

Why this exact formulation:

- It **exactly reproduces today's behavior** in Bucket and Select-by-Color, including the
  accidental-but-relied-upon behavior that a transparent pixel does *not* match a faint-alpha
  colored pixel at low thresholds (today `(0,0,0,0)` vs `(255,0,0,4)` has delta 255 via the R
  channel; naive "both-`a==0`-match" rules get this edge case wrong when only one side is
  transparent — canonicalizing the transparent side to zero RGB before the existing
  `max_channel_delta` keeps the delta at 255).
- cleanEdge already implements its spirit, so the engine ends up with one principle instead of
  two special cases.
- **It must NOT be applied to identity hashing**: the `.mkpx` tile dictionary dedups by content
  hash + byte equality (`io.rs:487-513`); canonicalizing there would merge tiles with different
  hidden RGB and destroy data. If "hash = visual equality" is worth preserving for probes and
  goldens, that needs a *separate visual hash* that canonicalizes, alongside the byte-identity
  hash. Decide which probes mean which.

## Further considerations not yet getting enough attention

1. **The durability story needs a decision, not just implementation.** With the literal spec,
   hidden RGB survives: painting nearby, adjustments, undo/redo, save/load. It dies on: move,
   nudge, paste, flip, rotate, scale, merge-down (source side: `session.rs:2581-2585`), and
   layer-clear. From a user's perspective Un-erase will feel *random* — "it worked yesterday,
   why not after I flipped the canvas?" Three coherent options, in increasing cost:
   (a) **document in-place-only semantics** and present Un-erase as best-effort recovery;
   (b) make relocation ops carry `(R,G,B,0)` pixels — touching every `a != 0` guard listed
   above, allocating tiles for invisible content (memory: the Android ~1 GiB scudo wall budgets
   were tuned without this), and turning `blit_over`'s skip into a read-modify-write;
   (c) narrow the feature: Un-erase works only against a dedicated, explicitly-managed state
   rather than piggybacking on stored RGB. Option (a) is the only one compatible with "small
   feature"; it should be an explicit product decision.
2. **No inspection surface.** The Eyedropper refuses `a==0` pixels and nothing else shows
   hidden RGB. If the feature ships, consider a debug/advanced view ("show hidden colors":
   render RGB ignoring alpha) — both for users to predict Un-erase and for support/diagnosis.
3. **The clipboard asymmetry** (Copy carries, Paste drops) is invisible today but becomes
   observable the moment Un-erase exists. Either make Paste drop-then-document, or carry
   through — same decision axis as consideration 1.
4. **Layer exports need the same scrub decision as the `.mkpx` attachment.** The publish
   pipeline is clean (composited), but `mkpx_export_layer_png`/WebP are raw. If the answer to
   the privacy question is "scrub on publish," the layer exports need an explicit
   scrub-or-keep decision too — keeping may even be desirable (round-tripping a layer through
   PNG preserving hidden RGB), which is exactly why it must be decided, not inherited.
5. **Merge-down keeps only the lower layer's hidden RGB** (the removed source layer's is
   discarded with it; the destination's survives where the source was transparent). Fine, but
   it belongs in the feature spec so tests can pin it.
6. **Test checklist for implementation time** (beyond the ANALYSIS.md churn estimate):
   Bucket + Select-by-Color over hidden-RGB backgrounds at threshold 0 and >0, seed-on-erased
   pixel; cleanEdge rotation over hidden-RGB background equals rotation over zeroed background;
   every relocation op's hidden-RGB policy pinned (whichever way it's decided); layer PNG
   export bytes with/without scrub; the two-hash (identity vs. visual) split if adopted.

## Revised confidence

- The **tool-breakage risk is smaller and better-bounded than the first analysis assumed**: two
  tools break, both fixed by one rule with an in-repo precedent; everything else is safe or
  merely needs its behavior written down.
- The **privacy surface is one file-type wider** (raw layer exports) than previously stated —
  ANALYSIS.md's claim "PNG export is safe" holds for frame/animation export only.
- The **biggest open question has shifted**: from "will tools break?" to "what does hidden RGB
  durability promise?" (consideration 1). That decision, not tool compatibility, now looks like
  the make-or-break for whether Un-erase feels dependable enough to ship.
