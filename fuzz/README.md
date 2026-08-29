# Makapix fuzzing

Coverage-guided fuzzing of the engine via `cargo-fuzz`/libFuzzer, per
`docs/fuzzing/ANALYSIS.md` (the why and the theory). This directory is the fuzz crate;
the run scripts live in `tools/fuzz/`. Fuzzing runs **in WSL2 (Ubuntu-24.04, nightly
Rust)** — the engine is platform-independent by construction, so a bug found on Linux
is a bug everywhere. Builds happen in `~/makapix-fuzz` inside WSL (ext4; `/mnt/c` is
too slow), and results sync back here automatically.

## Targets

- **`fuzz_load_mkpx`** — raw bytes → strict + tolerant `.mkpx` load → FFI read pokes →
  round-trip (content hash + byte-identical resave). Runs with `-rss_limit_mb=512` so
  the Android ~1 GiB allocator wall is an oracle on the workstation. Ships a **custom
  CRC re-signing mutator**: the loader verifies a whole-file CRC-32C before touching the
  body, so naive mutants all die at one branch (18.4M executions stuck at 1618 edges).
  The mutator restores the signature and rebuilds a correct INTG trailer after each
  mutation — what a real attacker does, since CRC-32C is not cryptographic — while
  leaving 1 in 8 mutants unsigned so the reject paths stay covered. With the
  `mkpx.dict` container dictionary and the boundary seeds this reached 2173 edges.
- **`fuzz_session_actions`** — structure-aware (`arbitrary`): random sequences of valid
  editor actions rendered to DSL text → `run_script` → compound oracle (no panic; Undo/
  Redo restores the content hash; save→load round-trip; byte-deterministic resave).
- **`fuzz_webp_differential`** — our hand-muxed animated WebP (VP8X/ANIM/ANMF with
  changed-rect delta frames) decoded by **libwebp**, Google's C reference, vendored and
  statically linked via `webp-animation`. Because the encoder is lossless and every ANMF
  is blend=overwrite / dispose=none, the reference decoder's composited canvas at frame
  *i* must equal our input frame *i* **exactly** — no tolerance. Catches halved-offset
  mistakes, too-small delta rects, bad chunk lengths, mis-sized canvases. Mechanizes what
  was a one-time manual check ("libwebp-verified lossless", 2026-08-09).
  Verify the oracle itself with `cargo +nightly run --release --bin webp_check`: it
  proves equality on correct output AND that a frame shifted 2 px (a still-valid
  container) is detected — a differential that cannot fail is not a test.
- **`fuzz_codec_import`** — the import path *we* own: `codec::decode` → `import_decoded`
  with a structured config (canvas size, scale mode, anchor, as-layer, start frame, crop
  rect). Oracles: no panic; every import either commits or registers a memory refusal;
  the resulting document saves, reloads, and resaves byte-identically. The `image`
  decoders underneath are fuzzed upstream by OSS-Fuzz, so their bugs are a bonus, not the
  target.

## Running (from PowerShell, repo root)

```powershell
./tools/fuzz/fuzz-day.ps1     # daytime companion: 8 workers, 4 h, quiet-ish, Ctrl+C safe
./tools/fuzz/fuzz-night.ps1   # overnight burst: 14 workers, 9 h, cmin + morning summary
# pick targets explicitly (default is the two engine targets):
./tools/fuzz/fuzz-night.ps1 -Targets "fuzz_webp_differential fuzz_codec_import"
# weight the budget per target with a `name:minutes` suffix (unsuffixed targets share the rest):
./tools/fuzz/fuzz-night.ps1 -Hours 10 -Targets "fuzz_session_actions:240 fuzz_load_mkpx:180 fuzz_webp_differential fuzz_codec_import"
```

Both print and save a summary (`fuzz/logs/summary-*.md`): executions, coverage, corpus
growth, and any new crash artifacts. Ctrl+C is safe — corpus and findings still sync
back. Both scripts take `-Hours`, `-Workers`, and `-Targets` overrides.

## When a crash artifact appears

1. Reproduce (WSL, in `~/makapix-fuzz`):
   `cargo +nightly fuzz run <target> fuzz/artifacts/<target>/<file>`
   The `fuzz_session_actions` panic message includes the failing DSL script and hashes.
   **Gotcha:** `RUST_LIBFUZZER_DEBUG_PATH=<file>` makes libfuzzer-sys dump the decoded
   input **without executing the target** — every such run "passes." Never use it to
   test whether an artifact still crashes; use it only to read the decoded input.
2. Minimize: `cargo +nightly fuzz tmin <target> fuzz/artifacts/<target>/<file>`
3. Record the finding in `docs/fuzzing/FINDINGS.md` (the durable ledger — artifacts
   are git-ignored working state). For a *panic* finding, also commit the reproducer as
   a new entry in `crates/engine/tests/fuzz_inputs.rs` (never-panic guard, runs on every
   platform, no nightly). For a *semantic* finding (undo coherence, byte determinism),
   do NOT add a failing check to the test suite while the bug is open — it would fail
   `cargo test` and the release gates; the regression test lands with the fix.
4. Fix the bug (a product decision, not the fuzzer's); the new test is the gate.

## Corpus policy

**Only `fuzz_load_mkpx`'s corpus is committed, and only entries ≤ 64 KiB**
(`CORPUS_COMMIT_MAX` in `run_fuzz.sh`). That one is worth keeping: it encodes hard-won
CRC-valid container structure, so a fresh machine starts deep inside the parser instead
of rediscovering the format. The size cap exists because fuzzing the boundary seeds
breeds multi-hundred-KB descendants (one 10-minute run made 45 MB of them).

Every **other** corpus is git-ignored. They run to thousands of tiny files that `cmin`
rewrites wholesale on each run — one burst churned 6,600 files — while regenerating
locally in minutes, so git is the wrong home for them. The WSL work tree
(`~/makapix-fuzz`) is the real corpus of record; `fuzz/artifacts/` and `fuzz/logs/` are
git-ignored operational output too.

`make_seeds` writes format-diverse small seeds (empty / drawing / noise / palette /
selection) plus **boundary seeds** that mutation reaches only by luck: a 256×256
16-layer noise document, 200 duplicate frames (tile-dictionary dedup at scale), and 60
distinct noise frames (widest legal dictionary index space). It runs automatically when
the corpus is empty; run it by hand (`cd fuzz && cargo +nightly run --release --bin
make_seeds`) to top an existing corpus back up.

## One-time WSL setup

```bash
sudo apt-get update && sudo apt-get install -y build-essential   # needs your password
curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain nightly --profile minimal
source ~/.cargo/env && cargo install cargo-fuzz
```

## Notes

- This crate is detached from the root workspace (`[workspace]` in its `Cargo.toml`):
  the workspace's `panic = "abort"` must not apply, and the fuzz profile enables
  `overflow-checks` (a silent wraparound violates the integer-exactness doctrine).
- If loader coverage plateaus suspiciously early, suspect the content-addressed tile
  hashes walling off deep code — see `docs/fuzzing/ANALYSIS.md` §1.6/§3.3 for the
  standard fixes before concluding "nothing to find."
