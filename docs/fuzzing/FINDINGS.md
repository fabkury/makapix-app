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

## FZ-2 — save→load→resave is not byte-identical (OPEN)

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

