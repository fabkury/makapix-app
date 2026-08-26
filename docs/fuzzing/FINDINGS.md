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

Both came up clean on first contact. For the differential that is a **meaningful
negative result, not an empty one**: 4.4M animations went through our hand-written
VP8X/ANIM/ANMF muxer and back through libwebp's decoder with pixel-exact agreement
every time, which is real evidence for the delta-frame container (halved ANMF offsets,
changed-rect bounds, chunk lengths) that previously rested on one manual spot-check.
The oracle is proven non-vacuous by `webp_check` (positive: 6 shapes match exactly;
negative: a frame shifted 2 px inside a still-valid container is caught).

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

## FZ-4 — a layer-move drag can mutate the document without recording it (OPEN)

**Found:** 2026-08-26, `fuzz_session_actions`, 45-minute night burst (14 workers,
22.5 min/target). **Eight** artifacts, all the same oracle and, after reduction, the
same root cause.
**Oracle:** 2 — undo coherence (`Undo()` changed the document but `Redo()` did not
restore it).
**Status:** OPEN. Deterministic, reduced, root cause located. **Not a 1.6.0
regression** — all eight reproduce unchanged on the engine at `90835314` (the last
commit before the two 1.6.0 engine commits), so this is long-standing surface the
earlier short bursts never reached.
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

**Regression test:** deliberately NOT added to `crates/engine/tests/fuzz_inputs.rs`
while this is open — a failing semantic check there breaks the release gates
(`release_android.ps1` runs `cargo test`). Add it with the fix.

**Artifacts:** `fuzz/artifacts/fuzz_session_actions/crash-{2193f3e4, 2f8595d0,
475ec510, 4904768f, 4e48dc6f, 58a9683d, e6dfc2ac, f91ff3be}...` (8, git-ignored),
plus `minimized-from-7a6acc12...` from `cargo fuzz tmin`.
