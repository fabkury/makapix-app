# replaylab — measurement harnesses for the session-replay appraisal

The tools behind the numbers in [`docs/replay/ANALYSIS.md`](../../docs/replay/ANALYSIS.md)
(2026-08-11). Same spirit as `tools/memlab/`: non-shipping lab code, results interpreted in the
report, nothing here is a product path.

## Contents

- `gen_replay_script.py` — generates the synthetic-but-representative DSL corpus into `out/`
  (gitignored): `replay_small|medium|large.txt` (runnable by `mkpx`), a `+<delta-ms>`-timestamped
  `.log` twin per script (recording-format size/compressibility model — never fed to `mkpx`),
  `replay_cheap.txt` (100k `SetCursor`, the parse/dispatch floor) and `baseline.txt` (process
  startup). Prints line counts, bytes/line, and gzip/deflate ratios as it writes.
- `vocab_check.txt` — a tiny script touching every verb the generator emits; run it after
  changing the generator (or the DSL) to catch vocabulary drift:
  `./target/release/mkpx run tools/replaylab/vocab_check.txt state`.
- `replaybench/` — a standalone bench crate (path-deps on `crates/codec` + `crates/engine`;
  deliberately **not** a workspace member). Modes, all `replaybench <mode> <w> <h> <X> <frames>
  [script]`:
  - `gif` / `webp` — time the shipped streaming encoders on timelapse-shaped content
    (progressive limited-palette drawing), with the per-frame `upscale_nearest` at scale `<X>`.
  - `upscale` — `upscale_nearest` alone. · `png` — per-frame PNG at upscaled size.
  - `snap 1 1 <checkpoints> 0 <script>` — replay a corpus script in chunks, take a COW
    frame-vector snapshot per checkpoint, pointer-census the retained tiles/tables.
  - `comp 1 1 <reps> 0 <script>` — `render::composite_frame` cost at source resolution.

  Content is LCG-deterministic: Windows and Android runs see identical inputs (and produced
  byte-identical encoder outputs in the appraisal).

## Reproducing the ANALYSIS numbers

```powershell
# corpus + recording-size/compressibility numbers (§2)
python tools/replaylab/gen_replay_script.py

# replay throughput + memory census + snapshot (.mkpx) roundtrip deltas (§3.1)
cargo build -p makapix-cli --release
Measure-Command { ./target/release/mkpx.exe run tools/replaylab/out/replay_large.txt }  # median of 7
./target/release/mkpx run tools/replaylab/out/replay_large.txt mem mem.os
Measure-Command { ./target/release/mkpx.exe run tools/replaylab/out/replay_large.txt assert.roundtrip }

# encoder / upscale / snapshot-retention / composite numbers (§3.2, §4.1)
cd tools/replaylab/replaybench
cargo build --release
./target/release/replaybench webp 256 256 4 450
./target/release/replaybench gif  256 256 4 450
./target/release/replaybench upscale 128 128 8 450
./target/release/replaybench snap 1 1 300 0 ../out/replay_large.txt
./target/release/replaybench comp 1 1 200 0 ../out/replay_large.txt
```

On-device twin (the `tools/memlab/run_matrix_device.ps1` pattern; use PowerShell — Git Bash
mangles `/data/...` paths):

```powershell
cargo ndk -t arm64-v8a build -p makapix-cli --release
cd tools/replaylab/replaybench; cargo ndk -t arm64-v8a build --release; cd ../../..
adb shell "mkdir -p /data/local/tmp/replay"
adb push target/aarch64-linux-android/release/mkpx `
         tools/replaylab/replaybench/target/aarch64-linux-android/release/replaybench `
         tools/replaylab/out/replay_large.txt /data/local/tmp/replay/
adb shell "cd /data/local/tmp/replay && chmod +x mkpx replaybench"
adb shell "cd /data/local/tmp/replay && for i in 1 2 3; do time ./mkpx run replay_large.txt >/dev/null; done"
adb shell "cd /data/local/tmp/replay && ./replaybench webp 256 256 4 450"
adb shell "rm -rf /data/local/tmp/replay"   # cleanup when done
```

Timing caveats: `mkpx run` prints no timing of its own — subtract the `baseline.txt` process
startup (~6 ms Windows / ~50 ms device) from wall-clock medians. The CLI's `render`/`composite`
probes break on absolute Windows paths (colon-separated probe specs), so pass relative output
filenames.
