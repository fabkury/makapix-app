# Fuzzing review, 2026-09-30

**Scope.** The coverage-guided fuzzing harness in `fuzz/` (four cargo-fuzz targets), its WSL
runner in `tools/fuzz/`, the stable never-panic suite `crates/engine/tests/fuzz_inputs.rs`, and
the ledgers in `docs/fuzzing/` (ANALYSIS.md, FINDINGS.md). Reviewed at HEAD `5b77a1f6`.
This file is the assessment as written on the review date and is not updated afterwards; the
live work tracker is `PLAN.md` next to it.

## Verdict

The harness is well above hobby grade and close to production grade in its core discipline.
The parts that matter most are done right: coverage-guided libFuzzer with structure-aware
inputs, property oracles instead of crash-only oracles, a true differential against the C
reference for the hand-muxed animated WebP container, a CRC re-signing mutator that beat a
real semantic wall, a findings ledger where every finding closed with a regression test, and
honest run logs. Five real engine bugs (FZ-1 to FZ-5) came out of it.

It is not comprehensive, and it has drifted. The gaps are in coverage breadth, staleness, and
reproducibility, not in method.

## What is strong

- **Method.** Structure-aware generation (`arbitrary` to DSL text) drives the exact path the
  shell, the journal replay, and the CLI use. The compound oracle (no panic, undo/redo
  restores the content hash, save/load round-trip, byte-identical resave) turned the
  determinism doctrine into a continuously attacked theorem.
- **The WebP differential.** libwebp, the C reference, decodes our hand-muxed container and
  must agree pixel for pixel. The oracle is proven non-vacuous by `webp_check` (a 2 px frame
  shift inside a still-valid container is caught).
- **The loader mutator.** Re-signing after mutation keeps the shipped CRC verification in the
  fuzzed build while letting mutants past it, with one in eight left unsigned so reject paths
  stay live. Coverage moved from 1618 to 2300+ edges.
- **Discipline.** Every finding has a minimal reproducer, a root-cause write-up, a regression
  test verified to fail on the old code, and a doctrine line (never gate a mutation on an
  input-space proxy; compare content). Run logs record executions, edges, and corpus growth.
- **Ops.** Day and night run modes, per-target time budgets, cmin, `--from-head` for
  parallel-safe runs, systemd-run launch that survives the harness, a narrow corpus-commit
  policy with a size cap, and a triage gotcha list.

## What is weak

### 1. Stale against the engine

| Target | Last run | Engine changes since |
|---|---|---|
| `fuzz_load_mkpx` | 2026-08-29 (`f89a9333`) | canvas cap 512 (ADR 0021), memoized content hash (ADR 0031), layer cap 128 + tile-table billing in the loader (ADR 0032) |
| `fuzz_session_actions` | 2026-09-06 (`0105c3b6`) | 11 commits in session/tool/raster: batch verbs (ADR 0031, 0033), Crop canvas (ADR 0027), dither families (ADR 0028), import placement (ADR 0030), brush size fix, Copy source toggle, Diagonal chip |
| `fuzz_webp_differential` | 2026-09-05 | none in the muxer |
| `fuzz_codec_import` | 2026-09-05 | ADR 0030 and 0034 changed `import.rs` placement geometry |

No rule ties a fuzz burst to engine changes or to a release, so the harness only protects the
code as it was three weeks before the review. 81 commits landed in that window.

### 2. The actions target emits a shrinking fraction of the DSL

`crates/engine/src/session/parse.rs` dispatches about 203 verb arms. The `Act` enum in
`fuzz/fuzz_targets/fuzz_session_actions.rs` renders about 70 distinct verbs. Never emitted:

- **The whole draft family:** `MoveDraft*`, `RotateDraft*`, `ScaleDraft*`, `PasteDraft` /
  `PasteMove` / `PasteCommit`, `MoveSelection*`. This is exactly the live-mutating-drag class
  that produced FZ-4 and FZ-5. The target only ever *cancels* these in its settle line.
- **Newer editing verbs:** `ReplaceColor`, `Outline`, `SetSymmetry`, `SetLayerBlend`,
  `SetCleanEdge`, `SetBrushShape`, `SetProtectPixels`, `SetIntensity`, `SetThreshold`,
  `SetAlphaCutoff`, `SetShapeRotation`, `SetTriangleTip`, `SetGradientType`,
  `SetGradientSmoothstep`, `SetSelectionMode`, `SetFillAllLayers`, `SetMoveGroup`.
- **Every batch verb** from ADR 0031 and 0033 (`RemoveFrames`, `DuplicateLayers`,
  `SetLayersOpacity`, `CopyLayerToFrames`, `InsertBlankFrames`, `ShiftFrames`,
  `ReverseFrames`, and so on).
- `Repeat`, `ScaleLayer`, `ScaleFrame`, `RotateFrame`, `NewDocument`, `ClearHistory`,
  `SetMemBudget`, `SetSeed`, `Stroke`, the cursor verbs, the palette-management verbs,
  `Play` / `Pause` / `AdvanceClock`.
- **Tools** missing from the fuzz `Tool` enum: `Precision`, `MoveLayer`, `SelectCircle`,
  `SelectPoly`.

Nothing checks the enum against the parser, so every new verb silently widens the gap.

### 3. Untrusted surfaces with zero fuzz coverage

Both sit on the Club edit/remix path, where other users' bytes arrive through `mkpx_load`
and `mkpx_read_meta` in `crates/ffi/src/lib.rs`:

- **The compact DEFLATE envelope**, `crates/codec/src/mkpx_compact.rs::open`. The loader
  target feeds plain bytes only, so the compact header, the declared-length check, and the
  bomb guard are never exercised by a fuzzer.
