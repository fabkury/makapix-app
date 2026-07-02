# Makapix `.mkpx` File Format — Version 5 (Redesign)

**Status:** Design specification, pending implementation and measurement gates (§16).
**Scope:** Supersedes `SPEC.md §17` (the legacy v1–v4 container). This is a free redesign; the app is
pre-distribution, so **no backward compatibility with v1–v4 is required or provided** (§14).
**Audience:** Engine and shell developers building the new codec.

`.mkpx` is the native, lossless working-state format of the Makapix Editor. It stores an animated,
multi-layer pixel-art document at full **8-bit straight RGBA** fidelity. This version is designed to be
**smaller** (content-addressed tile dedup + a per-tile codec menu with a raw floor), **faster** (a fast
encoder mode for autosave, one linear read path), and **more robust** (validated integrity, a typed-chunk
container) than the legacy format — while keeping the engine **pure-Rust and dependency-free**.

---

## Table of contents

1. Goals & non-goals
2. Design principles
3. Terminology & constants
4. Data model
5. Storage buffer, gutter & coordinate system
6. Container structure
7. Chunk: `HEAD`
8. Chunk: `TILE` (tile dictionary)
9. Tile codecs
10. Chunk: `FRMS` (frames, layers, tile-ref grids)
11. Chunk: `UPAL` (user palettes)
12. Chunk: `SELC` (selection)
13. Chunks: `THMB`, `META`
14. Chunk: `INTG` (integrity)
15. Encoder modes (fast vs compact) & verify-on-encode
16. Decoder / load path
17. Determinism contract
18. Versioning & extensibility
19. Engine dependency boundary
20. Validation & measurement gates
- Appendix A — Decided-against alternatives
- Appendix B — Deltas from legacy v1–v4

---

## 1. Goals & non-goals

**Goals**

- **Lossless, integer-exact** persistence of the full document (all frames, layers, palettes, selection),
  preserving every 32-bit RGBA value including RGB under `alpha = 0`.
- **Smaller files** than legacy per-tile RLE, driven primarily by **cross-frame/layer tile deduplication**
  and a **per-tile codec menu** that includes a spatial predictor (for gradients) and opportunistic indexing
  (for low-color tiles), with a **raw floor** guaranteeing no tile ever inflates past 32-bit RGBA.
- **Fast autosave**: a low-latency encoder mode suitable for the 5-second, hash-coalesced autosave loop.
- **Pure-Rust, Android-clean**: the entire container and all tile codecs live in the dependency-free engine.
  The only sanctioned optional dependency is a pure-Rust DEFLATE (§19), gated on measurement (§20).
- **Robustness**: a validated integrity check so truncated/corrupt autosaves are detected, not silently
  loaded.
- **Extensibility without churn**: a typed-chunk container with explicit criticality, and reserved codec IDs.

**Non-goals**

- Cross-user interchange or long-term archival of `.mkpx` (the Club shares *rendered* PNG/GIF/WebP, never
  `.mkpx`; see §14). A portable interchange/export format, if ever wanted, is out of scope here.
- Backward compatibility with legacy v1–v4 (§14, Appendix B).
- Lossy compression of any kind.

---

## 2. Design principles

- **The format defines capabilities; the encoder chooses how to use them.** Deduplication, per-tile codec
  selection, predictor-mode choice, and DEFLATE are all *encoder* decisions. A trivial conformant encoder may
  store every tile `RAW` with no dedup; a smart encoder minimizes size. The decoder is simple and universal.
- **Raw floor — never inflate.** Every tile can be stored `RAW`; the encoder picks the smallest candidate, so
  no content is ever larger than uncompressed 32-bit RGBA.
- **Dedup is orthogonal to the codec.** Identical tiles collapse regardless of how each distinct tile is
  encoded. This is the dominant lever for animation and layered art and is independent of color count.
- **Content-agnostic core.** The predictor + entropy path handles flat art *and* gradients *and* alpha with no
  color-count cliff. Indexing is *opportunistic*, never mandated.
