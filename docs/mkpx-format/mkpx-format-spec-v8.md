# `.mkpx` Binary Format — Specification **v8**

> **Status.** A complete, from-scratch redesign of the Makapix Editor's native document
> format. No backward compatibility with v1–v4 is required or attempted; v8 is a clean break.
> This document is self-contained and byte-level: a Rust engineer can implement a conformant
> reader and writer from it alone.
>
> **Ground truth this design is built on** (read and verified against the tree):
> `crates/engine/src/document.rs` (the data model), `crates/engine/src/buffer.rs` (the 32×32
> tiled COW buffer), `crates/engine/src/color.rs` (`Rgba8`), `crates/engine/src/selection.rs`
> (the 1-bit `Mask`), `crates/engine/src/util.rs` (the FNV-128 content hash), and
> `crates/engine/src/io.rs` (today's v4 codec). Size comparisons cite `current-format-v4-introspection.md`.

---

## 1. Design goals and tradeoffs

v8 is optimized, in strict priority order:

1. **Determinism first.** Byte-identical output for identical documents, on every platform.
   Integer-exact, fixed little-endian, no floats anywhere in the persisted path, canonical
   encodings. Goldens must never fork. This is non-negotiable and it constrains every other
   choice below (e.g. it forbids putting timestamps in the deterministic core, and it forces a
   deterministic tie-break in the per-tile codec chooser).
2. **Dependency-free and safe.** The codec is pure Rust with **zero external crates** and
   `#![forbid(unsafe_code)]`, matching the engine charter. It ships its own varint, per-tile
   codecs, and CRC-32. No zstd/flate/PNG in the engine (see §11 for the explicit rejection).
3. **Kill the two structural redundancies of v4.** (a) The **9× gutter tax**: v4 writes one
   present-flag byte for *every* storage tile, including the ~8/9 that are empty gutter. v8
   stores present tiles **sparsely** — an empty tile costs *zero* bytes. (b) The **lost
   copy-on-write sharing**: v4 re-serializes identical tiles once per frame/layer even though
   they are one `Arc` in RAM. v8 **deduplicates tiles on disk** via a content-addressed pool,
   so a static background across 64 frames is stored **once**.
4. **Beat RLE on the cases it loses.** v4's per-tile RLE *expands* on dithered/noisy tiles
   (up to 1.5× raw). v8 adds a per-tile **indexed-color** codec and picks the smallest encoding
   per tile, with a **RAW ceiling** so no tile ever exceeds ~4 KiB + a byte.
5. **Robust against hostile input.** Typed errors, never a panic; every length bounds-checked;
   every count capped; allocations bounded by what the remaining input could actually supply;
   verified integrity (per-chunk CRC-32 **and** a checked content-hash footer — v4 wrote a hash
   it never read).
6. **Self-describing and extensible.** A real PNG-style **TLV chunk container** with a
   critical/ancillary convention, so a reader can skip data it does not understand and the
   format can grow without a version bump. Optional metadata/thumbnail can travel *inside* the
   file, so a `.mkpx` no longer needs its sidecar directory.

**Explicit tradeoffs.** We accept slightly more code than v4's flat positional stream (chunk
framing, a varint, three tile codecs, CRC-32) in exchange for large size wins and real
forward-compatibility. We accept whole-file in-memory load (no streaming / partial-frame
random access) because the size budget (§10) is small and it keeps the reader simple. We keep
the gutter geometry **derived, never stored** (matching the engine invariant that it can never
desync from undo/redo).

**Non-goals.** Not a transport/publish format (publishing still rasterizes to PNG/GIF). Not an
action/undo log. Not a lossy or resampling format — v8 is exactly lossless.

---

## 2. Container structure and framing

A `.mkpx` v8 file is an 8-byte **signature** followed by a sequence of **chunks**, terminated
by the `MEND` chunk. All multi-byte integers are **little-endian** unless stated otherwise.

### 2.1 Signature (8 bytes, not a chunk)

```
0x89  'M'  'K'  'P'  'X'  0x0D  0x0A  0x1A
```

Chosen like PNG's signature to detect the common transport hazards: the leading `0x89` has the
high bit set (catches 7-bit / text-mode channels that strip it); `0x0D 0x0A` catches CRLF↔LF
newline translation; `0x1A` (DOS EOF) catches naive text-mode truncation. A mismatch →
`BadMagic`.

### 2.2 Chunk layout