- **The META reader**, `crates/engine/src/io.rs::read_meta_str`. The main loader skips META
  wholesale (`io.rs` treats `THMB | META` as skippable), so the varint, string, and typed-entry
  walk is unreached by the loader target even though provenance is read from loaded files.

### 4. The static WebP export is unverified

`fuzz_webp_differential.rs` returns early on single-frame input with a comment saying "that
path is covered by the static branch below." No such branch exists. Every still-image Club
publish goes through `codec::encode_webp` (the pure-Rust `image-webp` encoder) with no
independent decode check. GIF export has no oracle at all, not even "decodes back with
matching frame count and dimensions."

### 5. Reproducibility holes

- **The committed `fuzz/Cargo.lock` is stale.** It dates from the first harness commit
  (`bbede5a8`) and lists neither `makapix-codec` nor `image`. Cargo regenerates it on every
  WSL build (the regenerated file was discarded by decision on 2026-09-06), so the import and
  WebP targets may fuzz different `image`, `image-webp`, and `miniz_oxide` versions than the
  app ships. The root `Cargo.lock` pins `image 0.25.10`, `image-webp 0.2.4`,
  `miniz_oxide 0.8.9`.
- **Nightly is unpinned** in the fuzz crate (no `rust-toolchain.toml`), so a build can break
  or change instrumentation between runs.
- **The actions corpus lives only in `~/makapix-fuzz` on one laptop.** Regenerable in hours,
  so acceptable, but it is a single point of loss.

### 6. Blind spots nobody has measured

Coverage is tracked as libFuzzer's edge counter only. `cargo fuzz coverage` has never been
run, so there is no source-level map of which engine functions are unreached. Given gap 2,
that map would likely be sobering.

### 7. Smaller issues

- The loader `poke_reads` touches five read paths out of about forty on `Session`. Thumbs,
  outline mask, content bounds, used colors, save estimate, layer RGBA, display bytes, and the
  storage composite are skipped.
- The tolerant-load path saves but never reloads. A repaired document that cannot be reloaded
  strictly would pass.
- The import target has no image seeds. `make_seeds` writes only `.mkpx` files, so PNG, GIF,
  APNG, JPEG, BMP, and WebP structure is rediscovered from scratch in each fresh corpus.
- `make_seeds` comments and boundary seeds still target canvas 256 and 64 layers.
- The actions target always starts from a blank 32×32 canvas via `Session::new` and clamps
  resizes to 64, so multi-frame, deep-layer, and near-cap states are reached only by luck.
- `fuzz-day.ps1` and `fuzz-night.ps1` default to the two engine targets, so the codec targets
  run only when named.
- The `-max_len=2048` knob on the differential target does nothing (already noted in
  FINDINGS.md): `arbitrary` decides `Vec` length from a probability byte, not the buffer.

## Recommended work

Tracked in `PLAN.md`. Summary, in priority order:

| # | Item | Effort |
|---|---|---|
| 1 | Long burst on HEAD now; fuzz-burst rule tied to engine changes and releases | Low |
| 2 | Bring the actions target up to the parser (drafts first); a test that fails on unrendered verbs | Medium |
| 3 | Replay the committed loader corpus in a stable `cargo test` | Low |
| 4 | Loader target: compact envelope, META reader, tolerant reload, wider `poke_reads` | Low |
| 5 | Fuzz crate honors the root lockfile; pinned nightly | Low |
| 6 | Static WebP differential via libwebp; weak GIF decode-back oracle | Low |
| 7 | New actions oracles: two-session determinism, checkpoint restore + tail replay, tiny `SetMemBudget` refusal paths | Medium |
| 8 | Raw-text DSL target for the hand-written argument parser | Low |
| 9 | `cargo fuzz coverage` once per quarter, unreached functions logged | Low |
| 10 | Image seeds for the import target; 512-canvas and 128-layer boundary seeds | Low |

## Things not to do

- **An FFI target** (ANALYSIS.md §2.4). The FFI has 25 tests, invalid UTF-8 is handled in
  `mkpx_run`, and the unsafe surface is thin slices and C strings. The engine targets already
  cover what those wrappers call.
- **Dart-side fuzzing.** ANALYSIS.md §2.5 still holds. Journal repair and palette parsing have
  unit tests, and a failure there is a caught exception, not an abort.
- **A GIF palette differential.** The prior decision to decline it is right; the weak
  decode-back oracle in item 6 is enough.
- **ClusterFuzzLite or OSS-Fuzz.** The repo is Apache-2.0 on GitHub, so it qualifies, but the
  no-CI policy makes it moot unless that policy changes. If it ever does, ClusterFuzzLite is
  the cheap continuous option.

## Evidence gathered

- Verb count: `grep` of `"Verb" =>` arms inside `parse_line` in `parse.rs` (203); `Act`
  variants in the fuzz target (73, about 70 distinct verbs).
- Staleness: `git log 0105c3b6..HEAD -- crates` (13 commits), `git log f89a9333..HEAD --
  crates/engine/src/io.rs crates/engine/src/document.rs crates/engine/src/buffer.rs` (4).
- Lockfile: `grep '^name = ' fuzz/Cargo.lock` lists 17 packages, none from the image family;
  `git log -1 -- fuzz/Cargo.lock` is `bbede5a8`.
- Untrusted paths: `mkpx_load` calls `mkpx_compact::open` before `load_bytes_tolerant`;
  `mkpx_read_meta` calls `read_meta_str`; the loader's chunk walk skips `META`.
- Static WebP: `fuzz_webp_differential.rs` line `if sources.len() == 1 { return; }` with the
  stale comment above it.
- Last runs: `fuzz/logs/summary-20260906-1021-postfix.md` (actions),
  `summary-20260905-1535-parallel12h.md` (webp, import), `f89a9333` commit (loader).