- **One read path.** A single supported version, a linear chunk walk, no migration ladder.
- **Lossless & integer-exact.** Correctness is defined by pixel round-trip (content hash), matching the
  existing pixel-centric `assert.roundtrip` gate — not by exact file-byte reproduction.
- **Pure-Rust engine.** No `image`, no WebP, no C toolchain in the persistence path (§19, Appendix A).

---

## 3. Terminology & constants

| Term | Definition |
|------|------------|
| **Document** | The whole artwork: canvas size, timeline of frames, palettes, selection, metadata. |
| **Frame** | One animation cell; has a duration and an ordered list of layers. |
| **Layer** | One buffer within a frame; has name, visibility, lock, opacity, blend mode. |
| **Buffer** | A layer's pixels: a sparse grid of tiles over the *storage* area (canvas + gutter, §5). |
| **Tile** | A fixed **32×32** block of straight RGBA pixels; the unit of storage, dedup, and codec choice. |
| **Storage area** | The persisted pixel extent = canvas plus its gutter margins (§5). |
| **Tile dictionary** | The deduplicated set of distinct non-empty tiles (§8). |
| **Tile-ref grid** | Per-layer row-major grid of dictionary indices; `0` = transparent (§10). |

Constants:

| Name | Value |
|------|-------|
| `TILE_SIZE` | 32 (pixels per side) |
| `TILE_AREA` | 1024 (pixels per tile) |
| `TILE_BYTES` | 4096 (straight RGBA bytes per tile) |
| Canvas dimensions | `8..=256` in each axis |
| Frames per document | `1..=1024` |
| Layers per frame | `1..=64` |
| Frame duration | `16_667..=1_000_000` µs (1/60 s .. 1 s) |
| Pixel format | 8-bit **straight** (non-premultiplied) RGBA, sRGB; byte order R, G, B, A |
| Endianness | **little-endian** for all fixed-width integers |
| `varint` | unsigned LEB128 |

Pixel index within a tile is row-major: `i = y * 32 + x`, `x,y ∈ 0..31`.

---

## 4. Data model

```
Document
├── canvas (w, h)                     8..=256 each
├── gutter margins (l, t, r, b)       persisted storage extent (§5)
├── timeline
│   └── Frame[1..=1024]
│       ├── frame_id (opaque u32)
│       ├── duration_us
│       ├── active_layer
│       └── Layer[1..=64]
│           ├── layer_id (opaque u32)
│           ├── name, flags (visible/locked), opacity, blend
│           └── Buffer  → tile-ref grid → { tile dictionary }
├── user palettes (named swatch sets) — UI concern, not compression (§11)
├── selection (optional, for crash recovery) (§12)
├── thumbnail (optional) (§13)
└── metadata (optional) (§13)
```

Pixel data is stored **once** in the document-global **tile dictionary** (`TILE`, §8); each layer buffer is a
compact **tile-ref grid** (`FRMS`, §10) pointing into it. Identical tiles anywhere in the document — across
frames, across layers — share a single dictionary entry.

---

## 5. Storage buffer, gutter & coordinate system

Each layer buffer covers a **storage area** = the canvas plus an off-canvas **gutter** on each side. The
gutter holds legitimate off-canvas pixels (overscan strokes the user may later pan/crop into view) and MUST be
persisted losslessly.

- Persisted gutter margins `(gl, gt, gr, gb)` are recorded in `HEAD` (in pixels).
- `storage_w = canvas_w + gl + gr`, `storage_h = canvas_h + gt + gb`.
- Tile grid: `tiles_x = ceil(storage_w / 32)`, `tiles_y = ceil(storage_h / 32)`.
- The canvas origin within the storage area is `(gl, gt)`.
- **Edge tiles are always full 32×32.** Pixels of an edge tile that fall outside `[0, storage_w) × [0,
  storage_h)` are **canonically `(0,0,0,0)`**. This makes tile bytes well-defined so dedup and hashing are
  unambiguous.
