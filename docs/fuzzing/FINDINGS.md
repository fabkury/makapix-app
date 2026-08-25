# Fuzzing findings ledger

Confirmed, deterministic engine findings from coverage-guided fuzzing (`fuzz/`,
operations in `fuzz/README.md`). Each entry stays open until it is either fixed (with a
regression test) or explicitly ruled as-designed. Crash artifacts live in the
git-ignored `fuzz/artifacts/`; the reproducer scripts below are the durable record.

**Do not add failing scripts to `crates/engine/tests/fuzz_inputs.rs` while the bug is
open** — that suite asserts never-panic only, and these are *semantic* findings; a
proper regression (e.g. an `assert.undo`-style check) would fail `cargo test` and the
release gates until the fix lands.

---

## FZ-1 — mid-stroke structural change breaks the undo invariant (OPEN)

**Found:** 2026-08-25, `fuzz_session_actions`, first session (within minutes).
**Oracle:** undo coherence (SPEC §10 — do→undo→redo must restore the content hash).
**Status:** reproduces 10/10 via `mkpx run <script> assert.undo` (exit 1).

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
