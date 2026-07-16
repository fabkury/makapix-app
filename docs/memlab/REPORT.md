# Memory limits under adversarial content — measurement report

*2026-07-16 · Windows workstation (32 GB) + Google Pixel 10 Pro XL (16 GB, Android 16) ·
methodology and harnesses in `tools/memlab/`; raw data in `tools/memlab/results/*.csv`.*

## Question

The editor's limits are per-axis: ≤1024 frames, ≤64 layers/frame, ≤256×256 canvas. What actually
happens when they are pushed with content the architecture cannot mitigate — every layer of every
frame filled with pure random noise (no tile sparsity, no COW sharing, no RLE/dict/DEFLATE gains)?

## Test corpus

The `FillNoise(seed)` DSL action / `tool::noise_fill` (added for this study) fills a layer's
canvas with deterministic seeded random RGBA, every pixel non-transparent. A full 256×256 layer =
64 materialized tiles = **256 KiB payload**; a document's raw pixel payload is
`frames × layers × 256 KiB`. The combinatorial worst case (1024 × 64) is **16 GiB** — never
reachable on any target device; the practical question is *where the cliff actually is*.

Three workloads per platform:

- **gen/load** — direct document construction with no undo history (`mkpx gen`), then a fresh
  load: the resting-document floor, plus the `.mkpx` save/load transients.
- **edit** — the realistic path: scripted `AddFrame`/`AddLayer`/`FillNoise`, exactly what UI
  interaction produces, undo history retained.
- **churn** — repeated whole-layer repaints of one frame: undo-cap retention.

Engine-accounted memory comes from the new `mem` probe (`probe::mem_report`, Arc-pointer-deduped
census); OS truth from the `mem.os` probe (working set on Windows, `VmRSS`/`VmHWM` on Android).

## Results

### 1. Resting document — linear and predictable

| | Windows | Pixel 10 Pro XL |
|---|---|---|
| OS resident ÷ raw doc bytes | **1.10×** | **1.23×** |

(Baseline-subtracted slope, stable from 16 MiB to 1 GiB on Windows / 256 MiB on Android. The gap
is allocator overhead: scudo's per-chunk headers and alignment cost more than Windows' heap.)

Forecast: `resident ≈ 1.1–1.25 × frames × layers × canvas_tiles × 4096 B + ~5 MB baseline`
(engine only; the app adds its own ~200 MB Flutter/Dart baseline).

### 2. The `.mkpx` save transient — the biggest multiplier

Saving builds a content-addressed tile dictionary that **clones every distinct tile twice**
(dict order + hash-map key) and serializes into a growing buffer; noise defeats dedup entirely.

| | Windows | Pixel |
|---|---|---|
| Peak during save ÷ doc bytes | **6.2×** | **7.3×** |
| Load peak ÷ doc bytes | 2.1× | 2.2× |

A 256 MiB noise document peaks at **~2.0 GB** during save on the Pixel (measured in-app:
2,009 MB). Save is the first thing that dies as documents grow.

### 3. The editing path is quadratic — `AddFrame` history retention

Every structural edit records absolute before/after snapshots of the whole frame vector. Tiles
stay Arc-shared (cheap), but each snapshot re-allocates every layer's **tile-slot table**
(4,608 B/layer at 256×256, storage is 3w×3h). Adding frames one-by-one therefore retains

```
history_table_bytes ≈ 4608 × layers × frames²      (measured exact: F=512, L=1 → 1.208 GB)
```

Building 512 frames × 1 layer the way a user would costs **1.2 GB of undo tables for a 128 MiB
document** — 10.5× the document itself. The per-frame undo cap never trims these:
`DocStructure` records carry no frame id, so only the global 8192-record cap applies, far above
any realistic frame count.

### 4. Android has a hard allocator ceiling — independent of device RAM

On the Pixel (16 GB RAM), any workload dies with `memory allocation of 4112 bytes failed` +
SIGABRT (Rust `panic=abort`) once the **~4 KiB scudo size class** holds **~1.0 GiB**. Tiles
(4,112 B) and history tile-tables (4,608 B) share that class. Measured bisecting:

- 960 MiB of noise tiles → survives; 1,008 MiB → aborts (headless CLI, history-free)
- in-app `edit` of 512 frames × 1 layer → **aborts at frame 448** (tables ≈ 925 MB + tiles
  117 MB ≈ the same 1.0 GiB class total)

This is scudo's per-size-class region limit, not LMK and not total RSS (the process sat at
~3 GB RSS happily; it is the *one class* that ran out). Consequences:

- **No noise document above ~0.96 GiB can exist on Android at all** — a 1024×4 all-noise
  document is unrepresentable in-process regardless of device RAM.
- With the ~3× in-class save transient, the biggest noise document that can *save* is
  ~320 MiB (measured: 256 MiB saves, with the class at ~800 MB during the dict build).
- On Android the failure mode is a **native crash**, not a graceful error: `panic=abort` turns
  the failed 4 KiB allocation into SIGABRT.