Every chunk is:

| Field    | Type      | Bytes | Notes |
|----------|-----------|-------|-------|
| `length` | `u32` LE  | 4     | Byte length of `data` only (excludes `type` and `crc`). |
| `type`   | `[u8;4]`  | 4     | Four ASCII bytes identifying the chunk. |
| `data`   | `[u8;length]` | `length` | Chunk payload (§3). |
| `crc`    | `u32` LE  | 4     | CRC-32 (IEEE) over `type` ++ `data` (§8.1). |

The reader advances chunk-by-chunk: read `length`; require `length + 8 ≤ bytes_remaining`
(the `+8` covers `type` and `crc`) else `Truncated`; read `type` and `data`; recompute CRC over
`type ++ data` and require equality else `BadCrc`. It then dispatches on `type`.

### 2.3 Critical vs. ancillary — skipping unknown data

The case of the **first byte** of `type` encodes criticality (PNG's convention, simplified):

- **Uppercase `A`–`Z`** → **critical**. A reader that does not recognize a critical chunk MUST
  fail with `UnknownCriticalChunk(type)`.
- **Lowercase `a`–`z`** → **ancillary**. A reader that does not recognize an ancillary chunk
  MUST skip it (it already knows `length`) and continue. Ancillary chunks never carry data the
  artwork cannot be reconstructed without.

This makes "ignore unknown chunks" a real, load-bearing guarantee (v4's was incidental — its
reader merely stopped early). New ancillary chunks can be added freely; new critical chunks
raise `min_reader_version` (§8.2).

### 2.4 Defined chunks and canonical order

| Type   | Crit? | Count | Purpose |
|--------|-------|-------|---------|
| `MHDR` | crit  | 1, first | Header: version, canvas, gutter policy, loop, counts. §3.1 |
| `PLTS` | crit  | 1     | Palette table. §3.2 |
| `TILS` | crit  | 1     | Deduplicated tile pool (unique tiles, encoded once). §3.3 |
| `FRMS` | crit  | 1     | Frames → layers → sparse tile references into the pool. §3.4 |
| `msel` | anc   | 0–1   | Selection mask. §3.5 |
| `meta` | anc   | 0–1   | Metadata key/value map. §3.6 |
| `thmb` | anc   | 0–1   | Thumbnail image. §3.6 |
| `hash` | anc   | 0–1   | Verified content-hash footer. §3.7 |
| `MEND` | crit  | 1, last | End marker (empty). §3.8 |

**Canonical write order** (what the deterministic engine writer always emits):
`MHDR, PLTS, TILS, FRMS[, msel][, hash], MEND`. The optional `meta`/`thmb` chunks, when present,
are written by the shell/codec **after `FRMS` and before `MEND`**; the deterministic engine core
never emits them (§7). A reader accepts any order that satisfies "`MHDR` first, `MEND` last,
`TILS` before `FRMS`," but the canonical order is fixed so identical documents produce identical
bytes.

---

## 3. Section byte layouts

Two primitives are used throughout:

- **`varint`** — unsigned LEB128. Little-endian base-128: each byte carries 7 payload bits in
  bits 0–6; bit 7 set means "more bytes follow." The **writer emits the canonical minimal
  form** (no trailing `0x80…0x00` padding). The reader accumulates `value |= (byte & 0x7F) <<
  shift`; it rejects a `varint` longer than **5 bytes** where a `u32` is expected (**10 bytes**
  for a `u64` field), or any encoding whose value would overflow the target width →
  `Corrupt("bad varint")`. Varints keep small ids/indices to 1 byte.
- **`str`** — `varint` byte-length `n` followed by `n` UTF-8 bytes. Decoded lossily
  (`from_utf8_lossy`, matching the engine); `n` is bounded by remaining input.

### 3.1 `MHDR` — header

| Field | Type | Notes |
|-------|------|-------|
| `format_version` | `u16` | `8`. Anything else → `UnsupportedVersion`. |
| `min_reader_version` | `u16` | Minimum reader that can *correctly* read this file. A reader whose own version `< min_reader_version` → `UnsupportedVersion`. Writers set it to the lowest version that understands every **critical** chunk actually used (v8 writers: `8`). |
| `canvas_w` | `u16` | 8..=256. Else `Corrupt("canvas size")`. |
| `canvas_h` | `u16` | 8..=256. |
| `tile_log2` | `u8` | Tile edge = `1 << tile_log2`. Must be `5` (32) in v8; else `UnsupportedTileSize`. Stored for self-description and future flexibility. |
| `gutter_mode` | `u8` | `0` = no gutter (`storage = canvas`); `1` = symmetric full-canvas gutter (`storage = 3·canvas`, the engine's current policy). Else `Corrupt`. The gutter is **derived from this mode + canvas**, never stored as raw dimensions, so it cannot desync. |
| `loop_mode` | `u8` | `0`=Loop, `1`=Once, `2`=PingPong (any other value → Loop, matching the engine's tolerant mapping). |
| `active_frame` | `u32` | Clamped to `frame_count-1` on load. |
| `active_palette` | `u16` | Clamped to `palette_count-1` on load. |
| `frame_count` | `u32` | 1..=`MAX_FRAMES` (1024). Else `Corrupt("frame count")`. |

The **storage** dimensions and the tile grid are re-derived on load:
`storage_w = gutter_mode==1 ? 3·canvas_w : canvas_w` (same for height), `tiles_x =
ceil(storage_w / 32)`, `tiles_y = ceil(storage_h / 32)`, `cells = tiles_x · tiles_y`. This
exactly reproduces `RgbaBuffer::new(storage_w, storage_h)`.

### 3.2 `PLTS` — palettes

```
palette_count : varint                 (1..=MAX_PALETTES = 256)
repeat palette_count:
    name         : str
    color_count  : varint              (0..=MAX_COLORS = 65536)
    colors       : [r,g,b,a] × color_count   (straight RGBA, 4 bytes each)
```

If `palette_count == 0` the loader injects the built-in default 16-colour ramp (as the engine
does today). `active_palette` (from `MHDR`) is clamped to `palette_count-1`.

### 3.3 `TILS` — the deduplicated tile pool

This chunk is v8's headline. Every **unique** present tile in the whole document (across all
frames and layers) is stored **exactly once** here; `FRMS` references pool entries by index.
This is the on-disk realization of the engine's in-RAM `Arc`-shared COW tiles.

```
pool_count : varint                    (0..=MAX_POOL_TILES; see §9 for the allocation bound)
repeat pool_count:
    entry_len : varint                 (byte length of `method`++`payload`)
    method    : u8                     (§3.3.1)
    payload   : [u8; entry_len - 1]    (method-specific; §3.3.1)
```

`entry_len` frames each tile so a reader can (a) bound the payload read and (b) **skip a tile
encoded with a future, unknown `method`** by advancing `entry_len` bytes — forward-compatible
new codecs without a format bump. A reader parses `payload` per `method`; if parsing would
exceed `entry_len` → `Corrupt`; any bytes between the parsed end and `entry_len` are tolerated
and skipped (growth room). Pool entries are ordered by **first occurrence** in document
traversal order (frame 0→N, within a frame layer 0→M, within a layer cell 0→cells-1); this is
deterministic, so identical documents yield an identical pool. Deduplication is by **raw
1024-pixel content**, hash-bucketed then confirmed with a full byte compare (no false merge on
a hash collision).

Each tile is 32×32 = **1024 pixels** in **local row-major order** (`local = y*32 + x`), straight
`Rgba8`. The encoder computes the encoded size for every applicable method and picks the
**smallest**; ties break to the **lowest `method` id**. This selection is deterministic.

#### 3.3.1 Per-tile codecs

**`method = 0x00` — `RAW` (the ceiling).**
Payload = 4096 bytes, the tile's 1024 pixels as `[r,g,b,a]` row-major. Always valid; guarantees
no tile ever costs more than `4096 + ~2` bytes. The reader requires exactly 4096 payload bytes.

**`method = 0x01` — `RLE` (run coherence).**
Payload = a sequence of `(run: u16 LE, r, g, b, a)` pairs (6 bytes each) over the row-major
scan, until `Σ run == 1024`. `run ∈ 1..=1024`. Reader: `run == 0` or `Σ run > 1024` →
`Corrupt("bad RLE run")`. Best for flat/low-frequency tiles; can expand on noise, which is why
the chooser exists.

**`method = 0x02` — `INDEXED` (colour-count coherence).**
For tiles using ≤ 256 distinct colours (the overwhelming pixel-art case, and the case where
`RLE` loses to dithering). Subsumes "solid tile" as the 1-colour degenerate.

```
count_minus_1 : u8                     (ncolors = count_minus_1 + 1, so 1..=256)
table         : [r,g,b,a] × ncolors    (the tile's distinct colours, in first-appearance
                                         order under the row-major scan — deterministic)
indices       : ceil(1024 * bpp / 8) bytes
```

`bpp` (bits per index) is **derived**, the smallest of `{0,1,2,4,8}` with `2^bpp ≥ ncolors`:
`ncolors 1 → 0`, `2 → 1`, `3–4 → 2`, `5–16 → 4`, `17–256 → 8`. For `bpp = 0` (solid tile) there
are **zero** index bytes. Indices are packed **MSB-first within each byte**, row-major, pixel 0
in the high bits; the final byte is zero-padded in its low bits. Reader validates: `ncolors`,
the derived `bpp`, `table` length, `indices` length against `entry_len`/remaining, and that
every unpacked index is `< ncolors` → else `Corrupt`.

*Why indexed wins where RLE loses:* a 2-colour dithered/checkerboard tile encodes to `1` (count)
`+ 8` (table) `+ 128` (1 bpp × 1024) `= 137` bytes, versus `RLE`'s worst-case `6144` and `RAW`'s
`4096`.

### 3.4 `FRMS` — frames, layers, and pool references

```
repeat frame_count (from MHDR):
    frame_id     : u32
    duration_us  : u32                 (clamped to 16_667..=1_000_000 on load)
    active_layer : varint              (clamped to layer_count-1 on load)
    layer_count  : varint              (1..=MAX_LAYERS = 64; else Corrupt)
    repeat layer_count:
        layer_id : u32
        name     : str
        flags    : u8                  (bit0 = visible, bit1 = locked; other bits reserved 0)
        opacity  : u8
        blend    : u8                  (0 = Normal; reserved for future modes, else read-as-Normal)
        # --- sparse tile grid: only present tiles are listed ---
        present_count : varint         (0..=cells)
        repeat present_count:
            cell_index : varint        (0..=cells-1, STRICTLY INCREASING within this layer)
            pool_id    : varint        (0..=pool_count-1, index into TILS)
```

`cell_index` is the storage-tile grid index `ty*tiles_x + tx`. Requiring it **strictly
increasing** gives determinism, lets the reader validate monotonicity (a repeat or out-of-order
value → `Corrupt("tile order")`), and bounds `present_count ≤ cells`. Each `pool_id` is bounds-
checked `< pool_count`. On load, the layer's `RgbaBuffer` is created at the storage size and each
listed tile is installed at its `cell_index` from the pool entry's decoded 1024 pixels. Absent
cells stay `None` (transparent) — the sparse encoding is exactly why the 9× gutter is free.

Frame/layer `id` generators are seeded with `IdGen::starting_at(max_id + 1)` (never a warm-up
loop) so a crafted id like `0xFFFFFFFF` cannot spin the loader — carried over from the v4
hardening.

### 3.5 `msel` — selection (ancillary)

The selection is **storage-sized** editor state persisted for crash recovery (as in v4). It is
**not** folded into the content hash (§3.7), so a selection change never churns thumbnail
caches or goldens.

```
tag : u8            (0 = RECT, 1 = BITS, 2 = EMPTY)
```

- **`EMPTY` (2)** — no further bytes. Reconstructs an all-zero storage-sized mask (round-trips
  a `Some(empty mask)` distinctly from a `None`, which writes no `msel` chunk at all).
- **`RECT` (0)** — `bbox_x, bbox_y, bbox_w, bbox_h : u16` (storage coords). Every pixel inside
  the bbox is selected. This is the common case (rectangular marquee, select-all, a wand over a
  filled rect) and costs 9 bytes.
- **`BITS` (1)** — `bbox_x, bbox_y, bbox_w, bbox_h : u16`, then `ceil(bbox_w*bbox_h / 8)` packed
  bytes: the bbox's bits row-major, **LSB-first** (bit `k` = the `k`-th pixel in bbox scan
  order). For arbitrary shapes.

The writer chooses `RECT` iff the mask is exactly its bounding box fully set, `EMPTY` iff no
bits are set, else `BITS`. On load, if the bbox lies outside the derived storage size (a stale
or crafted chunk) the selection is **dropped** and the document still loads (matching v4's
tolerant handling); the packed-byte count is bounded by `MAX_SEL_BYTES` (§9).

Storing only the bbox (not the full `768×768` storage plane) is the key size win: a rectangular
selection over a `128×128` canvas costs `9`–`~2 KiB` instead of v4's fixed ~73 KiB word plane.

### 3.6 `meta` and `thmb` — optional identity (ancillary)

These let a `.mkpx` travel without its sidecar directory. **They are excluded from the
deterministic engine core** (§7) — they carry inherently non-deterministic data (timestamps,
author, a rasterized thumbnail) and would otherwise fork goldens. When emitted, it is by the
shell/codec, not by the dependency-free engine.

**`meta`** — a small typed key/value map:

```
entry_count : varint
repeat entry_count:
    key        : str                   (e.g. "title", "author", "created_unix",
                                         "modified_unix", "software")
    value_type : u8                    (0 = str, 1 = u64 LE, 2 = i64 LE, 3 = bytes(varint len))
    value      : per value_type
```

**`thmb`** — a preview image, produced by the `codec` crate (PNG) or the shell, never by the
engine: `format : u8` (`0` = PNG blob, `1` = raw straight-RGBA with `w:u16, h:u16` prefix), then
the image bytes to the end of the chunk. The engine reserves the type; it does not synthesize
PNG (that lives behind the quarantined `image` dependency in `crates/codec`).

### 3.7 `hash` — verified content-hash footer (ancillary)

```
content_hash : u128 LE                 (= Document::content_hash(), the engine's FNV-128)
```

Unlike v4 — which wrote a hash and **never read it** — v8's reader, when it understands `hash`,
recomputes `Document::content_hash()` on the fully-loaded document and compares. A mismatch →
`Corrupt("content hash mismatch")`. This is a semantic integrity check (did we reconstruct the
same artwork?) that complements the per-chunk CRC-32 (did the bytes survive the channel?). The
hash covers canvas size + frames (duration + per-layer name/visible/locked/opacity + present-
tile pixels); it deliberately excludes the selection, palettes, ids, and loop mode — matching
`Document::content_hash()` so the app's existing thumbnail-cache/golden keys are unchanged.

### 3.8 `MEND` — end marker

`length = 0`, empty data, CRC over the 4 type bytes. Terminates parsing; trailing bytes after
`MEND` are ignored.

---

## 4. Pixel/tile encoding, sparsity, dedup — summary

- **Sparsity.** Only present tiles are listed (`FRMS` sparse grid). An empty tile — including
  every empty gutter tile — costs **0 bytes**, eliminating v4's per-tile present-flag tax that
  scaled 9× with the gutter.
- **Deduplication (on-disk COW).** Identical tiles are stored **once** in `TILS` and referenced
  by `pool_id`. A static background across N frames → 1 pool entry + N cheap references. A layer
  duplicated across frames, a flat fill spanning many tiles, a symmetric sprite — all collapse.
  This is the single largest win over v4, which re-serialized every tile in full per frame/layer.
- **Per-tile codec choice.** `RAW` / `RLE` / `INDEXED`, smallest-wins with a deterministic tie-
  break, `INDEXED` beating RLE on dithered/noisy tiles, `RAW` capping the worst case. No indexed
  mode relies on the document palette — each tile's local table is exact and lossless, so
  imported photos, gradients, and HSV-shifted pixels all round-trip.
- **No cross-tile / inter-frame pixel prediction, no global LZ.** Deliberately out of scope
  (§11): dedup + indexed captures the redundancy pixel art actually has, dependency-free and
  fast.

---

## 5. Gutter / storage vs. canvas

Only the **canvas** size and the **gutter policy** (`gutter_mode`) are stored. The **storage**
area (`3w × 3h` under mode 1), the tile grid, and the canvas origin are **re-derived** on load,
exactly as the engine derives them from `Document::gutter_for` — never persisted as raw numbers,
so they can never desync from undo/redo (the engine's load-bearing invariant). Present tiles
anywhere in the storage area — canvas *or* gutter — are serialized (moved-off-canvas pixels are
real, recoverable document state); empty gutter tiles cost nothing thanks to the sparse grid.
`cell_index` values in `FRMS` are in this derived storage-tile grid.

---

## 6. Selection serialization

Covered byte-for-byte in §3.5. Key points: storage-sized, bbox-relative (not a full storage
plane), three tags (`EMPTY`/`RECT`/`BITS`) that round-trip `None` vs `Some(empty)` vs a rect vs
an arbitrary shape, dropped-not-fatal on a stale/out-of-range bbox, excluded from the content
hash.

---

## 7. Metadata & determinism boundary

There are **two** notions of "same":

1. **File-level byte-determinism (the strong one).** The engine's core writer — `MHDR`, `PLTS`,
   `TILS`, `FRMS`, `msel`, `hash`, `MEND` in canonical order, canonical varints, deterministic
   pool ordering and per-tile codec choice — produces **byte-identical** output for two
   documents that are structurally equal (same canvas, palettes, frames, ids, durations, layer
   attributes, pixels, selection). Goldens gate on this. It contains **no** timestamps, author,
   tool version, or thumbnail — those are non-deterministic and would fork goldens, so they are
   **not** in the core.
2. **Artwork content-hash (the app's).** `Document::content_hash()` (§3.7), a subset used for
   thumbnail cache keys, stored in the ancillary `hash` chunk and verified on load.

Identity/metadata (`meta`, `thmb`) is therefore **optional and ancillary**, written only by the
shell/codec when a self-contained file is wanted, and always skippable. This gets the best of
both: deterministic artwork bytes for CI, and travel-anywhere self-description when desired.

---

## 8. Integrity, versioning, forward-compatibility

### 8.1 CRC-32

Every chunk carries a **CRC-32/IEEE** (polynomial `0xEDB88320` reflected, init `0xFFFFFFFF`,
final XOR `0xFFFFFFFF`) over `type ++ data`, stored as `u32` LE and **verified on every read**
→ `BadCrc(type)` on mismatch. It is implemented dependency-free (a per-byte bitwise loop, or a
lazily-built 256-entry table — both deterministic). This localizes corruption to a chunk, and
unlike v4's write-only footer, it is actually checked.

### 8.2 Versioning

- `format_version` (`u16`, currently `8`) identifies the format generation; an unknown value →
  `UnsupportedVersion`.
- `min_reader_version` (`u16`) is the hard-compat floor: a reader older than it must refuse the
  file. Writers raise it only when they emit a **new critical chunk** an older reader could not
  safely ignore. Adding **ancillary** chunks or **new tile `method`s** (skippable via
  `entry_len`) does **not** raise it.

### 8.3 Forward-compatibility mechanisms (three layers)

1. **Unknown chunks** — skipped if ancillary (lowercase type), fatal if critical (uppercase).
2. **Unknown tile methods** — skipped via each pool entry's `entry_len`.
3. **Trailing growth room** — a reader tolerates and skips bytes between a parsed structure's
   end and its declared length (`entry_len`, and each chunk's `length`), so a future writer can
   append fields to an existing structure without breaking old readers.

---

## 9. Hardening against malicious/corrupt input

The loader is **panic-free** and returns a typed `IoError`:

```
BadMagic
UnsupportedVersion(u16)
UnsupportedTileSize(u8)
UnknownCriticalChunk([u8;4])
Truncated
BadCrc([u8;4])
Corrupt(&'static str)
TooLarge(&'static str)
```

Rules the reader enforces:

- **Bounds on every read.** No slice access without first checking `remaining`. A `length`,
  `str` length, `varint`, or count that would read past end → `Truncated`.
- **Caps on every count.** `frame_count ≤ 1024`, `layer_count ≤ 64` (and ≥ 1),
  `palette_count ≤ 256`, `color_count ≤ 65536`, `present_count ≤ cells`,
  `cell_index < cells` and strictly increasing, `pool_id < pool_count`, tile index `< ncolors`,
  `MAX_SEL_BYTES = ceil(768*768 / 8) = 73_728`, `MAX_POOL_TILES = 1<<24`. Violations →
  `Corrupt`/`TooLarge`.
- **Bounded allocation.** A declared count is never trusted for `Vec::with_capacity` directly;
  the reserved capacity is `min(count, remaining_bytes / MIN_ENTRY_BYTES)` where `MIN_ENTRY_BYTES`
  is the smallest possible per-item on-disk size (e.g. a pool entry ≥ 2 bytes, a grid reference ≥
  2 bytes). A crafted `pool_count = 2^24` in a 40-byte file cannot force a giant allocation.
- **Varints are length-limited** (5 bytes for `u32`, 10 for `u64`) and overflow-checked →
  `Corrupt("bad varint")`, so a stream of `0x80` cannot loop or overflow.
- **Id generators seeded, not looped** (`starting_at(max+1)`) → no O(2³²) warm-up.
- **CRC and (if present) content-hash verified** — silent bit-flips are caught, not just
  structural violations.
- **Tolerant, not fatal, where the engine already is:** empty palette → default injected; stale
  selection bbox → dropped; unknown `blend`/`loop_mode`/reserved flag bits → mapped to defaults.

Because the reader validates before it allocates and never trusts a self-declared size beyond
what the input can supply, a hostile file is rejected in bounded time and memory.

---

## 10. Worked size examples (vs. v4)

Chunk overhead = 12 bytes each (`length` 4 + `type` 4 + `crc` 4); signature = 8. Figures are
rounded; the point is the ratio and *where* the bytes go.

### A. Empty 256×256 document (1 frame, 1 empty layer, default 16-colour palette)

Storage `768×768` → `24×24 = 576` tiles, all absent.

| Section | v8 bytes | Note |
|---|---|---|
| Signature | 8 | |
| `MHDR` | 29 | 17 data + 12 |
| `PLTS` | 86 | name "Default" + 16×4 colours |
| `TILS` | 13 | `pool_count = 0` |
| `FRMS` | 38 | 1 frame, 1 layer, `present_count = 0` |
| `hash` | 28 | |
| `MEND` | 12 | |
| **Total** | **≈ 214** | |

**v4: ≈ 729 bytes** — dominated by **576 present-flag bytes** for the empty gutter tiles. v8 is
**~3.4× smaller**, and the gap widens with every added layer/frame (each adds 576 flag bytes in
v4, ~1 byte in v8).

### B. 64-frame animation, 128×128, one detailed **static** background layer (a "hold")

Storage `384×384` → `12×12` tiles; canvas occupies the centre `4×4 = 16` tiles. The background
is identical in every frame.

- **v8:** the background's 16 tiles dedup to **16 pool entries**, referenced 64×. `TILS` holds
  those 16 tiles once (say ~300 B each ≈ 4.8 KiB). `FRMS` = 64 frames × (frame header + one
  layer header + a 16-entry reference grid ≈ 65 B) ≈ **5.7 KiB**. Total ≈ **~11 KiB**.
- **v4:** the 16 background tiles are re-serialized **in full every frame** = 16 × 64 × ~300 B ≈
  **307 KiB**, plus 144 present-flags × 64 ≈ 9 KiB. Total ≈ **~320 KiB**.
- **v8 is ~29× smaller** here — the dedup dividend. (Add a changing foreground layer and the
  ratio moderates toward the foreground's own entropy, but the static portion stays 1×.)

### C. One noisy 128×128 frame, fully dithered (2-colour checkerboard — RLE's worst case)

16 canvas tiles, each a 2-colour checkerboard.

- **v8 `INDEXED` (1 bpp):** per tile `1 + 8 + 128 ≈ 137` B → 16 × 137 ≈ **2.2 KiB** for the pool
  (+ tiny grid). The chooser rejects `RLE` (would be ~6 KiB/tile) and `RAW` (4 KiB/tile).
- **v4 `RLE`:** every pixel breaks the run → 1024 runs × 6 B = **6144 B/tile** × 16 ≈ **98 KiB**
  (RLE *expands* past raw's 64 KiB).
- **v8 is ~44× smaller** on this pathological case — the indexed-mode dividend.

Across the three, the wins are orthogonal: **A** = sparse gutter, **B** = tile dedup, **C** =
indexed codec. A typical multi-frame sprite benefits from all three at once.

---

## 11. Over-engineering watch — what was deliberately left out

- **No zstd / DEFLATE / any general-purpose LZ.** This is the big one. It would add a
  dependency (or a large hand-rolled codec), risk the reliable Windows/Android builds and the
  fast headless test loop, and complicate determinism/perf — all against the engine charter. Tile
  **dedup + indexed** already captures the redundancy pixel art has. *If* ratio ever becomes
  critical, a dependency-free DEFLATE could be added later as an **ancillary transform** on the
  `TILS` payload without touching the container — but it is out of scope now.
- **No PNG-style per-row filters / delta prediction** before the tile codec. Marginal on 32×32
  tiles versus the code and the extra parameter to make deterministic.
- **No inter-frame pixel delta / motion compensation.** Dedup already handles the dominant "hold
  the same tile across frames" case; true per-pixel inter-frame coding is complex and rarely
  wins on hard-edged pixel art.
- **No arithmetic/range coding, no global-palette indexed pixels.** The former is slow and
  fiddly to keep integer-exact; the latter is unsafe for off-palette pixels (imports, gradients)
  and would make the codec lossy or conditional. Per-tile local tables stay simple and exact.
- **No random access / partial-frame load / streaming.** Whole-file load meets the <300 ms
  budget and keeps the reader a single linear pass.
- **No stored gutter geometry.** Re-derived, matching the engine invariant; prevents desync.

**The simplest version that still beats v4 decisively:** signature + `MHDR` + `PLTS` + a
deduplicated `TILS` with just `{RAW, RLE, INDEXED}` + a sparse-grid `FRMS` + per-chunk CRC +
`MEND`. That core alone delivers examples A/B/C. `msel` (bbox-packed) is a small, high-value
add; `meta`/`thmb`/`hash` are optional cream that make the file self-contained without touching
determinism. Everything in this spec beyond that core is either free (chunk framing) or
skippable (ancillary chunks) — nothing is mandatory complexity.

---

## 12. Constants (reference)

```
SIGNATURE            = 89 4D 4B 50 58 0D 0A 1A          # 8 bytes
FORMAT_VERSION       = 8
MIN_READER_VERSION   = 8
TILE                 = 32   (tile_log2 = 5)
TILE_PX              = 1024
TILE_RAW_BYTES       = 4096
MIN_CANVAS           = 8      MAX_CANVAS = 256
MAX_FRAMES           = 1024   MAX_LAYERS = 64
MIN_DURATION_US      = 16_667 MAX_DURATION_US = 1_000_000
MAX_PALETTES         = 256    MAX_COLORS_PER_PALETTE = 65_536
MAX_POOL_TILES       = 1 << 24
MAX_SEL_BYTES        = 73_728          # ceil(768*768 / 8)
VARINT_MAX_BYTES     = 5 (u32 fields) / 10 (u64 fields)
CRC32                = IEEE 0xEDB88320 reflected, init/xorout 0xFFFFFFFF, over type++data, LE
Tile methods         = 0x00 RAW · 0x01 RLE · 0x02 INDEXED
Selection tags       = 0 RECT · 1 BITS · 2 EMPTY
Loop modes           = 0 Loop · 1 Once · 2 PingPong
Layer flags          = bit0 visible · bit1 locked
Endianness           = little-endian (all integers except LEB128 varints)
```

## 13. Field-order cheat sheet

```
SIGNATURE(8)
chunk := length:u32  type:[u8;4]  data[length]  crc:u32     # crc over type++data

MHDR data: format_version:u16 min_reader_version:u16 canvas_w:u16 canvas_h:u16
           tile_log2:u8 gutter_mode:u8 loop_mode:u8 active_frame:u32
           active_palette:u16 frame_count:u32
PLTS data: pal_count:varint  { name:str  ccount:varint  [rgba×ccount] }×
TILS data: pool_count:varint { entry_len:varint  method:u8  payload[entry_len-1] }×
             RAW      = [rgba×1024]
             RLE      = { run:u16  rgba }×  (Σrun==1024)
             INDEXED  = count_minus_1:u8  [rgba×ncolors]  indices[ceil(1024*bpp/8)]
FRMS data: { frame_id:u32 duration_us:u32 active_layer:varint layer_count:varint
             { layer_id:u32 name:str flags:u8 opacity:u8 blend:u8
               present_count:varint { cell_index:varint pool_id:varint }× }× }×
msel data: tag:u8 [ bbox_x:u16 bbox_y:u16 bbox_w:u16 bbox_h:u16 [packed bits] ]   # anc
meta data: n:varint { key:str value_type:u8 value }×                              # anc
thmb data: format:u8 [w:u16 h:u16] image_bytes…                                   # anc
hash data: content_hash:u128                                                      # anc, verified
MEND data: (empty)

str    := len:varint + utf8[len]      (lossy decode)
varint := unsigned LEB128, canonical-minimal on write, length/overflow-checked on read
```

---

*v8 is a clean-break redesign: a CRC-checked TLV container, a content-addressed tile pool that
puts the engine's `Arc`-shared COW on disk, a sparse tile grid that makes the 9× gutter free, and
a per-tile smallest-wins codec (`RAW`/`RLE`/`INDEXED`) that never expands and crushes dithering —
all dependency-free, integer-exact, byte-deterministic, and hardened with typed errors and
bounded allocation.*
