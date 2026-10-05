# Fuzzing findings ledger

Confirmed, deterministic engine findings from coverage-guided fuzzing (`fuzz/`,
operations in `fuzz/README.md`). Each entry stays open until it is either fixed (with a
regression test) or explicitly ruled as-designed. Crash artifacts live in the
git-ignored `fuzz/artifacts/`; the reproducer scripts below are the durable record.

**Do not add failing scripts to `crates/engine/tests/fuzz_inputs.rs` while the bug is
open** — that suite asserts never-panic only, and these are *semantic* findings; a
proper regression (e.g. an `assert.undo`-style check) would fail `cargo test` and the
release gates until the fix lands.

## Run log

| Date | Config | Loader | Actions |
|---|---|---|---|
| 2026-08-25 | 8 workers, 10 min/target (pre-fix) | 18.4M execs, 1618 edges, 0 crashes | 97k execs, 5337 edges, **8 crashes** → FZ-1/FZ-2/FZ-3 |
| 2026-08-25 | 8 workers, 10 min (mutator + dict + boundary seeds) | 534k execs, **2173 edges**, 0 crashes | — |
| 2026-08-25 | 14 workers, 12.5 min/target (post-fix) | 1.12M execs, **2234 edges**, 0 crashes | 2.08M execs, **6935 edges**, **0 crashes** |
| 2026-08-25 | 14 workers, 10 min/target (FZ-2 close, stale-mask guard live) | 1.00M execs, 2287 edges, 0 crashes | 1.47M execs, 6940 edges, 0 crashes |
| 2026-08-25 | 14 workers, 5 min/target (all findings closed) | 451k execs, 2289 edges, 0 crashes | 656k execs, 6940 edges, 0 crashes |
| 2026-08-26 | 14 workers, 22.5 min/target (night burst) | 2.53M execs, **2292 edges**, 0 crashes | 2.98M execs, **6947 edges**, **8 crashes** → FZ-4 |
| 2026-08-26 | 14 workers, 15 min, actions only (FZ-4 fix verification) | — | 2.35M execs, 6946 edges, **0 crashes** |
| 2026-08-26 | 14 workers, 30 min, actions only (post-fix soak) | — | 4.41M execs, **6948 edges**, **0 crashes** |
| 2026-09-05 | 6 workers, 90/45/45 min actions/webp/import, HEAD e56fbf9d, alongside another agent (`--from-head`, loader skipped) | — | 4.59M execs, **7194 edges**, 0 crashes (webp 8.76M/848, import 11.97M/5163, 0 crashes) |
| 2026-09-05 | 6 workers, 12-h queue (actions 6 h / webp 3 h / import 3 h), HEAD e56fbf9d | — | 15.3M execs, **7207 edges**, **2 crashes** (~4.5 h in) → FZ-5; webp 24.5M/848, import 26.5M/**5180**, 0 crashes; cmin |
| 2026-09-06 | 14 workers, 4 h, actions only, HEAD 0105c3b6 (FZ-5 fix verification) | — | 22.0M execs, 7206 edges, **0 crashes** |
| 2026-10-03 | 4 workers, 3 min, actions only, widened alphabet (fuzzing-review W2, `14c19522`), empty corpus | — | 294k execs, **10260 edges**, **1 crash** (~1 min in) → FZ-6 |
| 2026-10-03 | 4 workers, 5 min, actions only, widened alphabet + FZ-6 fix, empty corpus | — | 407k execs, **10606 edges**, **0 crashes** |
| 2026-10-03 | 12 workers, `w1main2`, HEAD `94c7b28e`, 310/241/69/69 min planned. Actions and loader ended after ~2 h and ~10 min: `-jobs` = workers, so every job's first artifact ended it for good (harness flaw) | 13.6k execs, 2445 edges, **11 OOM** — benign (below) | 1.96M execs, **12536 edges**, **1 crash** → FZ-7; **10 timeouts** — benign (below) |
| 2026-10-03 | same run `w1main2`, the other two targets (69 min each, full budget) | webp: 28.3M execs, 848 edges, 0 findings | import: 22.7M execs, **5447 edges**, 0 findings |
| 2026-10-03 | 12 workers, `w1rerun`, HEAD `d3947948` (FZ-6 + FZ-7 fixed; fork mode), actions 5 h + loader 4 h, full budgets, cmin | **10.86M execs**, **2475 edges**, **0 findings** | **5.92M execs**, **13373 edges**, **0 crashes**, 0 timeouts (7 slow-unit notes) |
| 2026-10-04 | 12 workers, `w4w10`, HEAD `70b55478` (fuzzing-review W4 + W10: widened loader oracles, new `fuzz_mkpx_open`, image seeds), loader 100 min, envelope 70, import 70, full budgets, cmin | 3.72M execs, **3738 edges**, 108 artifacts — all one over-strict harness oracle (below); `fuzz_mkpx_open`: **23.1M execs**, 3781 edges, **0 findings** | import: 11.5M execs, **10146 edges** (was 5447), **7 crashes** → FZ-8 |
| 2026-10-04 | 12 workers, `w4confirm`, HEAD `1a96d330` (FZ-8 fix + corrected META oracle), loader 45 min + import 45 min, no cmin | 1.51M execs, 3749 edges, **0 findings** | import: 8.42M execs, **10537 edges**, **0 findings** |
| 2026-10-04 | 10 workers, `night`, HEAD `9a417ba0`, 9-h overnight burst on all five targets (actions 162 min, loader 135, import 108, envelope 81, webp 54), full budgets, cmin | 3.45M execs, 3749 edges, **0 findings**; `fuzz_mkpx_open`: 7.57M execs, **3802 edges**, **0 findings**; webp: 11.1M execs, 848 edges, 0 findings | 2.55M execs, **13400 edges**, **0 crashes**, 0 timeouts (3 slow-unit notes); import: 17.0M execs, **11054 edges**, **0 findings** |

Post-FZ-4, a 30-minute actions soak (4.41M execs) reached a new coverage high for that
target — 6948 edges, above both the 6947 of the run that found FZ-4 and the 6940 of the
"plateau" — with no findings. The corpus is still growing fast (13,006 → 18,413 in one
run), so the actions target is exploring, not saturated; it is simply not producing bugs
at this depth any more.

The 2026-08-26 burst broke that plateau on both targets (loader 2289→2292, actions
6940→6947) and produced FZ-4 — the "low-yield" verdict below held only for the
*short* bursts it was written about; a 22.5 min/target run was long enough to reach
new surface.

Coverage on both targets has plateaued (loader 2287→2289, actions 6940→6940) with no
new findings across ~3.6M post-fix executions: the saturation the analysis doc predicts
(§1.6). Further short bursts on the current targets are low-yield; the next real gains
are new surface — the WebP differential and codec-import targets (§3.2 items 3–4) — or
much longer runs.

### New surface, 2026-08-25 — §3.2 items 3 and 4 implemented

| Date | Config | `fuzz_webp_differential` | `fuzz_codec_import` |
|---|---|---|---|
| 2026-08-25 | 14 workers, 10 min/target | 4.41M execs, 847 edges, 0 findings | 7.48M execs, 4894 edges, 0 findings |
| 2026-08-26 | 14 workers, 35 min, differential only | **15.54M execs**, 848 edges, 0 findings | — |

Both came up clean on first contact. For the differential that is a **meaningful
negative result, not an empty one**: 4.4M animations went through our hand-written
VP8X/ANIM/ANMF muxer and back through libwebp's decoder with pixel-exact agreement
every time, which is real evidence for the delta-frame container (halved ANMF offsets,
changed-rect bounds, chunk lengths) that previously rested on one manual spot-check.
The oracle is proven non-vacuous by `webp_check` (positive: 6 shapes match exactly;
negative: a frame shifted 2 px inside a still-valid container is caught).

**2026-08-26, 35 min (the deepest run this target has had).** 15.54M executions,
0 findings, and coverage moved 847 \u2192 848 edges \u2014 this oracle is saturated in a way
the actions target is not (which reached a new high the same day, and whose corpus is
still growing fast). Cumulative: **~20M animations** have now gone through our
hand-written muxer and back through libwebp with pixel-exact agreement. For a container
whose delta-frame arithmetic (halved ANMF offsets, changed-rect bounds, chunk lengths)
once rested on a single manual spot-check, that is about as strong as a negative result
gets, and further budget here is better spent elsewhere.

Throughput is the tell for why it saturates: ~740k exec/min, roughly 20x the actions
target. Most inputs bail before doing any work. Measured on random bytes (`arbitrary`
1.x decode of the `Anim` struct, 20k trials per length): ~50% decode to zero frames and
~25% to a single frame, so only ~25% reach the differential oracle at all; the rest
return immediately. Note this is the *from-scratch mutation* distribution \u2014 the live run
mutates an evolved corpus under coverage feedback, which favors oracle-reaching inputs,
so the real fraction is higher. Also note `-max_len=2048` is doing nothing for this
target either way: `arbitrary` decides `Vec` continuation from a probability byte, not
from remaining buffer size, so the frame-count distribution (mean 1.0) and `scale` are
identical at every budget from 96 to 2048 bytes. Harmless, but not a knob worth turning.

`fuzz_codec_import`'s 4894 edges are mostly the upstream `image` decoders, as expected
(§2.3) — its value is the wrapper invariants it pins: every import either commits or
registers a memory refusal, and any document an import produces saves, reloads, and
resaves byte-identically.

The last row is the validation that FZ-1 and FZ-3 are actually closed: the actions
target previously produced its first artifact within ~60 seconds at 8 workers, and now
survives 12.5 minutes at 14 workers (2.08M executions) while reaching 30% more coverage
than the run that found the bugs.

---

## FZ-1 — mid-stroke structural change breaks the undo invariant (FIXED 2026-08-25)

**Root cause (three related leaks, all one disease — untracked pixels vs. the
absolute-snapshot history):** live-painting dabs and stroke-end commits resolved the
*current* active frame/layer while the stroke's one undo record diffs only the layer
frozen at PointerDown; ops that rebuild storage geometry (resize/crop/rotate) or lift
pixels (transform drafts) snapshotted half-painted strokes; and the commit gate keyed
off the live `self.tool`, so a mid-stroke `SelectTool` onto a non-committing tool
stranded painted pixels untracked.

**Fix:** (1) painting + stroke-end paths resolve the frozen (fid, lid)
(`buf_by_ids_mut`/`paint_buf_mut`); (2) `Stroke` freezes its starting tool and every
stroke decision keys off it (ADR 0007's coat rule generalized); (3) `settle_open_edits`
force-commits any open stroke at every chokepoint that pushes records or rebuilds
geometry: `begin_edit`, `edit_frame`, `edit_doc`, resize/crop/canvas-rotate, the five
draft-begins, and the `Undo`/`Redo` verbs (undo mid-stroke now pops the just-drawn
pixels — standard editor semantics). Regression: `mid_stroke_structural_changes_keep_
undo_coherent` (16 reproducer scripts) + `layer_lock_is_undoable_…` in
`session.rs` tests. Post-fix fuzzing: all 25 accumulated artifacts pass; further
bursts produce no logic crashes.

Original report follows.

**Found:** 2026-08-25, `fuzz_session_actions`, first session (within minutes).
**Oracle:** undo coherence (SPEC §10 — do→undo→redo must restore the content hash).
**Status:** reproduces 10/10 via `mkpx run <script> assert.undo` (exit 1).

**2026-08-25 day-run update:** 6 more variants; the class is broader than "Add*" — it
also triggers with `ResizeCanvas(...)` mid-stroke and with `SelectTool(...)`
(tool switch) mid-stroke. Any fix must cover *every* structural/mode change that can
land between PointerDown and PointerUp, not just frame/layer insertion.

Minimal reproducer (one of several; 5 of the first 6 artifacts are this class):

```
AddLayer()
PointerDown(1532713775,1531693907)
AddLayer()
PointerMove(-75,0)
PointerUp()
```

Undo then Redo yields a *third* content hash — the committed stroke's undo record does
not reproduce the stroke's actual effect when a structural action (`AddLayer`,
`AddFrame`, `AddFrameAt(n)`, `AddLayerAt(n)`…) lands mid-stroke. Variants also hit it
with in-bounds starts (`PointerDown(-5,-1)` + `AddFrame()`×4 + `PointerMove(0,0)` +
`PointerUp()`). This is the F-29 *family* (mid-stroke interleaving), one ring further
out: F-29 fixed the panic; the semantic coherence of the undo record is still wrong.

Relatedly (same root area, observed via the first smoke run): `Undo()` while a stroke
is open pops the *previous* history entry and destroys the open stroke's
already-painted pixels unrecoverably (`parse.rs` `Undo =>` does no stroke handling).
The shell may or may not be able to send that today (Ctrl+Z while the pointer is
down); the engine-level contract question is open.

## FZ-2 — save→load→resave is not byte-identical (FIXED 2026-08-25, by the FZ-1 fix)

**Root cause: FZ-2 was a *symptom* of FZ-1, surfacing through a different oracle.** The
document carried a selection mask belonging to a *different canvas geometry* — the
FZ-1 disease (absolute history snapshots restoring a mask from geometry A onto a
document at geometry B, via untracked stroke pixels and Undo/Redo across a
resize/rotate). Such a mask serializes fine, but `decode_selection`'s out-of-range
guard (`io.rs:446`) legitimately DROPS it on load, so the resave omits the 18-byte
`SELC` chunk: 221 → 203 bytes, first divergence at byte 40. Content hashes stayed
equal throughout, which is exactly why `assert.roundtrip` never saw it.

**Verification (both original reproducers plus 13 selection×geometry variants now
byte-identical), and three new guards so the class cannot return silently:**

1. `debug_assert!` in `io::save_to_bytes`: the live selection must fit current storage.
   Pinned by `stale_selection_mask_trips_the_save_guard` (a `#[should_panic]` test that
   manufactures the state directly — no session op produces it any more), and enabled
   during fuzzing via `debug-assertions = true` in the fuzz profile, making it a live
   oracle rather than an 18-byte difference the fuzzer has to notice downstream.
2. `save_load_resave_is_byte_identical` — 15 scripts pairing selection work with canvas
   geometry, including Undo/Redo across a geometry change (how the stale mask used to be
   restored).
3. New CLI probe **`assert.roundtrip.bytes`** — save→load→save byte equality, scriptable
   and gate-able (exit 1). `assert.roundtrip` keeps its existing hash meaning.

Measured against a deliberately manufactured stale-mask document, the split is exact:
hashes equal, bytes 279 vs 261 (18 short — FZ-2's signature); `assert.roundtrip` PASSES
while `assert.roundtrip.bytes` FAILS.

Original report follows.

**Found:** 2026-08-25, `fuzz_session_actions`, first session.
**Oracle:** byte-determinism of the resave.
**Status:** deterministic. **Invisible to `assert.roundtrip`** — the CLI probe
compares content hashes, which match; only the byte comparison sees it.

```
InvertSelection()
RotateLayer(191)
PointerDown(-111,111)
Rotate(191)
ResizeCanvas(1,1)
PointerUp()
```

`save_bytes()` → 221 bytes; load + `save_bytes()` again → 203 bytes, first divergence
at byte 40. The loader normalizes something the saver preserved (suspect: the
selection from `InvertSelection` left stale by `ResizeCanvas(1,1)`). Violates the
"byte-deterministic `.mkpx`" doctrine (docs/mkpx-format/); also means a re-saved
document changes hash identity without a content change.

**2026-08-25 day-run update:** a second, independent reproducer with the *identical*
byte signature (221 → 203, first diff at byte 40): `PointerDown(21,-1)` /
`InvertSelection()` / `SelectTool(Rectangle)` / `PointerDown(1114011,267782262)` /
`ResizeCanvas(12,12)` / `SelectTool(Pencil)`. Common core of both scripts:
`InvertSelection` + `ResizeCanvas` — strengthens the stale-selection hypothesis.

## FZ-3 — undo/redo incoherence without any open stroke (FIXED 2026-08-25)

**Root cause:** `set_layer_locked` mutated persisted, hashed document state with NO
history record (the deliberate "set_layer_locked idiom"), while `visible`/`opacity`/
`blend`/`rename` all record. History records store absolute frame snapshots, so
undoing any earlier record (here: the RotateLayer record) silently reverted the
untracked lock, and redo re-applied a snapshot that never contained it.

**Fix:** `set_layer_locked` records one undo step via `edit_frame` like its siblings
(no-op re-set records nothing, the `set_layer_blend` idiom). Regression:
`layer_lock_is_undoable_and_survives_neighbor_undo_redo` in `session.rs` tests.

Original report follows.

**Found:** 2026-08-25, `fuzz_session_actions`, 20-minute day run
(artifact `crash-4174706f…`).
**Oracle:** undo coherence. **Status:** deterministic via `hash.doc` comparison
(script vs script+`Undo()` vs script+`Undo()`+`Redo()`); distinct from FZ-1 — no
PointerDown/PointerUp interleaving involved, plain sequential actions.

```
InvertSelection()
RotateLayer(85)
SetLayerLocked(0,true)
ApplyBrightnessContrast()
```

After the sequence the doc hash reflects the locked layer. `Undo()` *removes the
lock* (hash returns to the unlocked empty doc); `Redo()` is then a no-op — the lock
is never restored. Minimization facts (all verified 2026-08-25):

- Every proper subset tried is an undo no-op: `SetLayerLocked(0,true)` alone,
  `lock+ApplyBrightnessContrast`, `InvertSelection+lock+ApplyBC`,
  `InvertSelection+RotateLayer(85)`, `lock+ApplyLevels/ApplyHsvShift/Invert/FlipH` —
  so lock toggles are (by themselves) not history-tracked, yet the full sequence
  produces an undo entry whose undo reverts the lock and whose redo restores nothing.
- `SetLayerVisible(0,false)` + `ApplyBrightnessContrast()` is fully COHERENT — the
  visibility flag does not exhibit this.
- Suspicion: a refused/degenerate apply on a locked layer pushes a malformed history
  entry whose before-state snapshot predates the lock. Root cause not yet located.

## FZ-4 — a layer-move drag can mutate the document without recording it (FIXED 2026-08-26)

**Found:** 2026-08-26, `fuzz_session_actions`, 45-minute night burst (14 workers,
22.5 min/target). **Eight** artifacts, all the same oracle and, after reduction, the
same root cause.
**Oracle:** 2 — undo coherence (`Undo()` changed the document but `Redo()` did not
restore it).
**Status:** FIXED. Deterministic, reduced, root cause located. **Not a 1.6.0
regression** — all eight reproduce unchanged on the engine at `90835314` (the last
commit before the two 1.6.0 engine commits), so this is long-standing surface the
earlier short bursts never reached.

**Fix:** the layer-move commit gates its record on **content** — the drag's frame
compared against the `move_before` snapshot by `content_hash` — instead of on pointer
coordinates. `Buffer::content_hash` hashes the whole storage, off-canvas tiles
included, so it is a complete "did anything change" test rather than another proxy.
Recording (not reverting) is the right answer here: in both shapes below the pixels
genuinely did move, and the user's edit should survive. Regression:
`layer_move_records_from_content_not_pointer_coordinates` in `session.rs` tests —
five reduced scripts under the fuzz oracle, plus a direct assertion that a zero-delta
wrapped move is one undoable/redoable step, plus the other side of the gate (a true
no-op drag must still record nothing, so the first Undo pops the preceding tap rather
than an empty move record). Verified to fail against the old coordinate guard.

`move_draft_commit` was hardened the same way in the same pass (defense-in-depth: it
is reached only by the `MoveDraftCommit` verb, which none of the eight scripts use).
Its `if d.offset == Point::new(0, 0) { return; }` was the identical assumption; it now
paints first and returns early only when the frame content *and* the marquee are
provably unchanged, so a zero-offset wrapped draft cannot strand a fold-in either.

Original report follows.
**User-reachable:** yes. It reproduces with a plain `PointerUp()` as the only settle
step, i.e. the exact sequence a finger or mouse produces — no fuzz-only teardown verb
is involved.

**Root cause** — `crates/engine/src/session.rs:1643`, the layer-move commit in
`pointer_up`:

```rust
if self.move_before.is_some() {
    if let Some((fid, before)) = self.move_before.take() {
        if stroke.start != stroke.last {          // <-- pointer coords as a proxy
            ...
            self.doc.record_frame_content(fid, before, after, sel_before);
        }
    }
    ...
}
```

Layer-move mode re-blits into the document **live** on every `pointer_move`
(`session.rs:1559-1600`: `clear_in_place()` then `blit_wrapped` / `blit_over`), and
defers the undo record to `pointer_up`. The guard above then decides whether that
already-applied mutation gets recorded by comparing **pointer coordinates**, not
content. When the coordinates match but the pixels changed, `move_before` is dropped
via `.take()` — and unlike `cancel_stroke` (`session.rs:1805`), which restores the
snapshot, this path neither records the change nor reverts it. The document is left
holding a mutation no history record covers.

That is the FZ-1 doctrine violated again, from the other side: history records store
absolute snapshots, so *every persisted mutation must be tracked*. Here an untracked
one survives, and the next `Undo()`/`Redo()` pair replays a snapshot that predates it,
silently discarding the pixels.

Two ways the fuzzer reached it:

**(a) zero-delta drag with `wrap` on.** `PointerDown(7,7)` then `PointerMove(7,7)`
gives `dx = dy = 0`, so `start == last` and nothing is recorded — but
`blit_wrapped(snap, 0, 0, cr)` is *not* the identity once the layer holds pixels
outside the canvas rect (here left behind by shrinking 32x32 to 18x45): the
out-of-canvas columns fold back into view. Minimal reproducer, every line necessary
(ddmin-verified — dropping any one line makes the oracle pass):

```
SelectTool(Move)
FillNoise(28079)
SetWrap(true)
ResizeCanvas(18,45)
PointerDown(7,7)
PointerMove(7,7)
```

Line-by-line trace at HEAD (`*` = this line changed the document):

```
FillNoise(28079)      *  canvas=32x32  doc=9c6efaf8
ResizeCanvas(18,45)   *  canvas=18x45  doc=4036a639
PointerDown(7,7)         canvas=18x45  doc=4036a639
PointerMove(7,7)      *  canvas=18x45  doc=947125b7   <-- untracked mutation
PointerUp()              canvas=18x45  doc=947125b7   <-- records nothing
Undo()                *  canvas=32x32  doc=9c6efaf8   (pops the ResizeCanvas record)
Redo()                *  canvas=18x45  doc=4036a639   <-- 947125b7 lost for good
```

It repeats on every subsequent Undo/Redo round, and `SetWrap(true)` is required:
without wrap, `blit_over(snap, (0,0))` really is the identity.

**(b) a drag superseded by a second `PointerDown`.** A new `PointerDown` while a
layer-move drag is still open mutates the document (visible as `*` on the
`PointerDown` line) and re-snapshots `move_before`; the superseded drag's mutation is
never recorded. Two reduced scripts of this shape, neither needing `wrap`:

```
Tap(29,29)                    ResizeCanvas(1,2)
InvertSelection()             FillNoise(57260)
SelectTool(Move)              InvertSelection()
PointerDown(27,96)            SelectTool(Move)
PointerMove(44,5)             PointerDown(7,46)
PointerDown(27,96)   *        PointerMove(-1526700545,1537189028)
PointerMove(-125,5)           PointerDown(58,27)     *
PointerDown(5,5)     *        PointerMove(27,63)     *
PointerMove(5,5)     *
```

**Suggested fix direction** (not implemented — engine fixes are separate sessions):
replace the coordinate proxy with a content test, or make the not-recorded branch
restore `before` the way `cancel_stroke` does. A content comparison is the safer of
the two: it also covers shape (b), where the pixels genuinely did change and the
right answer is to record, not to revert. Note `move_draft_commit`
(`session.rs:3304`) carries the *same* `if d.offset == Point::new(0, 0) { return; }`
proxy with the same "nothing moved -> no document change" comment; it is safe today
only because that path leaves the document untouched while the draft is open, but the
assumption is the same one that fails here.

**Regression test:** lives in `session.rs`'s inline tests (the FZ-1/FZ-3 precedent),
not `crates/engine/tests/fuzz_inputs.rs` — that suite asserts never-panic only, and
FZ-4 never panicked the engine at all; the panic was the fuzz target's own oracle.

**Artifacts:** `fuzz/artifacts/fuzz_session_actions/crash-{2193f3e4, 2f8595d0,
475ec510, 4904768f, 4e48dc6f, 58a9683d, e6dfc2ac, f91ff3be}...` (8, git-ignored),
plus `minimized-from-7a6acc12...` from `cargo fuzz tmin`.

## FZ-5 — a layer-move drag settled by another verb can still go unrecorded (FIXED 2026-09-06)

**Found:** 2026-09-05, `fuzz_session_actions`, about 4.5 h into the actions leg of a
12-hour run (6 workers, HEAD `e56fbf9d`). Two artifacts, one root cause.
**Oracle:** 2 — undo coherence (`Undo()` changed the document but `Redo()` did not
restore it).
**Status:** FIXED 2026-09-06. Deterministic, reduced, root cause located; the fix was
first verified in a scratch tree (both artifacts and every reduced variant pass), then
landed with the regression test `settled_layer_move_records_from_content` (session.rs
tests: the reduced scripts under the fuzz oracle settled through the verb, the mechanism
directly, and the gate's other side), verified to FAIL against the old guard first. **Not a Symmetry-release regression:** both artifacts reproduce unchanged on
`f0f59d29`, the last commit before the Symmetry/Outline engine work. This is the FZ-4
hole from the other door.

**Root cause** — `crates/engine/src/session.rs`, `settle_open_edits`, the layer-move
branch:

```rust
if let Some((fid, before)) = self.move_before.take() {
    if stroke.start != stroke.last {          // <-- the FZ-4 proxy, still here
        if let Some(fi) = self.doc.frame_index_by_id(fid) {
            let after = self.doc.frames[fi].clone();
            ...
            self.doc.record_frame_content(fid, before, after, sel_before);
        }
    }
}
```

FZ-4 replaced the pointer-coordinate proxy in `pointer_up` with a content comparison
against the `move_before` snapshot, and hardened `move_draft_commit` the same way. The
third copy of the assumption — the settle path that commits an open layer-move drag when
some other verb needs a clean state (`begin_edit`, `edit_frame`, `edit_doc`, `repeat`,
Undo/Redo, the resize/crop family) — kept the proxy. The live re-blit in `pointer_move`
has already mutated the document by the time the settle runs; when the proxy says
"no drag", the mutation is neither recorded nor reverted (this path, like the old
`pointer_up`, does not restore `before`).

**Why the earlier bursts missed it.** The hole is only *visible* to a one-step oracle
when the verb that triggers the settle records nothing itself. A recording verb
(`FlipV` on a real canvas, `AddLayer`, anything with a diff) absorbs the untracked
mutation into its own `before` snapshot, so Undo/Redo of that one step looks coherent —
the damage moves one step deeper into the stack, where the oracle does not look. The
fuzzer needed a *no-op* settle-triggering verb right after a zero-delta drag:
`ApplyLevels()` at default levels, or `FlipV()` on a 1×1 canvas.

Two shapes, every line necessary, checked line-by-line with `mkpx … hash.doc` on the
`f0f59d29` engine (`*` = the document changed on that line):

**(a) zero-delta wrapped re-blit, settled by a no-op `ApplyLevels`** — FZ-4 shape (a),
reached through the settle path instead of `pointer_up`:

```
PointerDown(7,7)      *   paint one pixel
PointerMove(47,39)    *   stroke to the far corner
ResizeCanvas(4,6)     *   shrink: pixels now live outside the canvas
SelectTool(Move)
PointerDown(7,-9)         layer-move drag begins, move_before snapshotted
SetWrap(true)
PointerMove(7,-9)     *   zero delta, but blit_wrapped folds the off-canvas pixels in
ApplyLevels()             default levels: edit_doc settles the drag (proxy: start == last,
                          nothing recorded), then records nothing itself
```

`Undo()` now pops `ResizeCanvas`; `Redo()` restores its `after` snapshot, which predates
the fold-in. Replacing `ApplyLevels()` with a plain `PointerUp()` passes (that path is
content-gated since FZ-4); replacing it with `FlipV()`/`AddLayer()`/`Undo()` passes for
the masking reason above; a non-zero delta passes; wrap off passes.

**(b) clamped pointer on a 1×1 canvas, settled by a no-op `FlipV`:**

```
PointerDown(7,7)      *   one pixel
SelectByAlpha(Replace)
CropToSelection()     *   canvas is now 1×1 around that pixel
SelectByAlpha(Replace)
Cut()                 *   pixel removed (selection kept)
SelectTool(Move)
Undo()                *   pixel back
PointerDown(11,-1)        selection move (floating) begins
PointerMove(9,9)
PointerDown(5,3)      *   supersedes the drag: the floating move commits, the pixel
                          lands off-canvas; a new drag starts in layer-move mode
PointerMove(9,9)      *   the re-blit rewrites the layer
FlipV()                   1×1 flip is a no-op: settles the drag, records nothing
```

`pointer_down`/`pointer_move` run the pointer through `clamp_pointer` ("bound
off-canvas input"), so on a 1×1 canvas `(5,3)` and `(9,9)` both clamp to the same
point: `start == last` and the proxy declares a no-op drag — while the zero-offset
re-blit (`clear_in_place` + `blit_over` of a snapshot holding an off-canvas pixel)
changed the content hash. `Undo()` pops the floating move instead, `Redo()` re-applies
it, and the layer-move's pixels are gone. Ending the first drag with an explicit
`PointerUp()`, or making the second drag literally zero-delta, fails identically.

**User-reachable:** the trigger is a document verb arriving while a layer-move drag is
open — a keyboard shortcut (Flip, Levels, Undo…) with the mouse button still down on
desktop, or any journaled verb interleaved with a drag. Not reachable from touch alone.
Shape (a) needs wrap on plus a prior shrink; shape (b) needs a tiny canvas.

**Fix:** gate the settle path on content, exactly as `pointer_up`
does since FZ-4:

```rust
if let Some((fid, before)) = self.move_before.take() {
    if let Some(fi) = self.doc.frame_index_by_id(fid) {
        if self.doc.frames[fi].content_hash() != before.content_hash() {
            let after = self.doc.frames[fi].clone();
            let sel_before = self.doc.selection.clone();
            self.doc.record_frame_content(fid, before, after, sel_before);
        }
    }
}
```

With that change both artifacts execute clean under the fuzz binary and all 15 reduced
variants pass the exact oracle (settle → Undo → skip-if-unchanged → Redo must restore) on
a patched `mkpx`, including the gate's other side (a true no-op layer drag settled by
`ApplyLevels` still records nothing). **Doctrine unchanged, now applied to the third
copy:** never decide whether a mutation happened from pointer coordinates — and note that
`clamp_pointer` makes coordinates an even weaker proxy than FZ-4 assumed, since distinct
inputs collapse to one point on small canvases.

**Regression test:** `settled_layer_move_records_from_content` in `session.rs` tests — the
scripts above under the fuzz oracle, settled through the verb rather than `PointerUp()`,
plus the mechanism directly and a no-op drag that must still record nothing. It failed
against the old guard on the first script before the fix went in. Not `fuzz_inputs.rs` —
never-panic only; the engine never panicked here.

**Gotcha for triage:** the CLI's `assert.undo` probe is *stricter* than the fuzz oracle —
it also reports FAIL when Undo is a content no-op (e.g. it pops a selection-only
record). Emulate the oracle with three `hash.doc` runs (script+settle, +Undo, +Undo+Redo)
and skip when the undone hash equals the settled one; several "failing" variants during
this triage were that artifact of the probe, not the bug.

**Artifacts:** `fuzz/artifacts/fuzz_session_actions/crash-1a2439cd…` (shape b, 1026
bytes) and `crash-39fc4a7b…` (shape a, 399 bytes), reduced with `cargo fuzz tmin` to
74 and 55 bytes (the DSL above is the reduced form; git-ignored).

---

## FZ-6 — an open selection-mask drag survives a geometry change (FIXED 2026-10-03)

**Found:** 2026-10-03, `fuzz_session_actions`, about a minute into the first smoke run of
the widened alphabet (fuzzing-review W2: the target had never emitted `MoveSelectionBegin`
before). One artifact.
**Oracle:** the FZ-2 save guard (`debug_assert!` in `io::save_to_bytes`: "selection mask
outside storage at save time (stale geometry)"), reached through oracle 2's Undo.
**Status:** FIXED 2026-10-03, with the regression test
`selection_drag_is_settled_before_geometry_changes` (session.rs tests), verified to fail on
the old code first.

**Root cause.** `MoveSelectionBegin` opens a coalesced selection-mask drag: it snapshots the
mask into `move_sel_before`, `MoveSelection` steps move the mask in place, and
`MoveSelectionCommit` records one selection step whose `before` is the snapshot. The
snapshot was not part of `settle_open_edits`, the chokepoint every structural verb runs to
close open strokes, layer drags, and pen segments (FZ-1). So it survived a geometry change:

```
FillNoise(1)
SelectTool(SelectRect)
PointerDown(8,8)
PointerMove(24,20)
PointerUp()               a 17x13 selection on the 32x32 canvas
MoveSelectionBegin()      move_sel_before = that mask (32x32 storage)
CropToSelection()         canvas is now 17x13; the crop clears the selection in its own record
MoveSelectionCommit()     before (32x32 mask) != current (None) → records a selection step
Undo()                    restores the 32x32 mask onto the 17x13 canvas
```

The same holds for `ResizeCanvas` and `CropCanvas`. On a debug build the save guard trips.
On release the stale mask did not panic (painting, filling, copy/paste, and further crops
on it were tried); the selection is silently dropped on save, so save→load→resave stops
being byte-identical — the FZ-2 symptom.

**Reachability:** low. The shell sends `MoveSelectionBegin` at the start of a selection drag
and `MoveSelectionCommit` at its end (`editor_page.canvas.dart`), so a crop or resize has to
arrive mid-drag: a journal replay, or a desktop shortcut during a mouse drag.

**Fix:** `settle_open_edits` ends with `move_selection_commit()`, so an open mask drag
commits before the structural verb snapshots the document, exactly as an open stroke does.
Undo mid-drag now commits the drag and pops it, matching strokes since FZ-1. The shell's
own `MoveSelectionCommit` after the drag becomes a no-op in those cases.

**Regression test:** `selection_drag_is_settled_before_geometry_changes` — the reduced
script plus moved-mask, `ResizeCanvas`, `CropCanvas`, and Undo-mid-drag variants, each
checked through two Undos and two Redos for a mask that fits the storage and a
byte-identical resave; then the step structure (undoing the crop restores the moved mask,
the next Undo reverts the drag, Redo restores it). Not `fuzz_inputs.rs`: the engine panics
here only through a `debug_assert!`.

**Artifact:** `crash-c507f1b8…` (25 bytes; git-ignored). The script above is the reduced
form, checked with the debug `mkpx` CLI and `assert.roundtrip.bytes`.

---

## FZ-7 — Move, Scale, and Rotate selection drafts survive a geometry change (FIXED 2026-10-03)

**Found:** 2026-10-03, `fuzz_session_actions`, run `w1main2` (12 workers, HEAD `94c7b28e`,
which already carries the FZ-6 fix). One artifact.
**Oracle:** the FZ-2 save guard ("selection mask outside storage at save time (stale
geometry)"), after oracle 2's Undo.
**Status:** FIXED 2026-10-03 (decision: cancel the drafts), with the regression test
`geometry_changes_cancel_open_transform_drafts` (session.rs tests), verified to fail without
the fix.

**Root cause.** The three transform drafts snapshot geometry-bound state when they open:
`sel_before` (the selection mask in the current storage geometry), and for the Move draft also
the float anchors and `bbox` in storage coordinates. The drafts deliberately stay open across
ordinary edits (the document is untouched until commit, and the commit snapshots the frame it
finds), so `settle_open_edits` does not close them. A crop or resize changes the storage
geometry underneath them, and the commit then mixes geometries:

- **Move draft:** the commit paints the floats at the old anchors and sets the selection to the
  translated old-geometry mask. The save guard trips with no Undo at all.
- **Scale and Rotate drafts:** the commit records the old-geometry `sel_before` as the step's
  `before`, so Undo restores it onto the new canvas.

Reduced scripts (debug `mkpx` CLI, `assert.roundtrip.bytes`; `*` = trips the guard):

```
FillNoise(1); SelectTool(SelectRect); PointerDown(8,8); PointerMove(24,20); PointerUp()
then:
* MoveDraftBegin(); MoveDraftMove(2,2); CropToSelection(); MoveDraftCommit()
* ScaleDraftBegin(); ScaleDraftSet(1500,1500); CropToSelection(); ScaleDraftCommit(); Undo()
* RotateDraftBegin(); RotateDraftSetAngle(500); CropToSelection(); RotateDraftCommit(); Undo()
  RotateDraftBegin(); CropToSelection(); RotateDraftCommit()      (identity: commits nothing)
  Copy(); PasteDraft(); PasteMove(3,3); CropToSelection(); PasteCommit(); Undo()   (passes)
  any of the drafts + Cancel instead of Commit                      (passes)
  a layer-mode move draft (no selection) across ResizeCanvas         (passes this oracle)
```

`ResizeCanvas` behaves like the crop. An Undo that crosses a crop while a draft is open passed.
The fuzzer's own script reached it through the rotate draft (`RotateDraftBegin` …
`CropToSelection` … `RotateDraftCommit`, then Undo).

**Reachability:** probable. The shell cancels open drafts when the tool changes
(`editor_page.engine.dart`), but `CropCanvas` and `ResizeCanvas` run from the canvas menu with
no draft cancel before them, so a pending Move/Rotate/Resize draft with a selection followed
by Crop canvas or Resize canvas reaches it. Not verified on a device. Journals replay it too.
**Consequence on release builds:** no panic (debug-assert only); the selection is wrong or
silently dropped on save, and a committed Move draft lands its pixels at pre-crop coordinates.

**Fix (user decision 2026-10-03: cancel, not commit).** `Session::exec` compares the storage
size before and after every verb; when it changed (crop, resize, an Undo/Redo across one) it
calls `cancel_transform_drafts()`, which drops the move, rotate, scale, and paste drafts as
their Cancel verbs do. The pending transform is discarded and the later Commit is a no-op.
Drafts still survive verbs that keep the geometry. The shell cancels its own draft UI before
Crop canvas and Resize canvas (`_cancelTransformDrafts`, shared with the tool-change path),
so it never offers Commit for a draft the engine dropped. The shell change is covered by
`flutter analyze` and the Dart suite only; it was not exercised on a device.

**Regression test:** `geometry_changes_cancel_open_transform_drafts` — the scripts above plus
paste, `ResizeCanvas`, `CropCanvas`, and an Undo crossing a crop with a draft open, each
checked through two Undos and two Redos for a mask that fits the storage and a byte-identical
resave; then the cancel itself (no draft after the crop, Commit is a no-op, one Undo restores
the pre-crop document) and a draft surviving a same-geometry verb.

**Artifact:** `crash-fc38a386…` (git-ignored).

### Benign artifacts from the same run (triaged 2026-10-03)

- **10 timeouts (actions).** Every one is a 128×128 canvas (`side(255)`, libFuzzer's 0xFF
  bias again) with `DuplicateLayers` repeated toward the 128-layer cap, then `RotateFrame`.
  They take 10–60 s under the fuzz build's instrumentation and 0.3–2.4 s in a release build;
  none hangs. Harness, not engine.
- **11 OOMs (loader).** Ten are existing corpus entries (264,864 and 986,057 bytes), one a
  mutant; each runs alone in 75–250 ms without exceeding the limit. Loading the 646-entry
  corpus into one process already peaks at 487 MB of RSS, so libFuzzer's process-wide
  `-rss_limit_mb=512` had ~25 MB of headroom — the allocator-retention false-OOM the actions
  target hit in August, now reached by the grown loader corpus. Harness, not engine.

---

## FZ-8 — an animated frame delay near `u32::MAX` ms overflows the duration (FIXED 2026-10-04)

**Found:** 2026-10-04, `fuzz_codec_import`, run `w4w10` — the first run with image seeds
(fuzzing-review W10), which took the target from 5447 to 10146 edges. Seven artifacts, one
cause.
**Oracle:** crash (`attempt to multiply with overflow`, the fuzz build's overflow checks).
**Status:** FIXED 2026-10-04 with the regression test
`animated_frame_delay_near_u32_max_does_not_overflow` (codec tests; the fuzzer's 139-byte
animated WebP), verified to fail first.

**Root cause.** `crates/codec/src/lib.rs`, `decode_animated_capped`:
`duration_us: dur_ms.max(1) * 1000` in `u32`. An animated WebP's ANMF frame duration is 24
bits of milliseconds (the reproducer carries 0xFD0050 ms, about 4.6 hours), so anything above
4,294,967 ms overflows. Release builds do not check overflow: the import got a wrapped, wrong
frame duration (no panic, no memory issue; the engine clamps durations afterwards).
**Reachability:** any import of a crafted or odd animated file (WebP; GIF and APNG delays are
16-bit and cannot reach it). **Fix:** `saturating_mul`.

### Harness false positives from the same run (triaged 2026-10-04)

- **108 loader artifacts**, all the new META oracle: "splice_meta_str refused entries
  read_meta_str returned from the same file". `read_meta_str` returns at the first META
  chunk, `splice_meta_str` walks every chunk, so a CRC-valid file with a malformed chunk
  after its META reads but does not splice. The loader rejects those files too, so the
  refusal is correct; the oracle now demands the splice only of strict-loadable files. All
  108 pass on the corrected target.

---

## OBS-1 — a small compact file can force a large inflate before the loader refuses it (ACCEPTED LIMIT, cap lowered 2026-10-04)

Not a fuzz finding: noticed while building `fuzz_mkpx_open` (W4) and measured by hand, because
the run's `-max_len` keeps inflations under what the harness could flag.

**What.** `mkpx_compact::open` inflates a compact `.mkpx` up to its stated length under a fixed
cap before the engine's loader sees a byte. A 522 KB file declaring 512 MiB of zeros was
accepted and fully inflated (peak RSS 1.6 GB on the workstation, 9 s), then refused by the
loader. On Club edit/remix the app opens another user's file twice in a row — `mkpx_read_meta`
and `mkpx_load` both inflate — so a crafted layers upload costs the opener's cap in transient
memory, twice, on the reader's phone. No crash in the engine, no corruption; on a low-memory
device the OS may kill the app (not tested on a device). The server's 50 MB upload limit does
not prevent it.

**Why accepted.** The app already accepts, by design, files that cost about as much: the
loader's budget admits documents up to 320 MiB of tile payload, and such a document can come
from a compact file of a few MB. Opening one holds the inflated bytes and the document at once.
The bomb is therefore not a new class, only a cap above what the loader would ever accept.

**Decision (user, 2026-10-04).** Lower `MAX_INFLATED` from 512 to **384 MiB** (`05a7500e`):
`MEM_HARD_BUDGET` (320 MiB) plus headroom for chunk overhead, META, palettes, and the selection.
The opener now refuses nothing the loader could load (a test pins the cap above the budget). The
remaining spike is the accepted document-size limit itself (`docs/memlab/REPORT.md`). Rejected:
a smaller cap on the Club path only (new FFI surface, refuses large legitimate posts) and a
server-side check (possible follow-up; the app must not depend on it either way).
