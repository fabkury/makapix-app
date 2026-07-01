# `.mkpx` Binary Format — Specification **v9** (synthesis)

> **Status.** A complete, implementable, byte-level specification for the Makapix Editor's native
> document format. **Clean break, no backward compatibility** — the app has barely shipped, so a v9
> reader reads only v9. This spec is the *synthesis* of three independent clean-sheet proposals
> (v6, v7, v8): it keeps every idea all three converged on, adopts the single best variant of each
> point where they differed, and **deliberately cuts the redundant machinery** each one carried
> (see §14, the over-engineering watch). It does **not** draw on v5, which was out of scope.
>
> **Ground truth.** Built against the real engine: `crates/engine/src/document.rs` (model),
> `buffer.rs` (32×32 tiled COW buffer), `color.rs` (`Rgba8`), `selection.rs` (1-bit `Mask`),
> `util.rs` (FNV-128 `content_hash`), and the v4 audit `current-format-v4-introspection.md`.
>
> **One-line pitch.** A CRC-checked, PNG-style TLV container with **two content-addressed dedup
> pools** — unique 32×32 *tiles* and unique per-layer *cels* — that put the engine's in-RAM
> `Arc`-shared copy-on-write onto disk, a **sparse** tile grid that makes the 9× gutter free, a
> per-tile **smallest-wins codec** (`RAW`/`RLE`/`INDEXED`) that never expands and crushes dithering,
> and **two mandatory, actually-verified** integrity layers — all pure-Rust, integer-exact, and
> byte-deterministic. The same tile granularity that shrinks files also makes the Editor's
> 10 s-debounced **autosave** cheap: a save re-encodes only the tiles a stroke actually touched, not
> the whole document (§11).

---

## 1. Design goals (strict priority order)

1. **Determinism.** One document ⇒ exactly one byte sequence, on every platform, forever. Fixed
   little-endian, no floats in the persisted path, canonical varints, deterministic pool ordering
   and a deterministic per-tile codec choice. Goldens never fork. This constrains everything below
   (e.g. it *forces* timestamps out of the deterministic core, §7).
2. **Panic-free, hostile-input-safe loading.** Every read bounds-checked; every count capped; every
   allocation bounded by what the remaining input could actually supply; every failure a typed
   error, never a panic, never an unbounded loop or allocation.
3. **Dependency-free deterministic core; pure-Rust deps allowed at the periphery.** The engine's
   `.mkpx` codec has **zero runtime dependencies** and is `#![forbid(unsafe_code)]`-compatible: it
   ships its own varint, tile codecs, and CRC-32. This is *scoped, not dogmatic* — the ban exists to
   protect the three properties a dependency most easily breaks here: **cross-compilation** (Windows
   DLL + Android `arm64`/`arm32`, iOS later — no native/`-sys` crate in the core, ever),
   **determinism** (byte-identical goldens — no SIMD/float/intrinsic-fallback surprises), and
   **memory safety on untrusted input** (`forbid(unsafe)` on the hostile-input loader). Following the
   existing `image`-in-`crates/codec` model, **pure-Rust dependencies are welcome at the periphery**,
   and **dev-dependencies that don't ship** — fuzzers (`proptest`/`arbitrary`/`cargo-fuzz`),
   benchmarks (`criterion`) — are unconstrained and encouraged for hardening the loader and the
   autosave encoder. **No compression library in the core**; §14 states the one sanctioned escape hatch.
4. **Kill v4's two structural redundancies.** (a) the **9× gutter tax** — v4 writes a present-flag
   byte for every storage tile, ~8/9 of them empty gutter — and (b) **lost on-disk COW** — v4
   re-serializes identical tiles once per frame/layer though they are one `Arc` in RAM. v9's sparse
   grid makes empty tiles free, and its two dedup pools store repeated pixels *and* repeated layouts
   once.
5. **Cheap, incremental writes (autosave-first).** The Editor autosaves the document on every change,
   debounced by 10 s, so `.mkpx` is **written far more often than it is read** — typically after a
   stroke that dirtied only a handful of tiles. A save after a small edit must cost work
   **proportional to what changed**, not to the whole document, and must never jank the editor. The
   tile-granular pools make this achievable with a pure-memoization writer (§11.2) that stays
   byte-identical to a from-scratch canonical encode, so autosave and manual save share one code path.
6. **Never expand.** A `RAW` ceiling per tile bounds the worst case; the codec chooser picks the
   smallest encoding per tile, so v4's ~1.5× RLE blow-up on dithered art becomes a shrink.
7. **Real integrity + forward-compat.** Per-chunk CRC-32 *and* a verified content-hash close v4's
   write-but-never-read footer. A true chunk container lets readers skip data they don't understand
   (ancillary) or correctly refuse data they must understand but can't (critical).
8. **Self-describing when wanted.** Optional in-file title/author/timestamps/thumbnail so a `.mkpx`
   can travel without its sidecar directory — without those volatile parts polluting the
   deterministic core or the content hash.

**Non-goals.** Not a transport/publish format (publishing still rasterizes to PNG/GIF). Not an
undo/action log. Not lossy. No random-access / partial-frame / streaming load — the whole-file model
meets the < 300 ms budget for a 64-frame / 8-layer / 128×128 document with wide margin.

---

## 2. Container structure and framing

A v9 file is an **8-byte signature**, then a sequence of **chunks**, terminated by `MEND`.
All multi-byte fixed-width integers are **little-endian**. Variable-length integers are canonical
unsigned LEB128 (§2.5).

### 2.1 Signature (8 bytes, not a chunk)

```
0x89  'M'(0x4D)  'K'(0x4B)  'P'(0x50)  'X'(0x58)  0x0D  0x0A  0x1A
```

PNG-style, to catch transport hazards: leading `0x89` (high bit set → detects 7-bit/text-mode
stripping); `0x0D 0x0A` (detects CRLF↔LF translation); `0x1A` (DOS EOF → detects naive text-mode
truncation). It is also **distinct from every prior Makapix format** (which began with ASCII
`MKPX`), so old files fail the magic check instead of mis-parsing. Mismatch ⇒ `BadMagic`.

