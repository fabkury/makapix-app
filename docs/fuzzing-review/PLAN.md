# Fuzzing review: work plan

Live tracker for closing the gaps in `REVIEW.md` (2026-09-30). One row per item. Update the
Status and Closed-by columns as work lands; add a dated note under the item when a decision
changes. Run results still go to `docs/fuzzing/FINDINGS.md` (the run log and findings ledger);
this file tracks the harness work, not the bugs it finds.

**Status values:** `open` (undecided) · `accepted` · `in progress` · `done` · `deferred` ·
`rejected`. **Decision** is the user's call per item; nothing here is pre-accepted.

## Tracker

| ID | Item | Priority | Effort | Status | Decision | Closed by |
|---|---|---|---|---|---|---|
| W1 | Long burst on HEAD; fuzz-burst rule for engine changes and releases | 1 | Low | open | | |
| W2 | Actions target up to the parser; unrendered-verb test | 2 | Medium | open | | |
| W3 | Stable `cargo test` replays the committed loader corpus | 3 | Low | open | | |
| W4 | Loader target: compact envelope, META reader, tolerant reload, wider `poke_reads` | 4 | Low | open | | |
| W5 | Fuzz crate honors the root lockfile; pinned nightly | 5 | Low | open | | |
| W6 | Static WebP differential; weak GIF decode-back oracle | 6 | Low | open | | |
| W7 | New actions oracles: determinism, checkpoint replay, tiny budgets | 7 | Medium | open | | |
| W8 | Raw-text DSL parser target | 8 | Low | open | | |
| W9 | `cargo fuzz coverage` quarterly; unreached functions logged | 9 | Low | open | | |
| W10 | Image seeds for import; 512-canvas and 128-layer boundary seeds | 10 | Low | open | | |
| R1 | FFI fuzz target (ANALYSIS.md §2.4) | | | rejected | Not worth it: 25 FFI tests, thin unsafe surface, engine targets cover the callees | |
| R2 | Dart-side fuzzing | | | rejected | ANALYSIS.md §2.5 still holds; failures are caught exceptions | |
| R3 | GIF palette differential | | | rejected | Prior decision stands; W6's weak oracle is enough | |
| R4 | ClusterFuzzLite / OSS-Fuzz | | | rejected | Moot under the no-CI policy; revisit only if that policy changes | |

## Items

### W1. Long burst on HEAD; a fuzz-burst rule

**Why.** The loader was last fuzzed 2026-08-29 and the actions target 2026-09-06; the caps,
the loader billing, and eleven session/tool/raster commits changed since (REVIEW.md gap 1).

**Steps.**
1. Overnight burst on all four targets at HEAD, `--from-head --cmin`, weighted toward
   actions and loader (the 2026-08-28 recipe: `fuzz_session_actions:240 fuzz_load_mkpx:180
   fuzz_webp_differential:90 fuzz_codec_import:90`). Launch via `systemd-run --user`
   (memory: `fuzzing-analysis`).
2. Record the run in FINDINGS.md; commit the loader corpus growth.
3. Write the rule down in `fuzz/README.md`: a burst on every engine commit that touches
   `io.rs`, `session*`, `tool*`, `raster.rs`, `import.rs`, or `crates/codec`, and one before
   every Play/App Store release. Record the fuzzed HEAD in FINDINGS.md's run log so the gap is
   visible.
4. Change `fuzz-day.ps1` and `fuzz-night.ps1` defaults to all four targets (REVIEW.md gap 7).

**Done when.** A clean (or triaged) run on HEAD is in the run log and the rule is in the README.

### W2. Actions target up to the parser

**Why.** About 70 of 203 verbs are rendered; the draft family, the FZ-4/FZ-5 class, is never
emitted (gap 2).

**Steps.**
1. Add `Act` variants for the draft family first: `MoveDraftBegin/Move/Commit/Cancel`,
   `RotateDraftBegin/BeginFrame/Move/SetAngle/Commit/Cancel`, `ScaleDraftBegin/BeginFrame/
   Move/Set/Commit/Cancel`, `PasteDraft/PasteMove/PasteCommit/PasteCancel`,
   `MoveSelectionBegin/Commit`, and the settle line stays as is.
2. Then the newer editing verbs, the batch verbs, `Repeat`, `ScaleLayer/Frame`,
   `RotateFrame`, `NewDocument`, `ClearHistory`, `SetSeed`, `Stroke`; the missing tools
   (`Precision`, `MoveLayer`, `SelectCircle`, `SelectPoly`).
3. Decide per verb whether it belongs in the fuzz alphabet or on an explicit exclusion list
   (candidates for exclusion: `Play/Pause/AdvanceClock`, cursor verbs, `SetMemBudget` unless
   W7 takes it, `SetOverscanView`).
4. Add a test (in the engine crate, or a `cargo test` in the fuzz crate on stable) that
   extracts the verb arms from `parse.rs` and fails when one is neither rendered by the fuzz
   target nor on the exclusion list. This is the drift guard.
5. Consider starting some sequences from a loaded seed document (a small committed `.mkpx`
   with several frames and layers) instead of always `Session::new(32, 32)`, and widening
   `ResizeCanvas` past 64 occasionally.

**Done when.** The drift test passes and a burst on the widened alphabet is in the run log.

### W3. Stable corpus replay in `cargo test`

**Why.** The committed loader corpus (553 files, 2.9 MB) is only used under nightly in WSL.
Replaying it on stable makes it a release gate on every platform (gap 7, and ANALYSIS.md §3
"two-tier" intent).