Windows has no such class limit; the same workloads run to multi-GB there, which is exactly why
this never surfaced on the development workstation.

### 5. What is *not* a problem

- **Undo churn is correctly bounded.** Repainting one 256×256 layer N times plateaus at the
  128-record per-frame cap ≈ **33.5 MB per heavily-repainted frame** (measured plateau at
  N=128 and N=160). Byte-wise that cap is still generous (see recommendations) but it works.
- **COW sharing is measured and real**: duplicated frames/layers share tiles (census
  `doc_unique_tiles` vs `doc_tiles`), so non-adversarial documents sit far below these curves.
- **Flutter-side texture pressure is negligible at editor scale**: holding 1024 per-frame
  timeline thumbnails (48×48) alongside a 256 MiB document added ~10 MB (rung
  `edit:1024:1+clear+thumbs`: 508 MB RSS).
- **The in-app numbers match the headless CLI numbers** — engine memory behavior is identical
  inside the Flutter process; the app adds a ~200 MB constant baseline.

### 6. In-app escalation ladder (Pixel 10 Pro XL)

See `tools/memlab/results/android_app.csv` (+ `android_pss.csv` for PSS timelines). Highlights:

| Rung | Outcome |
|---|---|
| 64 MiB doc + 64 thumbs | ✓ 268 MB RSS |
| 256 frames × 1 layer, realistic edit | ✓ 626 MB RSS (302 MB of it history tables) |
| 256 MiB doc + 256 thumbs | ✓ 509 MB RSS |
| 512 frames × 1 layer, realistic edit | ✗ SIGABRT at frame 448 (history tables hit the class ceiling) |
| 256 MiB doc + 1024 thumbs | ✓ 508 MB RSS — timeline textures are negligible |
| 256 MiB doc + save (268.8 MB .mkpx in 3.3 s) | ✓ but **2,009 MB peak** |
| 1024 × 4 (1 GiB doc, thumbs or save variant) | ✗ SIGABRT at frame 960 = 960 MiB of tiles |
| 1024 × 8 (2 GiB attempt) | ✗ SIGABRT within frames 449–512 (0.90–1.00 GiB) |
| 1024 × 16 (4 GiB attempt) | ✗ SIGABRT within frames 193–256 (0.77–1.00 GiB) |
| 1024 × 32 (8 GiB attempt) | ✗ SIGABRT within frames 65–128 (0.52–1.00 GiB) |

Every kill is the same wall: the ~4 KiB allocation class reaching ~1 GiB, in-app exactly as in
the headless CLI. LMK never got a say — the allocator aborts first.

## Recommended budgets (for the enforcement follow-up)

The measured constants make a joint byte budget straightforward. Suggested numbers, sized so the
worst transient (save, ~7×… in-class ~3×) stays under the Android class ceiling with margin:

1. **Document budget: 256 MiB of materialized tile payload** (= 1024 frame-layers of full
   256×256 noise; vastly more of realistic content thanks to sparsity + COW). Enforce at the
   edges that grow the document (`AddFrame`/`DuplicateFrame`/`AddLayer`/import/paste): predict
   the post-action census (`probe::mem_report` is cheap) and refuse/warn past the budget,
   `ClubSizeRules`-style advisory first, hard stop at e.g. 320 MiB.
2. **Fix the quadratic history retention** — the highest-value single change. Options, best
   first: (a) make `DocStructure` snapshots share layer tables (store `Arc<[Option<Arc<Tile>>]>`
   or make `Frame` itself COW via `Arc`); (b) byte-budget the history (e.g. 128 MiB total,
   evict oldest past it) using `mem_report`'s `history_*` figures; (c) at minimum give
   `DocStructure` records a synthetic frame-count-scaled weight against the caps.
3. **Guard save/export**: the payload size is known exactly before serializing
   (`present_tiles × 4096`); above ~150 MiB on mobile, stream the dictionary or fail with a
   user-facing message instead of letting `panic=abort` take the process down.
4. **Consider `std::alloc::set_alloc_error_hook`** (or catching at the FFI seam) so allocation
   failure inside the engine surfaces as an error string to Dart rather than SIGABRT.
5. iOS is unmeasured (deferred); rerun `run_ladder` semantics there before trusting these
   numbers beyond Android.

## Reproducing

```powershell
cargo build -p makapix-cli --release
./tools/memlab/run_matrix.ps1                       # Windows matrix → results/windows.csv
cargo ndk -t arm64-v8a build -p makapix-cli --release
./tools/memlab/run_matrix_device.ps1                # headless device matrix → results/android.csv
./build_android.ps1 -Install
./tools/memlab/run_ladder.ps1                       # in-app ladder → results/android_app.csv
```

The in-app lab has no UI entry point; it launches only via
`adb shell am start -n club.makapix.app/.MainActivity -e memlab auto` (see `lib/dev/memlab.dart`
for the rung grammar).