### 2.2 Chunk framing

Every chunk, in order:

| Field | Type | Bytes | Notes |
|---|---|---|---|
| `length` | `u32` LE | 4 | Byte length of `data` only (excludes `type` and `crc`). |
| `type` | `[u8;4]` | 4 | Four ASCII letters identifying the chunk. |
| `data` | `[u8;length]` | `length` | Chunk payload (§3). May be empty. |
| `crc` | `u32` LE | 4 | CRC-32/IEEE over `type ++ data` (§8.1). |

To advance past any chunk a reader needs only `length` (read `4 + 4 + length + 4`). It requires
`length + 8 ≤ bytes_remaining` else `Truncated`, recomputes the CRC over `type ++ data` and requires
equality else `BadCrc(type)`, **then** dispatches on `type`. CRC-before-trust means a corrupted
length/count is caught before it is used.

### 2.3 Critical vs. ancillary — skipping unknown data

Criticality is the **case of the first byte of `type`** (PNG's convention — no separate flag byte):

- **Uppercase `A`–`Z` ⇒ critical.** A reader that does not recognize a critical `type` MUST fail
  with `UnknownCriticalChunk(type)` — it cannot faithfully load the document without it.
- **Lowercase `a`–`z` ⇒ ancillary.** A reader that does not recognize an ancillary `type` MUST skip
  it (it already has `length`) and continue. Ancillary chunks never carry data the artwork cannot be
  reconstructed without.

This makes "ignore unknown chunks" a *real, enforced* guarantee (v4's was incidental — its reader
merely stopped early). New optional sections ⇒ new ancillary chunks, added freely. New load-bearing
sections ⇒ new critical chunks, which old readers correctly refuse.

### 2.4 Defined chunks and canonical order

| Type | Crit? | Count | Purpose | § |
|---|---|---|---|---|
| `MHDR` | crit | 1, first | Header: version, canvas, gutter mode, loop, counts, content hash. | 3.1 |
| `PLTS` | crit | 1 | Palette table. | 3.2 |
| `TILS` | crit | 1 | Deduplicated **tile** pool (unique 32×32 tiles, encoded once). | 3.3 |
| `CELS` | crit | 1 | Deduplicated **cel** pool (unique per-layer sparse tile-maps). | 3.4 |
| `FRMS` | crit | 1 | Frames → layers (attributes + a cel reference). | 3.5 |
| `msel` | anc | 0–1 | Selection mask (bbox-packed). | 3.6 |
| `meta` | anc | 0–1 | Metadata key/value map. | 3.7 |
| `thmb` | anc | 0–1 | Embedded thumbnail image. | 3.7 |
| `MEND` | crit | 1, last | End marker (empty). | 3.8 |

**Canonical write order** (the deterministic engine core always emits): `MHDR, PLTS, TILS, CELS,
FRMS [, msel] , MEND`. When a self-contained file is wanted, the shell/codec emits `meta`/`thmb`
after `FRMS` and before `MEND` **in the same single write** (never by rewriting the engine's core).

**Reader rules** (single forward pass): `MHDR` is the first chunk; the critical chunks appear
exactly once each in the relative order `MHDR → PLTS → TILS → CELS → FRMS → MEND` (so every
reference resolves in one pass); ancillary chunks may appear anywhere between `MHDR` and `MEND`, at
most once each; the input MUST end **immediately** after `MEND`'s CRC (rejects a truncated tail and
trailing garbage). Any violation ⇒ `Corrupt`.

### 2.5 Primitives

- **`varint`** — canonical unsigned LEB128, low 7-bit group first, `0x80` = "more follows". Writers
  emit the **minimal** length. Readers reject an encoding longer than **5 bytes** for a `u32` field
  (or that overflows the target width), or with a non-minimal trailing zero group ⇒
  `Corrupt("bad varint")`. Used for all counts and indices. Fixed-width LE is used for ids, sizes,
  colors, durations, and the hash (the spec names which).
- **`str`** — `varint` byte-length `n` (≤ `MAX_STR = 4096`, else `Corrupt`) then `n` UTF-8 bytes,
  decoded lossily (invalid → U+FFFD, matching the engine and keeping the loader infallible on
  content; byte corruption is already caught by the chunk CRC). `n` is additionally bounded by the
  enclosing chunk.
- **`rgba`** — 4 bytes `r, g, b, a`, straight (non-premultiplied), matching `Rgba8`.

---

## 3. Section byte layouts

### 3.1 `MHDR` — header (fixed 33-byte payload)

| Off | Field | Type | Notes |
|---|---|---|---|
| 0 | `format_version` | `u16` | `= 9`. Else `UnsupportedVersion`. |
| 2 | `canvas_w` | `u16` | 8..=256, else `Corrupt("canvas size")`. |
| 4 | `canvas_h` | `u16` | 8..=256. |
| 6 | `tile_log2` | `u8` | Tile edge = `1 << tile_log2`. MUST be `5` (32) in v9; else `UnsupportedTileSize`. Stored for self-description / future flexibility. |
| 7 | `gutter_mode` | `u8` | `0` = none (`storage = canvas`); `1` = symmetric full-canvas gutter (`storage = 3·canvas`, the engine's current policy). Else `Corrupt`. Geometry is **derived from this + canvas**, never stored as raw dims (so it cannot desync — the engine invariant). |
| 8 | `loop_mode` | `u8` | `0`=Loop, `1`=Once, `2`=PingPong; any other value → Loop (tolerant, matching the engine). |
| 9 | `active_frame` | `u32` | Clamped to `frame_count-1` on load. |
| 13 | `active_palette` | `u16` | Clamped to `palette_count-1` on load. |
| 15 | `frame_count` | `u16` | 1..=1024 (`MAX_FRAMES`), else `Corrupt`. |
| 17 | `content_hash` | `u128` | `Document::content_hash()`, LE. **Verified after load** (§3.1.1). |

**Derived geometry** (computed once, then the modulus for every grid index):
```
storage_w = gutter_mode==1 ? 3*canvas_w : canvas_w      (same for _h)
tiles_x   = ceil(storage_w / 32)
tiles_y   = ceil(storage_h / 32)
cells     = tiles_x * tiles_y            // 256² canvas → 768² storage → 24×24 = 576
```
The loader validates `storage_w, storage_h ≤ 768`, bounding `cells ≤ 576`.

#### 3.1.1 The content hash is *used*

After the document is fully reconstructed, the reader recomputes `Document::content_hash()` and
compares to `MHDR.content_hash`; mismatch ⇒ `Corrupt("content hash mismatch")`. This is the
**semantic** integrity layer (did we rebuild the same artwork?), complementing the per-chunk CRC
(did the bytes survive the channel?). It closes v4's write-but-never-read footer. The hash covers
canvas size + per-frame duration + per-layer name/visible/locked/opacity + present-tile pixels; it
**excludes** selection, palettes, ids, loop mode, and all ancillary chunks — matching the engine's
existing `content_hash`, so thumbnail-cache/golden keys are unchanged and a selection or metadata
edit never churns them. Because the hash is derived from the in-RAM `Document` (not the file bytes),
the writer computes it up front and stores it in the first chunk with no ordering hazard.

### 3.2 `PLTS` — palettes

```
palette_count : varint                 (0..=256; else Corrupt)
repeat palette_count:
    name        : str
    color_count : varint               (0..=65536; else Corrupt)
    colors      : rgba × color_count
```
If `palette_count == 0`, the loader injects the built-in default 16-colour ramp
(`Palette::default_palette`) and clamps `active_palette` to 0 — matching engine behaviour.

### 3.3 `TILS` — the deduplicated tile pool

Every **unique present tile** in the whole document (across all frames and layers) is stored
**exactly once**, in **first-occurrence order** under the canonical traversal (frame 0→N, within a
frame layer 0→M, within a layer cell 0→cells-1). Deduplication is by **raw 1024-pixel content**
(hash-bucketed, then confirmed by full byte compare — no false merge on a hash collision). Absent
(fully-transparent) tiles are **never** pooled or referenced — sparsity is by omission.

```
tile_count : varint                    (0..=MAX_POOL_TILES = 1<<24; §8 bounds the allocation)
repeat tile_count:
    method  : u8                       (0=RAW, 1=RLE, 2=INDEXED; unknown ⇒ Corrupt)
    payload : method-specific, self-delimiting (§3.3.1)
```

Entries are **not** length-prefixed: each codec is exactly self-delimiting and the reader decodes
sequentially, bounds-checking every byte (the chunk CRC already frames the whole pool). Tiles are
referenced elsewhere by 0-based pool index. A tile is 1024 pixels in **local row-major order**
(`local = y*32 + x`), straight `Rgba8`.

The writer computes the encoded size of every *applicable* method and picks the **smallest**; ties
break to the **lowest method id**. Pure integer logic ⇒ identical choice on every platform ⇒
byte-identical goldens.

#### 3.3.1 Per-tile codecs

**`0x00 RAW` (the ceiling).** 4096 bytes, `rgba × 1024` row-major. Always valid; guarantees no tile
costs more than `1 + 4096` bytes — fixes v4's worst-case RLE expansion.

**`0x01 RLE` (run coherence).** `(run: varint(1..=1024), rgba)` pairs over the row-major scan until
`Σ run == 1024`. Reader rejects `run == 0` or `Σ run > 1024` ⇒ `Corrupt("bad rle")`. Varint runs
make short runs cheaper than v4's fixed `u16`.

**`0x02 INDEXED` (colour-count coherence — the pixel-art workhorse; subsumes "solid").** For tiles
with ≤ 256 distinct colours — the overwhelming case, and exactly where RLE loses to dithering.
```
count_minus_1 : u8                     (ncolors = count_minus_1 + 1, so 1..=256)
table         : rgba × ncolors         (the tile's distinct colours in first-appearance row-major order)
indices       : ceil(1024 * k / 8) bytes, k-bit indices, row-major, packed LSB-first, low index first
                where k = bits_needed(ncolors) = (ncolors<=1 ? 0 : ceil_log2(ncolors)), k ∈ 0..=8 (derived, not stored)
```
`k` is derived from `ncolors` (full granularity 0..8, not rounded to powers of two — a 5–8-colour
tile packs at 3 bpp, a 17–32-colour tile at 5 bpp, etc.). For `k = 0` (a **solid** tile, `ncolors
== 1`) there are **zero** index bytes ⇒ 5 bytes total, so `INDEXED` cleanly absorbs the old `SOLID`
method (including a materialised-but-transparent tile, `INDEXED ncolors=1 rgba=0000`, preserving
present-vs-absent fidelity through the round-trip and the content-hash check). The reader derives
`k`, reads exactly `ceil(1024*k/8)` index bytes, and validates every unpacked index `< ncolors` ⇒
else `Corrupt("index")`. Sizes: 2-colour tile `1+8+128 = 137 B`; 16-colour `1+64+512 = 577 B`;
256-colour `1+1024+1024 = 2049 B` — all under `RAW`.

### 3.4 `CELS` — the deduplicated cel pool

A **cel** is one layer's pixel content: a sparse map from storage-tile-grid index → tile-pool index.
Cels are themselves pooled and deduplicated, so a layer whose pixels are identical across many frames
(a static background, a held key frame) is stored **once** and referenced many times. Tile dedup
(§3.3) removes duplicate *pixels*; cel dedup removes duplicate *layouts*. Together they collapse
animation redundancy — the reason this matters at up to **1024 frames**: a 1024-frame hold of a
16-tile background costs one cel plus 1024 tiny cel-references, not 1024 repeated reference lists.

```
cel_count : varint                     (0..=MAX_CELS = 1<<20)
repeat cel_count:
    present_count : varint             (0..=cells)
    repeat present_count:
        gap      : varint              (grid-index delta; see below)
        tile_ref : varint              (< tile_count, index into TILS)
```

**Grid indices** are emitted **strictly ascending** and **delta-coded** to stay 1 byte for clustered
art: start `prev = -1`; each entry `grid_index = prev + 1 + gap`, then `prev = grid_index`. The
reader validates `grid_index < cells`, strict ascent, and `tile_ref < tile_count` ⇒ else
`Corrupt("cel")`. `present_count == 0` is a valid **empty cel** (a fully transparent layer); all such
layers dedup to it. Cels are referenced by 0-based index from `FRMS`.

**Reconstruction restores COW.** The reader materialises each `TILS` entry into exactly **one**
`Arc<Tile>`. For each cel it builds a prototype storage-sized `RgbaBuffer` placing that shared `Arc`
at each present grid slot. A layer referencing the cel takes a cheap clone of the prototype (a
`Vec<Option<Arc<Tile>>>` clone = `Arc` clones only). So every layer that shared a tile in the
authored document **shares the same `Arc<Tile>` again after load** — the on-disk pools map 1:1 onto
in-RAM COW, so loading *rebuilds* the memory sharing the editor relies on instead of exploding it,
and peak load memory is **lower** than v4's (which mints a private copy per occurrence).

### 3.5 `FRMS` — frames and layers

```
frame_count : varint                   (1..=1024; else Corrupt — a document always has ≥1 frame)
repeat frame_count:
    frame_id     : u32                 (stable identity)
    duration_us  : u32                 (clamped to 16_667..=1_000_000 on load)
    active_layer : varint              (clamped to layer_count-1 on load)
    layer_count  : varint              (1..=64; else Corrupt)
    repeat layer_count:
        layer_id : u32                 (stable identity)
        name     : str
        flags    : u8                  (bit0 = visible, bit1 = locked; other bits reserved 0)
        opacity  : u8
        blend    : u8                  (0 = Normal; unknown ⇒ Normal, tolerant/reserved)
        cel_ref  : varint              (< cel_count, index into CELS)
```
`frame_id`/`layer_id` are persisted so stable identities survive save/load. On load the id
generators are seeded to `max_seen_id + 1` **directly** (`IdGen::starting_at`), never by a warm-up
loop — a crafted `0xFFFFFFFF` cannot spin the loader (v4's [F-2] hardening, preserved). Ids do not
participate in `content_hash`.

### 3.6 `msel` — selection (ancillary, bbox-packed)

The engine's selection is a **storage-sized** 1-bit `Mask`, persisted for crash recovery. Ancillary
because it is editor state, not artwork (a reader that skips it merely loses the selection). It is
**not** folded into the content hash, so a selection change never churns caches/goldens. The combine
*mode* (Replace/Add/…) is transient tool state and is **not** persisted.

```
tag : u8            (0 = RECT, 1 = BITS, 2 = EMPTY)
  EMPTY (2): no further bytes. Reconstructs an all-zero storage-sized mask — distinct from "no
             selection" (which writes no msel chunk at all).
  RECT  (0): bbox_x, bbox_y, bbox_w, bbox_h : u16 (storage coords). Every pixel in the bbox is set.
             The common marquee / select-all / wand-over-a-rect case → 9 bytes.
  BITS  (1): bbox_x, bbox_y, bbox_w, bbox_h : u16, then ceil(bbox_w*bbox_h / 8) packed bytes:
             the bbox's bits row-major, LSB-first (bit k = the k-th pixel in bbox scan order).
```
The writer chooses `EMPTY` if no bits are set, `RECT` if the mask is exactly its bounding box fully
set, else `BITS`. Storing only the **bounding box** (not the full 768×768 plane) is the size win: a
rectangular selection over a 128² canvas costs 9 bytes instead of v4's fixed ~73 KiB word plane; an
arbitrary shape pays only for its bbox. On load, a bbox outside the derived storage size (a stale or
crafted chunk) ⇒ the selection is **dropped** and the document still loads (v4's tolerant policy);
the packed-byte count is bounded by `MAX_SEL_BYTES = ceil(768*768/8) = 73_728`.

### 3.7 `meta` and `thmb` — optional identity (ancillary; outside the deterministic core, §9)

**`meta`** — a small typed key/value map so a `.mkpx` can carry its own identity:
```
entry_count : varint                   (≤ 256)
repeat entry_count:
    key        : str                   (e.g. "title","author","created_unix","modified_unix","software")
    value_type : u8                    (0 = str, 1 = u64 LE, 2 = i64 LE, 3 = bytes(varint len))
    value      : per value_type
```
Unknown keys are ignored semantically (preserved on read). **`thmb`** — a preview produced by the
`codec` crate (PNG) or the shell, never by the dependency-free engine: `format : u8` (0 = PNG blob;
1 = raw straight-RGBA prefixed with `w:u16, h:u16`), then image bytes to the end of the chunk, with
`byte_len` bounded by `THUMB_MAX = 1 MiB`.

### 3.8 `MEND` — end marker

`length = 0`, empty data, CRC over the 4 type bytes. The input MUST end immediately after its CRC
(§2.4) — a definite "file is complete" signal v4 never had.

---

## 4. Pixel / tile encoding — summary

- **Sparsity by omission.** Only present tiles are listed (via cels); an empty tile — including every
  empty gutter tile — costs **0 bytes**, deleting v4's per-tile present-flag tax that scaled 9× with
  the gutter.
- **Two-level dedup (on-disk COW).** `TILS` stores each unique tile once; `CELS` stores each unique
  layer-layout once. A static background across N frames → a handful of pool tiles + one cel + N
  cheap cel-refs. Repeated motifs at different grid positions dedup too (which in-RAM COW cannot,
  since it is per-buffer-slot).
- **Smallest-wins per-tile codec.** `RAW` / `RLE` / `INDEXED`, deterministic tie-break, `INDEXED`
  beating RLE on dithered/noisy tiles and absorbing solids, `RAW` capping the worst case. Indexing is
  **per-tile and local** (a table derived from the tile's own pixels), so it is lossless and adaptive
  for *any* RGBA — imported photos, gradients, HSV-shifted pixels all round-trip. It is **not** tied
  to the document palettes (those are swatch lists, not a pixel constraint).

---

## 5. Gutter / storage vs. canvas

Only the **canvas** size and the **gutter policy** (`gutter_mode`) are stored; the **storage** area
(`3w × 3h` under mode 1), the tile grid, and the canvas origin are **re-derived** on load exactly as
the engine derives them from `Document::gutter_for` — never persisted as raw numbers, so they can
never desync from undo/redo (the load-bearing engine invariant). Present tiles **anywhere** in the
storage area — canvas *or* gutter — are serialized (moved-off-canvas pixels are real, recoverable
state); empty gutter tiles cost nothing (sparse grid). `gutter_mode` being an **enum** (not raw
dims) keeps the file self-describing *and* future-proof: a future "no gutter" export or a different
gutter policy is a new mode value, not a format break.

---

## 6. Selection

Covered byte-for-byte in §3.6: storage-sized, **bbox-relative** (`EMPTY`/`RECT`/`BITS`) so the common
cases are a handful of bytes and arbitrary shapes pay only their bounding box; round-trips `None` vs
`Some(empty)` vs rect vs arbitrary distinctly; dropped-not-fatal on a stale/out-of-range bbox;
excluded from the content hash; combine mode not persisted.

---

## 7. Metadata & the determinism boundary

There are two notions of "same", and the format keeps them cleanly separate:

1. **File-level byte-determinism (strong).** The engine's core writer — `MHDR, PLTS, TILS, CELS,
   FRMS [, msel], MEND` in canonical order, canonical varints, first-occurrence pool ordering,
   smallest-wins codec choice — produces **byte-identical** output for two structurally-equal
   documents. Goldens gate on this. It contains **no** timestamps, author, tool version, or
   thumbnail (all non-deterministic ⇒ would fork goldens).
2. **Artwork content-hash (the app's).** `Document::content_hash()` (§3.1.1), a subset used for
   thumbnail-cache keys, stored in `MHDR` and verified on load.

Identity (`meta`, `thmb`) is therefore **optional, ancillary, and written only by the shell/codec**
when a self-contained file is wanted — always skippable, never in the deterministic core. Best of
both: deterministic artwork bytes for CI, travel-anywhere self-description on demand.

---

## 8. Integrity, versioning, forward-compatibility

### 8.1 Integrity — two mandatory layers

1. **Byte integrity: per-chunk CRC-32/IEEE** (reflected polynomial `0xEDB88320`, init/xorout
   `0xFFFFFFFF` — the standard zlib/PNG CRC) over `type ++ data`, LE, **verified on every read**
   before the payload is trusted ⇒ `BadCrc(type)` on mismatch. Dependency-free (a 256-entry table
   built once, or a per-byte bitwise loop). Localizes corruption to a chunk.
2. **Semantic integrity: content-hash verification** (§3.1.1) after reconstruction ⇒ `Corrupt` on
   mismatch. A byte flip that somehow slips past a CRC, or a third-party writer bug, still cannot
   yield a silently-wrong document.

A single whole-file hash trailer (one of the three inputs proposed it) is **not** used — it is
redundant with per-chunk CRC + content-hash and would only re-checksum bytes already covered.

### 8.2 Versioning & forward-compat

- `format_version : u16 = 9` gates the reader; any other value ⇒ `UnsupportedVersion`. There is no
  in-engine migration (clean-break mandate); the distinct signature makes older files fail fast.
- **Growth without a version bump is the normal case**, handled by the chunk model: an unknown
  **ancillary** chunk is skipped by `length`; an unknown **critical** chunk is a hard refuse
  (`UnknownCriticalChunk`). Reserved header bits / `blend` / unknown `loop_mode` → writer 0, reader
  tolerant. New optional data ⇒ new ancillary chunk. A semantic change to pixels/frames/geometry ⇒
  a new critical chunk (old readers correctly refuse) and/or a `format_version` bump.

  *(No separate `min_reader_version` field: the critical-chunk-refuse rule already forces a safe
  refusal whenever a file uses a section an old reader can't understand — see §14.)*

---

## 9. Hardening against malicious / corrupt input

The loader returns `Result<Document, IoError>` and **never panics** (no unchecked indexing, no
`unwrap`, no unchecked arithmetic on file-derived values):

```rust
pub enum IoError {
    BadMagic,
    UnsupportedVersion(u16),
    UnsupportedTileSize(u8),
    UnknownCriticalChunk([u8; 4]),
    Truncated,
    BadCrc([u8; 4]),
    TooLarge(&'static str),
    Corrupt(&'static str),
}
```

Rules the reader enforces:

- **Bounds on every read.** No slice access without checking `remaining`; any `length`/`str`/`varint`
  /count that would read past end ⇒ `Truncated`.
- **Caps on every count** (violations ⇒ `Corrupt`/`TooLarge`):

  | Quantity | Cap | Source |
  |---|---|---|
  | `canvas_w/h` | 8..=256 | `Size::in_range` |
  | `storage_w/h` | ≤ 768 | canvas + full gutter |
  | `cells` | ≤ 576 | derived |
  | `frame_count` | 1..=1024 | `MAX_FRAMES` |
  | `layer_count` | 1..=64 | `MAX_LAYERS` |
  | `palette_count` | ≤ 256 | this spec |
  | `color_count` | ≤ 65536 | this spec |
  | `tile_count` | ≤ 1<<24 | `MAX_POOL_TILES` |
  | `cel_count` | ≤ 1<<20 | `MAX_CELS` (≥ frames·layers with headroom) |
  | `present_count` | ≤ cells | derived |
  | `str` length | ≤ 4096 | `MAX_STR` |
  | `msel` packed bytes | ≤ 73_728 | `MAX_SEL_BYTES` |
  | `thmb` byte_len | ≤ 1 MiB | `THUMB_MAX` |
  | `varint` | ≤ 5 bytes / fits u32 | canonical LEB128 |
  | any chunk `length` | ≤ bytes-remaining | framing |

- **Bounded allocation.** A declared count never sizes a `Vec::with_capacity` directly: reserve
  `min(count, remaining_bytes / MIN_ENTRY_BYTES)` where `MIN_ENTRY_BYTES` is the smallest possible
  per-item on-disk size (a pool tile ≥ 2 bytes, a cel reference ≥ 2 bytes). A crafted `tile_count =
  2^24` in a 40-byte file cannot force a giant allocation.
- **Every index domain-checked:** `tile_ref < tile_count`; `cel_ref < cel_count`; cel grid indices
  strictly ascending and `< cells`; `INDEXED` index `< ncolors`; `active_*` clamped; `duration_us`
  clamped.
- **Varints length/overflow-checked**, so a stream of `0x80` cannot loop or overflow.
- **Ids seeded, not looped** (`starting_at(max+1)`).
- **CRC + content-hash verified** — silent bit-flips are caught, not just structural violations.
- **Tolerant where the engine already is:** empty palette → default injected; stale selection bbox →
  dropped; unknown `blend`/`loop_mode`/reserved bits → mapped to defaults.

The Tier-1 round-trip gate holds: `load(save(doc))` yields a document with an equal `content_hash()`
(same tiles, presence set, palettes, durations, layer attributes, ordering).

---

## 10. Worked size examples (v9 vs. v4)

Chunk overhead = 12 bytes each (`length` 4 + `type` 4 + `crc` 4); signature = 8. Figures rounded; the
point is the ratio and *where the bytes go*.

### A. Empty 256×256 document (1 frame, 1 empty layer, default 16-colour palette)
Storage 768×768 → 576 tiles, all absent.

| Section | v9 |
|---|---|
| Signature + `MHDR` (33+12) | 53 |
| `PLTS` ("Default" + 16 rgba) | ≈ 86 |
| `TILS` (`tile_count = 0`) | 13 |
| `CELS` (one empty cel) | 14 |
| `FRMS` (1 frame, 1 layer "Layer 1") | ≈ 40 |
| `MEND` | 12 |
| **Total** | **≈ 218 B** |

**v4 ≈ 727 B**, dominated by 576 present-flag bytes for the empty gutter. **~3.3× smaller**, and the
gap widens with every added layer/frame (v4 adds 576 flag bytes each; v9 adds ~1).

### B. 64-frame 128×128 animation, one detailed **static** background + one small moving sprite
Storage 384×384 → 144 tiles; canvas = centre 4×4 = 16 tiles. Background identical in all 64 frames;
sprite touches a few unique tiles per frame.

- **Background:** 16 unique tiles → pooled **once** in `TILS`; its layout → **one** cel in `CELS`,
  referenced by all 64 frames' background layer. Cost ≈ (16 tiles × ~300 B) + one ~40 B cel + 64
  cel-refs ≈ **~5 KB total**, essentially independent of frame count.
- **Sprite:** ~64–256 unique small tiles pooled once; 64 one-tile cels.
- **v9 total ≈ 25–40 KB**, vs **v4 ≈ 280 KB** (which re-serializes the background every frame with no
  dedup): **~7–11× smaller**. At **1024 frames**, v4's static background alone would balloon ~16×
  while v9's stays ~5 KB — the cel pool is what keeps long holds flat.

### C. One noisy 128×128 frame fully covered by a 2-colour dither (RLE's worst case)
16 canvas tiles, each a 2-colour checkerboard.

- **v9 `INDEXED` (1 bpp):** `1+8+128 = 137 B`/tile; if the 16 tiles share the pattern they dedup to
  **one** pool tile ⇒ **~0.2 KB**, else ~2.2 KB.
- **v4 `RLE`:** every pixel breaks the run ⇒ 1024 runs × 6 B = 6144 B/tile ⇒ **≈ 98 KB** (RLE
  *expands* past raw).
- **~44× smaller** even without dedup; far more with it — the case v4 handles worst.

The three wins are orthogonal: **A** = sparse gutter, **B** = tile + cel dedup, **C** = indexed
codec. A typical multi-frame sprite benefits from all three at once.

---

## 11. Performance — loading and autosave writes

### 11.1 Load (informative)

Load is a single forward pass. Per chunk: a table-driven CRC over its bytes, then dispatch. Tile
decode is O(pixels), integer-only; each **unique** tile is decoded once and thereafter installed by
`Arc::clone`. For the 64f / 8l / 128² budget, the upper bound is ~8192 present-tile references over
≤ 8192 unique tiles ⇒ a few million pixels of integer work — comfortably under 300 ms, and less with
realistic dedup. The content-hash re-verification is one extra O(present-pixels) pass. Because
reconstruction shares one `Arc<Tile>` per pool entry and one prototype buffer per cel, peak load
memory is **lower** than v4's.

### 11.2 Autosave is a first-class write path

**Context.** The Editor autosaves to `.mkpx` on every change, debounced by 10 s (atomic
`doc.mkpx.tmp` write → rename → keep `doc.mkpx.bak`, per `app/lib/editor/persistence/drawing_store.dart`).
So the format is written *far more often than read*, almost always after an edit that dirtied only a
few 32×32 tiles. **Target:** an autosave after a small edit does work proportional to what changed,
not to the whole document, and never blocks the editor.

The **format needs no change** to meet this — its structure already enables it. A conformant writer
SHOULD implement the following, all of which is **pure memoization**: it MUST produce **byte-identical**
output to a from-scratch canonical encode (the determinism guarantee of §7 is preserved; the cache
never changes the bytes, only the time to produce them).

**(a) Skip unchanged saves.** The engine keeps a *dirty flag* set on any pixel/structural mutation and
cleared on save. When the debounce fires and the flag is clear, **skip entirely** — no serialization,
no IO. If dirty, compute `Document::content_hash()`; if it equals the last-saved hash (e.g. the edit
was undone back to the saved state), skip too. (Selection-only changes: see (e).) The hash is the
same value the header needs anyway (§3.1.1), so this check is free on the saves that do proceed.

**(b) Incremental tile encoding via a persistent cache.** The engine's tiles are `Arc<Tile>`; an
untouched tile keeps the **same `Arc` pointer** across edits, and the COW dirty set (changed `Arc`s)
is exactly what a stroke touched. The writer keeps, across saves, a memo `tile_ptr → (content_hash,
encoded_record)` where `encoded_record` is the smallest-wins codec bytes of §3.3. On each save it
walks present tiles in canonical order:
- **pointer hit** → reuse the cached hash + encoded bytes verbatim (no hashing, no codec re-selection);
- **pointer miss** (a newly-created `Arc` = a dirtied tile) → hash once, run the codec chooser once,
  insert.

Per-save encoding is therefore **O(tiles dirtied since last save)** — usually a few — plus
**O(present references)** cheap pointer-map lookups to assign the first-appearance pool indices. The
memo is pruned as `Arc`s drop (or rebuilt lazily); it is bounded by the count of distinct present
tiles. The value-dedup fallback (two *distinct* `Arc`s with identical content) is keyed by the cached
`content_hash`, so it too costs nothing on the hit path.

**(c) Cheap cel dedup by pointer.** Two layers are the same cel iff they have identical present
`(grid_index → Arc pointer)` sequences — a pointer comparison, no content hashing. The cel pool
(§3.4) is built from these fingerprints in O(present references); a held layer across many frames is
recognized as one cel without touching pixels.

**(d) Assemble + checksum.** Concatenating the cached per-tile byte slices and running CRC-32 over
each chunk is O(file bytes) at table-driven ~GB/s — a few ms even for a multi-MB file. `content_hash`
(header) is one O(present-pixels) pass over the in-RAM document, independent of serialization order;
if profiling ever shows it dominating, the engine can maintain it incrementally, but that is not
needed for the typical case.

**(e) Persist selection cheaply.** A selection change with no pixel change won't move `content_hash`,
so (a) would wrongly skip it. The shell SHOULD treat a selection edit as dirtying autosave (or fold
the selection's own small hash into the skip check) so a marquee survives a crash. Encoding `msel`
(§3.6) is O(bbox) and bounded by `MAX_SEL_BYTES`.

**(f) Off-thread IO.** The fast, cache-accelerated **encode** runs on the engine's thread (it owns the
document); the resulting `Vec<u8>` is handed to a background thread/isolate for the atomic
tmp-write → rename → fsync, so disk latency never blocks the editor. Only the *bytes* cross the
boundary, never the `Session`.

### 11.3 What autosave writes

Autosave emits **exactly the deterministic engine core** — `MHDR, PLTS, TILS, CELS, FRMS[, msel],
MEND` — and **never** the ancillary `meta`/`thmb` (those are for the explicit "export a self-contained
file" path, §7). So autosave *is* the canonical writer, and a crash-recovered autosave file is a
fully valid, CRC- and hash-verifiable `.mkpx` indistinguishable from a manual save of the same state.

### 11.4 Worst case and bounds

A global operation that dirties every tile (a full-canvas filter, a palette-wide recolor, a large
import) defeats the cache for that one save: it pays a full re-encode, bounded by O(present pixels).
For the typical 64f / 8l / 128² project that is a few hundred thousand pixels — tens of ms; for the
pathological 1024f / 64l / 256² document (which the engine already declares cannot be RAM-resident on
mobile, SPEC §8.1) it is correspondingly large, but such a save is rare, is 10 s-debounced, and runs
off the UI thread. **No autosave ever costs more than a single canonical encode — the same bound as a
manual save** — and the common case (a stroke) costs a tiny fraction of it.

---

## 12. Constants (reference)

```
SIGNATURE        = 89 4D 4B 50 58 0D 0A 1A         (8 bytes)
FORMAT_VERSION   = 9
TILE             = 32   (tile_log2 = 5), TILE_PX = 1024, TILE_RAW_BYTES = 4096
CANVAS           = 8..=256           FRAMES = 1..=1024   LAYERS = 1..=64
DURATION_US      = 16_667..=1_000_000
MAX_PALETTES     = 256   MAX_COLORS = 65_536   MAX_STR = 4096
MAX_POOL_TILES   = 1<<24  MAX_CELS = 1<<20
MAX_SEL_BYTES    = 73_728            THUMB_MAX = 1 MiB
VARINT_MAX_BYTES = 5 (u32 fields)
CRC32            = IEEE 0xEDB88320 reflected, init/xorout 0xFFFFFFFF, over type++data, LE
Tile methods     = 0 RAW · 1 RLE · 2 INDEXED
Selection tags   = 0 RECT · 1 BITS · 2 EMPTY
Loop modes       = 0 Loop · 1 Once · 2 PingPong
Layer flags      = bit0 visible · bit1 locked
Gutter modes     = 0 none · 1 symmetric full-canvas
Endianness       = little-endian (all integers except LEB128 varints)
```

## 13. Field-order cheat sheet

```
SIGNATURE(8)
chunk := length:u32  type:[u8;4]  data[length]  crc:u32           # crc over type++data; first-letter case = crit/anc

MHDR data(33): format_version:u16 canvas_w:u16 canvas_h:u16 tile_log2:u8 gutter_mode:u8
               loop_mode:u8 active_frame:u32 active_palette:u16 frame_count:u16 content_hash:u128
PLTS data: palette_count:varint  { name:str  color_count:varint  rgba×color_count }×
TILS data: tile_count:varint  { method:u8  payload… }×            # self-delimiting
             0 RAW     : rgba×1024
             1 RLE     : { run:varint(1..=1024)  rgba }×  (Σrun==1024)
             2 INDEXED : count_minus_1:u8  rgba×ncolors  indices[ceil(1024*k/8)]  (k=bits_needed(ncolors), LSB-first)
CELS data: cel_count:varint  { present_count:varint  { gap:varint  tile_ref:varint }× }×
             (grid_index = prev+1+gap, strictly ascending, < cells)
FRMS data: frame_count:varint
             { frame_id:u32 duration_us:u32 active_layer:varint layer_count:varint
               { layer_id:u32 name:str flags:u8 opacity:u8 blend:u8 cel_ref:varint }× }×
msel data (anc): tag:u8  [bbox_x:u16 bbox_y:u16 bbox_w:u16 bbox_h:u16 [packed bits LSB-first]]
meta data (anc): entry_count:varint  { key:str value_type:u8 value }×
thmb data (anc): format:u8 [w:u16 h:u16] image_bytes…
MEND data: (empty)            # file ends immediately after its crc

str    := len:varint(≤4096) + utf8[len]   (lossy decode)
varint := canonical unsigned LEB128, ≤5 bytes for u32, overlong/overflow → Corrupt
```

---

## 14. Over-engineering watch — what was cut, and why

v9 is a *synthesis*, so its most important discipline is subtractive. Beyond the standard rejections
all three inputs shared — **no compression in the core** (the pools + indexed codec already capture
the structural redundancy pixel art has, and whole-buffer compression *fights the incremental autosave
encoder* of §11.2 — recompressing the pool on every 10 s save trades cheap writes, which you have, for
bytes, which local disk doesn't need; the sanctioned escape hatch, only if a corpus ever shows a real
residual win, is a **pure-Rust, version-pinned** DEFLATE [e.g. `miniz_oxide`] as an **ancillary,
export-only** transform on the `TILS` payload — kept out of the deterministic core and off the autosave
path, added as a new tile `method` id or ancillary chunk *without* a container change), **no
inter-frame pixel delta / motion compensation** (dedup already captures the
"hold a tile across frames" case, and it would break the clean pool ↔ `Arc<Tile>` mapping), **no
random access / streaming / partial-frame load** (whole-file meets the budget), **no undo/action
log** (transient), **no arithmetic coding / global-palette indexed pixels** (slow/fiddly to keep
integer-exact; the latter is unsafe for off-palette imports) — v9 also **cut machinery that
individual inputs carried**:

- **No append-only journal / delta-log autosave.** Tempting for "write only what changed" under the
  10 s autosave, but it reintroduces exactly what SPEC §17 rejected — the on-disk format is
  **state-based, not an action log**: a journal needs replay-on-load, periodic log compaction, and a
  *second* crash-safety story, and it fights the verified-whole-document integrity model (CRC +
  content-hash). The incremental **encoder** (§11.2) already makes a whole-file autosave cost
  proportional to the edit, so every save stays a single, self-verifying, state-based snapshot that
  `drawing_store`'s existing tmp→rename→bak dance makes atomic. Revisit only if a real corpus shows
  whole-file writes are genuinely too heavy for large projects on mobile — at which point a
  bounded-size "recent deltas" ancillary chunk could be added without disturbing the core.
- **No per-tile `entry_len` length prefix.** One input length-prefixed every pool entry so a future
  unknown codec could be skipped — but a *skipped* tile is silent pixel loss, which contradicts the
  critical philosophy, and the prefix costs 1–2 bytes on every one of potentially thousands of pool
  tiles. v9's codecs are exactly self-delimiting, the chunk CRC frames the whole pool, and an unknown
  method is a clean `Corrupt` (a new tile codec is a semantic change that *should* gate, not silently
  drop). Growth room lives at the chunk and format-version level, where it's free.
- **No `min_reader_version` field.** Redundant: the critical-chunk-refuse rule (§8.2) already forces
  a safe refusal whenever a file uses a section an old reader can't interpret. One mechanism, not two.
- **No whole-file hash trailer.** Redundant with per-chunk CRC + verified content-hash.
- **No separate `SOLID` method, no `IDX4`/`IDX8` split.** `INDEXED` with a derived `k` (0..8 bpp)
  subsumes both — one codec, full bit-packing granularity, `k=0` *is* solid.
- **No stored raw gutter/storage dimensions.** A 1-byte `gutter_mode` enum is self-describing yet
  derived, so it stays future-proof without the desync risk (or the redundant "store then validate
  against the derived value" dance) of persisting raw dims.
- **No selection bit-RLE codec.** The bbox `EMPTY`/`RECT`/`BITS` encoding already collapses the
  common cases to a handful of bytes and bounds arbitrary shapes to their bbox; a second selection
  codec earns nothing.
- **No tolerant chunk-order reader / offset table.** A fixed canonical order with a single forward
  pass is simpler and sufficient (`TILS`→`CELS`→`FRMS` guarantees references resolve in one pass).

**The one judgment call — the cel pool.** It is the single piece of "extra" machinery v9 keeps beyond
the tile pool (it comes from one of the three inputs). It earns its place *specifically* because the
editor supports **up to 1024 frames**: without it, a long hold of a static layer repeats that layer's
tile-reference list once per frame (tens of KB at 1024 frames); with it, the layout is stored once.
It is a small, orthogonal second pool that reuses the exact same "dedup by content, reference by
index" pattern as the tile pool, so it adds concept-reuse, not concept-count. **If** a corpus ever
shows holds are rare in practice, it is cleanly removable: drop `CELS`, inline one implicit cel per
layer into `FRMS`, and every other part of the format is unchanged.

**The minimal core that still beats v4 decisively:** signature + `MHDR` + `PLTS` + a deduplicated
`TILS` with `{RAW, RLE, INDEXED}` + a sparse-grid `FRMS` (implicit per-layer cels) + per-chunk CRC +
`MEND`. That alone delivers examples A/B/C. `CELS` (long-hold dedup), `msel` (bbox), and
`meta`/`thmb`/verified-hash are each independent, high-value, individually-droppable increments.

---

*End of v9 specification — the synthesis: two dedup pools, sparse gutter, a never-expand indexed
codec, and two verified integrity layers; pure-Rust, integer-exact, byte-deterministic, panic-free.*