- **Empty tiles cost nothing**: a grid cell with no allocated pixels references dictionary index `0` (the
  implicit transparent tile) and is absorbed by run-length in the ref grid (§10). The mostly-empty gutter is
  therefore nearly free.

The **runtime** gutter (the engine's in-memory storage size) is an engine constant and MAY be larger than the
persisted gutter. On load, the persisted storage area is placed at the canvas origin within the runtime
storage area (§16). A compact save MAY shrink the persisted gutter to the union of the canvas and the bounding
box of non-empty tiles (§15); a fast save persists the full runtime gutter.

---

## 6. Container structure

A `.mkpx` file is a fixed signature followed by a linear sequence of typed chunks.

**Signature (8 bytes):**

| Offset | Type | Field | Value |
|--------|------|-------|-------|
| 0 | `u8[4]` | magic | `"MKPX"` = `4D 4B 50 58` |
| 4 | `u16` | `format_version` | `5` |
| 6 | `u16` | `container_flags` | reserved, `0` |

**Chunk framing (repeated to EOF):**

| Type | Field | Notes |
|------|-------|-------|
| `u8[4]` | `fourcc` | chunk type (ASCII) |
| `u8` | `chunk_flags` | bit0 = **critical** |
| `u32` | `length` | payload length in bytes |
| `u8[length]` | `payload` | chunk-specific |

**Reader rules**

- `HEAD` MUST be the first chunk; `INTG` MUST be the last chunk.
- Chunk types defined here have fixed criticality (table below). For an **unknown** `fourcc`: if the critical
  bit is set → **error** (`UnsupportedChunk`); otherwise **skip** it.
- Duplicate critical chunks → error. Order of non-`HEAD`/`INTG` chunks is otherwise unconstrained.

**Defined chunks**

| FourCC | Critical | Presence | Purpose |
|--------|:--------:|----------|---------|
| `HEAD` | ✔ | exactly 1, first | Document header (§7) |
| `TILE` | ✔ | exactly 1 | Tile dictionary (§8) |
| `FRMS` | ✔ | exactly 1 | Frames, layers, tile-ref grids (§10) |
| `UPAL` | – | 0 or 1 | User palettes (§11) |
| `SELC` | – | 0 or 1 | Selection mask (§12) |
| `THMB` | – | 0 or 1 | Thumbnail (§13) |
| `META` | – | 0 or 1 | Metadata (§13) |
| `INTG` | ✔ | exactly 1, last | Integrity CRC (§14) |

---

## 7. Chunk: `HEAD`

Uncompressed. Payload:

| Type | Field | Notes |
|------|-------|-------|
| `u16` | `canvas_w` | `8..=256` |
| `u16` | `canvas_h` | `8..=256` |
| `u16` | `gutter_left` | pixels (persisted) |
| `u16` | `gutter_top` | pixels |
| `u16` | `gutter_right` | pixels |
| `u16` | `gutter_bottom` | pixels |
| `u32` | `frame_count` | `1..=1024` |
| `u16` | `active_frame` | 0-based |
| `u16` | `active_palette` | 0-based; `0xFFFF` = none |
| `u8` | `loop_mode` | `0` Loop · `1` Once · `2` PingPong |
| `u8` | `head_flags` | bit0 has `THMB` · bit1 has `SELC` · others reserved |

`tiles_x`/`tiles_y` (used by `FRMS`) are derived from canvas + gutter per §5.

---

## 8. Chunk: `TILE` (tile dictionary)

The deduplicated set of distinct **non-empty** tiles. Tile index `0` is the implicit fully-transparent tile
and is **never** stored. Entry *i* in the stream is dictionary index *i* (1-based).

Payload:

| Type | Field | Notes |
|------|-------|-------|
| `u8` | `transform` | `0` none · `1` deflate (§19) |
| `u32` | `uncompressed_len` | **only present if `transform == 1`** |
| … | `stream` | the (optionally inflated) dictionary stream below |

Dictionary stream:

```
varint  tile_count
repeat tile_count times:
    u8      codec            // §9
    varint  payload_len
    u8[payload_len] payload  // decodes to exactly 4096 straight-RGBA bytes
```

**Deduplication (encoder responsibility).** A compact encoder content-addresses tiles (canonical 4096-byte
form, §5) and emits each distinct tile once; every referencing grid cell points to the shared index. The file
stores only indices, so the dedup hash algorithm is *not* part of the format. A fast encoder MAY dedup
incrementally or not at all.

---

## 9. Tile codecs

Every codec decodes to exactly `TILE_BYTES = 4096` straight-RGBA bytes (row-major 32×32). IDs `4..=15` are
reserved for future codecs; a decoder encountering an unknown codec ID → error.

| ID | Name | Best for | Payload |
|----|------|----------|---------|
| 0 | `RAW` | the floor / incompressible | 4096 bytes verbatim |
| 1 | `RLE` | flat regions, solid fills | `(u16 run, u8[4] rgba)*`, Σ run = 1024 |
| 2 | `DELTA_RLE` | gradients, dodge/burn, ramps | `u8 predictor` + `RLE(residual pixels)` |
| 3 | `INDEXED` | busy low-color tiles (dithering) | `u16 color_count` + `rgba8[color_count]` + packed indices |

**`RLE`** — identical-consecutive-pixel run-length, as legacy: a sequence of `(u16 run_len, 4-byte RGBA)` whose
run lengths sum to exactly 1024. `run_len ≥ 1`.

**`DELTA_RLE`** — decorrelate, then run-length. `predictor`: `1` sub-left · `2` sub-up · `3` sub-avg(left,up)
· `4` paeth. For each pixel, residual channel = `(value − predicted) mod 256`, where the predictor reads
already-reconstructed neighbors (left/up); out-of-tile neighbors are `0`. The residual pixels are then encoded
with the `RLE` scheme. A linear gradient collapses to near-constant residuals → one long run. Decode:
RLE-decode 1024 residual pixels, then un-predict in raster order.

**`INDEXED`** — `color_count ∈ 1..=1024`; `bpp = max(1, ceil(log2(color_count)))`; 1024 indices packed
MSB-first in raster order into `ceil(1024 * bpp / 8)` bytes. A 32×32 tile is a small window on any image, so
local color counts stay low even in globally many-color (gradient/alpha) documents — this is why indexing is
viable *per-tile* even though a *global* palette is not (Appendix A).

**Selection is an encoder decision.** A compact encoder computes candidate encodings and stores the smallest
(RAW as the floor). Further whole-dictionary entropy coding is handled by the optional `transform` (§8/§19),
not per tile.

---

## 10. Chunk: `FRMS` (frames, layers, tile-ref grids)

Frame/layer structure plus each layer's sparse tile-ref grid.

Payload:

| Type | Field | Notes |
|------|-------|-------|
| `u8` | `transform` | `0` none · `1` deflate (§19) |
| `u32` | `uncompressed_len` | only if `transform == 1` |
| … | `stream` | below |

Stream:

```
varint frame_count                     // MUST equal HEAD.frame_count
repeat frame_count times:
    u32     frame_id                   // opaque, preserved across save/load
    u32     duration_us
    u16     active_layer
    u16     layer_count                // 1..=64
    repeat layer_count times:
        u32     layer_id               // opaque
        u16     name_len
        u8[name_len] name              // UTF-8
        u8      flags                  // bit0 visible · bit1 locked
        u8      opacity                // 0..=255
        u8      blend                  // 0 Normal (others reserved)
        // tile-ref grid: exactly tiles_x*tiles_y cells, row-major, run-length encoded:
        repeat until (tiles_x*tiles_y) cells emitted:
            varint  run_len            // ≥ 1
            varint  tile_index         // 0 = transparent; else index into TILE
```

The ref-grid run-length absorbs the large transparent gutter and any flat empty regions. `tile_index` MUST be
`0` or `≤ tile_count`.

---

## 11. Chunk: `UPAL` (user palettes)

Named swatch sets the artist curates. **Distinct from compression** — a palette may contain colors not
currently used and omit colors that are. Uncompressed payload:

```
varint palette_count
repeat palette_count times:
    u16          name_len
    u8[name_len] name          // UTF-8
    u16          color_count
    rgba8[color_count] colors  // straight RGBA
```

`HEAD.active_palette` indexes this list.

---

## 12. Chunk: `SELC` (selection)

Optional 1-bit selection mask over the **persisted storage** area, for crash-recovery continuity.

| Type | Field | Notes |
|------|-------|-------|
| `u16` | `mask_w` | persisted storage width, px |
| `u16` | `mask_h` | persisted storage height, px |
| `u32` | `word_count` | number of `u64` words |
| `u64[word_count]` | `bits` | row-major, LE, bit *n* = pixel *n* |

On load, if `(mask_w, mask_h)` does not match the reconstructed runtime storage area, the selection is
**dropped** (not an error).

---

## 13. Chunks: `THMB`, `META`

**`THMB`** — optional preview for the project browser.

| Type | Field | Notes |
|------|-------|-------|
| `u16` | `tw` | thumbnail width |
| `u16` | `th` | thumbnail height |
| `u8` | `codec` | `0` RAW · `1` RLE (over `tw*th` straight-RGBA pixels) |
| `…` | `payload` | per codec |

**`META`** — optional freeform key/value metadata (e.g. `title`, `author`, `created_us`, `modified_us`,
`app_version`). Values are opaque bytes; unknown keys are preserved/ignored.

```
varint entry_count
repeat entry_count times:
    u16          key_len
    u8[key_len]  key      // UTF-8
    u32          val_len
    u8[val_len]  val
```

---

## 14. Chunk: `INTG` (integrity)

MUST be the last chunk. Detects truncation/corruption (a crash mid-autosave, a bad copy).

| Type | Field | Notes |
|------|-------|-------|
| `u32` | `crc32c` | CRC-32C (Castagnoli) over bytes `[0 .. start_of_INTG_chunk)` |

The CRC covers the signature and every preceding chunk (including their headers), up to but not including this
`INTG` chunk. On load, a mismatch yields a distinct `Incomplete`/`Corrupt` error so the caller (e.g.
autosave-recovery) can fall back to a previous good save rather than loading garbage.

---

## 15. Encoder modes (fast vs compact) & verify-on-encode

There is **one format** and **two encoder effort levels**. The mode affects only encoder effort, never the
grammar; both modes produce valid v5 files read by the same decoder.

**Fast mode — autosave (latency-optimized).** Target: the 5-second, hash-coalesced autosave and the
dispose/flush path.
- `transform = none` on all chunks (no DEFLATE).
- Tile codec limited to `RAW`/`RLE` (cheap, no predictor/index search).
- Dedup optional or incremental.
- Persist the full runtime gutter.
- Still writes a valid `INTG`.

**Compact mode — explicit user save / export (size-optimized).** Target: File → Save and "Post to Club" export
of the source document.
- Full document-global content-addressed **tile dedup**.
- Full per-tile codec search over `{RAW, RLE, DELTA_RLE, INDEXED}`, choosing the smallest (RAW floor ⇒ never
  inflates).
- Optional **DEFLATE** `transform` on `TILE` and `FRMS` (§19), gated by measurement (§20).
- MAY shrink the persisted gutter to `bbox(non-empty tiles) ∪ canvas` (record the actual margins in `HEAD`).
- **Verify-on-encode (REQUIRED).** After encoding, decode the produced bytes and assert a pixel-identical
  round-trip (document content hash). On any mismatch, fall back the offending tile(s) to `RAW` and re-verify.
  This guarantees the user's explicit save is never silently corrupted, regardless of codec bugs or edge cases
  (e.g. RGB under `alpha = 0`).

---

## 16. Decoder / load path

The decoder is mode-agnostic and linear:

1. Verify signature; require `format_version == 5` (else `UnsupportedVersion`).
2. Verify `INTG` CRC over the file body (else `Incomplete`/`Corrupt`; caller may fall back).
3. Parse `HEAD` (must be first). Walk chunks; unknown critical → error, unknown ancillary → skip; reject
   duplicate criticals.
4. Decode `TILE` (inflate if `transform == 1`) into a vector of `Arc<Tile>`; index `0` is a single shared
   transparent `Arc`.
5. For each layer in `FRMS`, expand the run-length tile-ref grid into a buffer whose cells reference the
   **same `Arc<Tile>`** for identical indices. This **restores copy-on-write sharing in RAM** — identical
   tiles are deduplicated in memory on load, not just on disk. Subsequent edits COW via `Arc::make_mut`.
6. Map the persisted storage area onto the engine's runtime storage area by aligning canvas origins
   (re-expanding the gutter when the persisted gutter is smaller than runtime).
7. If `SELC` is present and its dimensions match the runtime storage area, apply it; otherwise drop it.

---

## 17. Determinism contract

- Pixels are 8-bit **straight** RGBA, sRGB; out-of-bounds tile pixels are canonically `(0,0,0,0)`. All engine
  color math remains integer-exact, so decoded buffers are byte-identical across platforms and goldens never
  fork.
- **Correctness is pixel round-trip, not byte reproduction.** The gate is the existing content-hash /
  `assert.roundtrip` check: `decode(encode(doc)) ≡ doc`. Encoders SHOULD be deterministic (same document +
  mode ⇒ same bytes) for reproducibility, but this is not required for correctness — freeing encoders to
  improve over time without test churn.
- Content-addressing for dedup uses the engine's own hash and never appears in the file.

---

## 18. Versioning & extensibility

- Exactly one supported version (`5`); the reader rejects anything else. No migration ladder.
- **Additive evolution without a version bump:** add a new **ancillary** chunk (older readers skip it), or a
  new **tile codec** in reserved IDs `4..=15` (only newer files that use it require a newer reader; the file
  still parses structurally).
- A `format_version` bump is reserved for changes that break **critical** parsing (signature, chunk framing,
  or a `HEAD`/`TILE`/`FRMS` grammar change).

---

## 19. Engine dependency boundary

- **Engine (`crates/engine`, zero-dependency, `#![forbid(unsafe_code)]`) owns the entire persistence path:**
  the container, chunk framing, all four tile codecs (`RAW`/`RLE`/`DELTA_RLE`/`INDEXED`), content-addressed
  dedup, varint, and CRC-32C. All of this is pure-Rust with **no** third-party crate — it builds fast, cross-
  compiles to Android trivially, and never breaks on a transitive dependency.
- **DEFLATE is the single sanctioned optional dependency** (the `transform` field of §8/§10). Recommended
  implementation: **`miniz_oxide`** — pure-Rust, no `build.rs`, no C, Android-clean, the same inflate/deflate
  that backs PNG. **Adoption is gated on G1 (§20).**
  - *If adopted:* it lives **in the engine** behind the `transform` flag, so there remains exactly **one read
    path** (the engine can always inflate what it wrote, and the `mkpx` CLI harness keeps validating compact
    files via `assert.roundtrip`). This is the one, deliberate, bounded exception to the engine's zero-
    dependency rule.
  - *If the zero-dependency line is held strictly instead:* DEFLATE moves to the `ffi`/`codec` layer, and the
    `cli` crate gains that layer so the harness can still round-trip compressed files.
- **No WebP, no `image`, no `libwebp`/`image-webp`, no C toolchain** anywhere in this path (Appendix A).

---

## 20. Validation & measurement gates

Three knobs are intentionally left to data. All are decided with one `mkpx`-harness probe over a shared corpus
of representative real documents (flat sprites, gradient/dodge-burn art, multi-frame animations, multi-layer
art). **None affect the decoder** — every setting still produces a valid v5 file.

- **G1 — Does DEFLATE earn the dependency?** Compare compact-mode size *with* vs *without* the DEFLATE
  `transform`, on top of dedup + `DELTA_RLE`. Adopt `miniz_oxide` only if the marginal reduction justifies the
  (small, pure-Rust) dependency; otherwise ship dedup + per-tile codecs alone, fully dependency-free.
- **G2 — Codec menu tuning.** Measure per-tile codec selection frequency and total bytes across the corpus.
  Prune codecs never chosen and/or add predictors (e.g. more paeth-like modes) only if data supports them.
- **G3 — Gutter trimming.** Quantify the savings of compact-mode gutter shrink (§5/§15); keep it if material.

**Expected outcome (to be confirmed, not assumed):** deduplication dominates on animated/layered work;
`DELTA_RLE` carries gradient-heavy art; `INDEXED` wins only on the subset of busy low-color tiles; `RAW`/`RLE`
handle the rest. WebP is not required to beat the legacy format.

---

## Appendix A — Decided-against alternatives

Terse conclusions (rationale only, no history):

- **Global color indexing / a document-wide palette** — *rejected.* Makapix supports gradients and stores
  32-bit RGBA; gradients and alpha falloffs routinely exceed 256 distinct colors, so a global palette hits a
  hard cliff and adds table overhead for exactly the documents with the most pixel data. Indexing is retained
  only as an **opportunistic per-tile** codec (§9), where local color counts stay low.
- **Lossless WebP (VP8L)** — *not adopted.* The efficient encoder is Google's native **libwebp** (C compiler +
  `bindgen`/`libclang` + Android NDK cross-compilation), contrary to the pure-Rust, dependency-free build. The
  pure-Rust `image-webp` encoder lacks the palette and LZ77 transforms and is roughly PNG-level, not the
  "efficient WebP" people cite. Moreover WebP is a **whole-image** codec: it cannot compose with **tile-level
  deduplication** — the dominant redundancy in animation — because flattening a buffer to feed the encoder
  re-materializes the duplicate tiles. May return *only* as an optional per-tile/per-buffer codec ID if a
  measured case ever justifies it.