**Steps.**
1. A test in `crates/engine/tests/` that walks `fuzz/corpus/fuzz_load_mkpx/` (path relative
   to `CARGO_MANIFEST_DIR`) and runs the loader target's body: strict + tolerant load,
   `poke_reads`, round-trip on strict success. Skip silently if the directory is absent (public
   checkouts without the corpus must still pass).
2. Keep it fast: the corpus is small; cap wall time if it grows.
3. Optionally commit a cmin'd sample of the actions corpus (a few hundred entries) and replay
   it the same way through `run_script`. Decide against if the churn argument from the corpus
   policy still wins.

**Done when.** `cargo test` on Windows replays the corpus and the release gate inherits it.

### W4. Loader target widening

**Why.** Two untrusted parsers on the Club path have zero fuzz coverage; the tolerant save is
never reloaded; `poke_reads` covers five of about forty read paths (gaps 3 and 7).

**Steps.**
1. In `fuzz_load_mkpx`, on a share of inputs (say 1 in 4 by a byte of the input), wrap the
   bytes through `mkpx_compact::compress` before loading, and separately feed the raw bytes to
   `mkpx_compact::open` so a hostile compact header is exercised.
2. Call `io::read_meta_str` on every input (plain) and on the compact-opened bytes.
3. After the tolerant load, save and reload strictly; assert the reload succeeds.
4. Extend `poke_reads` to thumbs, outline mask, content bounds, used colors, save estimate,
   layer RGBA, display bytes, and the storage composite.
5. Add compact-envelope and META tokens to `fuzz/mkpx.dict`.

**Done when.** A loader burst on the widened target is in the run log.

### W5. Lockfile and toolchain pinning

**Why.** The committed `fuzz/Cargo.lock` predates the codec dependency; each WSL build
resolves `image`, `image-webp`, and `miniz_oxide` afresh (gap 5).

**Options.** (a) Commit the regenerated `fuzz/Cargo.lock` and keep it in sync with the root
by hand. (b) Have `run_fuzz.sh` copy the root `Cargo.lock` into the work tree and run cargo
with `--locked` after a one-time merge. (c) Fold the fuzz crate into the workspace with a
profile override; rejected by the original design (panic strategy and overflow checks), so
prefer (a) or (b). Pin nightly with a `fuzz/rust-toolchain.toml`.

**Done when.** The fuzzed decoder versions provably equal the shipped ones and the nightly is
recorded.

### W6. Static WebP differential; GIF decode-back

**Why.** The single-frame path is what every still Club publish uses and has no independent
check; GIF export has no oracle (gap 4).

**Steps.**
1. In `fuzz_webp_differential`, replace the early return on one frame with a static decode
   via libwebp (the `webp` crate over `libwebp-sys`, or `webp-animation`'s underlying sys
   crate) and pixel-exact comparison. Fix the stale comment.
2. A small `fuzz_gif_export` target or a branch in the same target: `encode_gif` then decode
   with the `image` GIF decoder; assert frame count, dimensions, and that fully opaque
   palette-exact inputs round-trip exactly (a decidable subset; no tolerance oracle).

**Done when.** `webp_check` gains a static positive/negative pair and a burst is logged.

### W7. New actions oracles

**Why.** Cheap properties the product promises that no target asserts (gap 7 and REVIEW.md
recommended work).

**Steps.**
1. Determinism: run the rendered script in two fresh sessions; assert equal
   `doc.content_hash()` and equal `state_json()`.
2. Replay: split the script at an arbitrary index, run the prefix, `take_checkpoint`, run the
   suffix, record the hash; `restore_checkpoint`, rerun the suffix, assert the same hash. This
   is the Watch-replay promise (`replay_checkpoint.rs` covers fixed scripts only).
3. Budgets: emit `SetMemBudget` with tiny values so refusal paths run on a 32×32 canvas;
   after the sequence assert the document is coherent (round-trip) and that history and
   checkpoint retained bytes stay under the configured budgets.

**Done when.** Each oracle is proven non-vacuous (a deliberately broken variant fails) and a
burst is logged.

### W8. Raw-text DSL target

**Why.** The hand-written argument parser (floats, hex colors, tuples, point lists, enum
tokens) is covered only by the fixed-LCG `random_dsl_never_panics` test (REVIEW.md
recommended work).

**Steps.** A `fuzz_dsl_text` target: arbitrary bytes, lossy UTF-8, `run_script`, then
`poke_reads`. Seed with `examples/*.txt` and a dictionary of verb names and argument tokens.

**Done when.** A burst is logged; any parser panic becomes a `fuzz_inputs.rs` entry.

### W9. Source-level coverage

**Why.** Edge counts do not say which functions are unreached (gap 6).

**Steps.** `cargo +nightly fuzz coverage <target>` in WSL, `llvm-cov report` over the engine
sources, and a short "unreached" list per target appended to FINDINGS.md. Repeat quarterly or
after W2.

**Done when.** The first report is in FINDINGS.md and W2's exclusion list is checked against it.

### W10. Seeds

**Why.** The import target starts with no image structure; the boundary seeds predate the
512-canvas and 128-layer caps (gap 7).

**Steps.**
1. `make_seeds` writes tiny PNG, GIF (multi-frame), APNG, JPEG, BMP, and WebP (static and
   animated) files into `corpus/fuzz_codec_import/` using the codec's own encoders where they
   exist and byte literals otherwise.
2. Add 512×512 and 128-layer boundary `.mkpx` seeds; update the comments.
3. Decide whether the import corpus joins the commit policy (probably not; seeds regenerate).

**Done when.** Seeds exist and the next import burst starts above its previous edge count.

## Log

- 2026-09-30: review written, plan opened with all items undecided.