- **Per-tile WebP** — *rejected.* A 32×32 tile is too small for VP8L's machinery and pays ~20–25 bytes of RIFF
  container overhead per tile.
- **`zstd` / other native compressors** — *rejected for the shipping path.* No pure-Rust encoder exists;
  native builds reintroduce the C/NDK toolchain. DEFLATE (`miniz_oxide`) is the pure-Rust entropy option.
- **Legacy v1–v4 read support** — *dropped.* The app is pre-distribution; a single read path is simpler and
  the new reader cleanly rejects `format_version < 5`.
- **Zip-of-PNGs container** — *rejected* for working state: per-buffer PNG is heavier than tiled storage, it
  loses tile sparsity and dedup, a max document would need tens of thousands of archive entries, and it adds a
  zip dependency. (A separate portable export format is a different, out-of-scope concern.)

---

## Appendix B — Deltas from legacy v1–v4 (for implementers)

| Legacy (v1–v4) | Version 5 |
|----------------|-----------|
| Positional grammar; encoding implied by file version | Typed-chunk container; explicit per-tile codec IDs + reserved IDs |
| Per-tile RLE the only codec (inflates on gradients) | Per-tile codec menu `{RAW, RLE, DELTA_RLE, INDEXED}` with a RAW floor + spatial predictor |
| Every (frame×layer) tile stored independently | Document-global content-addressed **tile dictionary** + ref grids (dedup) |
| 32-byte blake3 footer, **written but never validated** | Validated **CRC-32C** `INTG` chunk (detects truncation/corruption) |
| Single save path | **Fast** (autosave) and **compact** (user-save) encoder modes; one format |
| Gutter stored as storage-sized tiles | Explicit persisted gutter margins in `HEAD`; compact mode may trim empties |
| No in-RAM dedup on load | Load restores shared `Arc<Tile>` for identical tiles (COW sharing in memory) |

---

*End of specification.*
