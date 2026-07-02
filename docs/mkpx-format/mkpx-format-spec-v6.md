# `.mkpx` Format — Specification v6 (from-scratch redesign)

> **Status.** A complete, implementable, byte-level specification for a **new** native document
> container for the Makapix Editor. This is a *clean-sheet* design: it owes nothing to the current
> on-disk layout and assumes **no backward-compatibility** requirement (the app has barely shipped).
> It is grounded in the real engine — `crates/engine/src/{buffer,document,color,selection,util,io}.rs`
> — and in the code-derived audit `current-format-v4-introspection.md`.
>
> **One-line pitch.** A chunked, little-endian container whose pixels live in a single
> **content-addressed tile pool** (each unique 32×32 tile stored once, referenced by index), so the
> in-RAM copy-on-write sharing the engine already has is preserved *on disk* — killing the animation
> redundancy that dominates v4 — with a **per-tile codec menu** that never expands, and a
> **verified whole-file checksum**.

---

## 1. Design goals and tradeoffs (priorities, stated up front)

In strict priority order. When two goals conflict, the higher one wins.

1. **Determinism above all.** Byte-identical output for byte-identical documents, on every platform.
   Fixed little-endian, no floats anywhere in the persisted path, canonical variable-length integers,
   a deterministic tile-pool order, and a deterministic per-tile codec choice. Goldens must never fork.
2. **Panic-free, bounded, hostile-input-safe loading.** Every read is bounds-checked; every
   allocation is sized only from a value that has already been range-checked against a hard cap;
   every failure is a typed `IoError`, never a panic, never an unbounded loop or allocation.
3. **Dependency-free, pure-Rust codec.** The engine crate is `#![forbid(unsafe_code)]` and ships its
   own hash + RLE by charter. v6 adds **no** dependency: no `zstd`, no `flate2`, no `image`. Every
   codec here is a few dozen lines of integer Rust. (See §11 for why this is a feature, not a
   limitation, and exactly what we give up.)
4. **Attack the real redundancy: on-disk COW loss.** The single largest structural waste in v4 is
   that `Arc`-shared identical tiles (a static background across 64 frames; a duplicated layer) are
   re-serialized in full every time. v6's tile pool collapses that to *one copy plus a few bytes of
   reference* — and, as a bonus, **restores** the `Arc` sharing when the file is loaded (v4 loses it).
5. **Never expand.** No document is larger than its raw pixel footprint plus small fixed overhead.
   The per-tile codec menu includes a `RAW` ceiling and picks the smallest encoding per tile, so the
   noisy/dithered case that inflates v4's RLE by ~1.5× is bounded instead.
6. **Self-describing and portable.** A `.mkpx` can optionally carry its own title/author/timestamps
   and a thumbnail, so a file can travel without the shell's sidecar directory — *without* those
   optional, volatile parts polluting the deterministic core or the content hash.
7. **Forward-compatible by construction.** A real chunked (type + flags + length) container: unknown
   **ancillary** chunks are skipped by length; unknown **critical** chunks are a typed rejection. The
   format can grow new sections without a version bump and without breaking old readers.

**Explicit non-goals** (see §11): random access, partial/streaming/single-frame loads, in-place
mutation, cross-tile prediction filters, and any general-purpose entropy coder. The performance
budget (a 64-frame / 8-layer / 128×128 document opens in < 300 ms) is met with comfortable margin by
a single-pass whole-file loader; we do not need streaming to hit it.

---

## 2. Container structure and framing

A v6 file is:

```
Preamble   :  magic "MKPX" (4)  |  version u16 = 6  |  reserved u16 = 0
Chunks     :  a sequence of TLV chunks (see below), in canonical order
Trailer    :  file_checksum u128   (the last 16 bytes of the file)
```

All multi-byte fixed-width integers are **little-endian**. Variable-length integers use the
canonical unsigned LEB128 encoding defined in §2.3. There are no floats anywhere in the file.

### 2.1 Chunk framing (TLV)

Every chunk has an 9-byte header followed by its payload:

| Field   | Type      | Bytes | Notes |
|---------|-----------|-------|-------|
| `type`  | `[u8;4]`  | 4     | Four ASCII bytes identifying the chunk (e.g. `MHDR`). |
| `flags` | `u8`      | 1     | bit0 = **critical** (1 = a reader that does not understand `type` must fail). bits 1–7 reserved, written 0. |
| `length`| `u32` LE  | 4     | Payload length in bytes. Must satisfy `length ≤ bytes_remaining_before_trailer`. |
| payload | `[u8;length]` | length | Chunk body (defined per type in §3). |

**Skipping unknown chunks.** A reader advances by `9 + length` per chunk. If it meets a `type` it
does not recognise: if bit0 (critical) is set it returns `IoError::UnknownCriticalChunk`; otherwise
it skips the payload and continues. This makes "ignore unknown data" a *real* guarantee, not the
incidental "reader stops early" behaviour of v4.

**Where chunks end.** The reader knows the total slice length `N`. Chunk scanning runs over
`[8 .. N-16]`; the final 16 bytes are the trailer checksum and are never parsed as a chunk. A chunk
whose `9 + length` would cross `N-16` is `IoError::Truncated`.

### 2.2 Canonical chunk set and order

| Order | `type` | Crit | Required | Purpose |
|------:|--------|:----:|:--------:|---------|
| 1 | `MHDR` | ✔ | ✔ | Main header: geometry, gutter, counts, active indices, loop mode, content hash. |
| 2 | `PALS` | ✔ | ✔ | Palette table (named swatch lists). |
| 3 | `TILE` | ✔ | ✔ | The content-addressed tile pool (every unique tile, once). |
| 4 | `FRMS` | ✔ | ✔ | Frames → layers → sparse tile references into the pool. |
| 5 | `SELC` | ✘ | ✘ | Selection mask (crash-safety; droppable). |
| 6 | `META` | ✘ | ✘ | Title/author/timestamps/tool version. **Excluded from determinism & content hash.** |
| 7 | `THMB` | ✘ | ✘ | Embedded thumbnail bytes (opaque, e.g. PNG). **Excluded from determinism.** |

The **writer** always emits the required critical chunks in the order above, followed by whichever
optional chunks apply, in the order above. This fixed order is part of the determinism guarantee.

The **reader** does a single forward scan that records `(type → offset, length, flags)` into a small
table (rejecting a duplicate of any critical chunk as `Corrupt`), then processes chunks in the
dependency order `MHDR → PALS → TILE → FRMS → SELC → META → THMB`. A missing required chunk is
`IoError::Corrupt`. This decouples correctness from stream order while keeping the writer canonical.

### 2.3 Variable-length integers (varint)

Unsigned LEB128, **canonical**: 7 bits per byte, low group first, continuation bit `0x80` set on all
but the last byte. Two hard rules for determinism and safety:

- **Writers emit the minimal number of bytes** for the value.
- **Readers reject non-canonical or over-range encodings.** A `varu32` uses **at most 5 bytes**; a
  reader that reads a 6th continuation byte, or decodes a value `> u32::MAX`, or finds a trailing
  `0x00`-only group that could have been omitted, returns `IoError::Corrupt("bad varint")`.

`varint(v)` is used for counts and indices (`palette_count`, `pool_count`, `tile_ref_count`,
delta grid indices, pool references, RLE runs). Fixed-width LE is used for ids, sizes, timestamps,
colours, and hashes. The spec below always names which.

### 2.4 String encoding

`str := len:u16 (LE) + len bytes of UTF-8`. Readers decode with lossy UTF-8 (invalid sequences →
U+FFFD) to stay panic-free, and reject `len > 1024` for names (`Corrupt("name too long")`). The
`u16` length is additionally bounded by the enclosing chunk's `length`.

---

## 3. Exact byte layout of every section

Below, `u8/u16/u32/u64/u128` are fixed-width little-endian; `var` is a canonical varint (§2.3);
`str` is §2.4; `rgba` is 4 bytes `r,g,b,a` (straight, non-premultiplied — matching `Rgba8`).

### 3.1 `MHDR` — main header (critical, required)

| Field | Type | Bytes | Notes |
|---|---|---|---|
| `canvas_w` | `u16` | 2 | 8..=256. Else `Corrupt("canvas size")`. |
| `canvas_h` | `u16` | 2 | 8..=256. |
| `gutter_w` | `u16` | 2 | Per-side off-canvas margin, columns. Authored value (see §5). |
| `gutter_h` | `u16` | 2 | Per-side off-canvas margin, rows. |
| `frame_count` | `u16` | 2 | 1..=1024. Else `Corrupt`. |
| `active_frame` | `u16` | 2 | Clamped to `frame_count-1` on load. |
| `active_palette` | `u16` | 2 | Clamped to `palette_count-1` on load. |
| `loop_mode` | `u8` | 1 | 0 = Loop, 1 = Once, 2 = PingPong; unknown → Loop. |
| `content_hash` | `u128` | 16 | `Document::content_hash()` (informational; see §8.3). |

`gutter_w/h` are stored (unlike v4, which re-derives them) so the file is **self-describing** and
robust to a future change of the gutter policy — at a cost of 4 bytes. Storage geometry is derived:
`storage_w = canvas_w + 2·gutter_w`, `storage_h = canvas_h + 2·gutter_h`;
`tiles_x = ceil(storage_w/32)`, `tiles_y = ceil(storage_h/32)`; `tiles_per_layer = tiles_x·tiles_y`.
The loader validates `gutter ≤ canvas` (the engine's invariant) and `storage_w,storage_h ≤ 768`
(`Corrupt` otherwise), which bounds `tiles_per_layer ≤ 24·24 = 576`.

### 3.2 `PALS` — palette table (critical, required)

```
palette_count : var            (0..=4096; else Corrupt)
repeat palette_count times:
    name        : str
    color_count : u16           (0..=1024; else Corrupt)
    colors      : rgba × color_count
```

If `palette_count == 0`, the loader injects the built-in default 16-colour ramp
(`Palette::default_palette()`), matching engine behaviour. `active_palette` (from `MHDR`) is clamped.

### 3.3 `TILE` — the content-addressed tile pool (critical, required)

Every **unique** 32×32 tile that appears anywhere in the document, stored exactly once, in
first-appearance order (§4.2). Each entry is a self-delimiting per-tile codec record (§4.3).

```
pool_count : var               (0..=MAX_TILE_POOL = 131072; else Corrupt)
repeat pool_count times:
    tile_record                (codec byte + codec-specific body; §4.3)
```

Tiles are **not** length-prefixed inside the pool: each codec is self-delimiting and the loader
decodes them sequentially, bounds-checking every byte. A truncated pool is `IoError::Truncated`.

### 3.4 `FRMS` — frames, layers, and sparse tile references (critical, required)

```
repeat frame_count times (frame_count from MHDR):
    frame_id     : u32
    duration_us  : u32          (clamped to 16_667..=1_000_000 on load)
    active_layer : u16          (clamped to layer_count-1 on load)
    layer_count  : u16          (1..=64; else Corrupt)
    repeat layer_count times:
        layer_id      : u32
        name          : str
        flags         : u8      (bit0 = visible, bit1 = locked; other bits reserved 0)
        opacity       : u8
        blend         : u8      (0 = Normal; unknown values map to Normal, not an error)
        tile_ref_count: var     (0..=tiles_per_layer; else Corrupt)
        repeat tile_ref_count times:
            grid_delta : var    (see below)
            pool_ref   : var    (< pool_count; else Corrupt)
```

**`grid_delta`** encodes the tile's linear index into the layer's storage tile grid
(`grid_index = ty·tiles_x + tx`), delta-coded so references stay small: the **first** reference in a
layer stores `grid_index` directly; each subsequent reference stores `grid_index − previous − 1`
(the gap). Because references are emitted in strictly ascending grid order, every delta is ≥ 0 and
the reconstruction is `grid_index = previous + 1 + grid_delta`. The loader rejects any
`grid_index ≥ tiles_per_layer` or a non-ascending sequence as `Corrupt`.

For each reference the loader installs `Arc::clone(pool[pool_ref])` at `grid_index` of a fresh
storage-sized `RgbaBuffer` — so **one pool tile becomes one `Arc` shared across every reference**,
reconstructing the exact in-RAM COW graph (a static background is one `Arc` again, as it was in the
editor). Absent (unreferenced) grid slots stay `None` (transparent), preserving sparsity.

### 3.5 `SELC` — selection (ancillary, optional)

Present iff the document has a live selection. The mask is **storage-sized** (its `w×h` equals the
storage dimensions), consistent with the engine.

```
mask_w    : u16
mask_h    : u16
sel_codec : u8                  (0 = raw words, 1 = bit-RLE)
if sel_codec == 0:
    word_count : var            (≤ MAX_SEL_WORDS = 9216; else Corrupt)
    words      : u64 × word_count
if sel_codec == 1:              (bit-RLE over the row-major bit stream)
    run_count  : var            (bounds below)
    runs       : var × run_count (alternating clear/set run lengths, starting with a CLEAR run)
```

The writer emits whichever of the two encodings is smaller (raw words for a busy mask; bit-RLE for
the common empty/full/rectangular marquee, which collapses to a handful of bytes). **Loaders must
support both.** In bit-RLE, runs alternate starting from bit 0 with a clear run (which may be length
0), and `Σ runs == mask_w·mask_h` exactly, else `Corrupt`. `run_count` is bounded by
`mask_w·mask_h + 1`.

On load, a mask whose `(mask_w, mask_h)` does not equal the derived storage size is **dropped**
(document still loads) — exactly v4's stale-selection policy. A word/run count inconsistent with the
dimensions is dropped too.

### 3.6 `META` — document metadata (ancillary, optional)

```
present : u16 bitmask
    bit0 title | bit1 author | bit2 created | bit3 modified | bit4 tool_name | bit5 tool_version
for each set string bit, in bit order: value : str      (title, author, tool_name, tool_version)
for created (bit2): created_unix_us  : u64
for modified (bit3): modified_unix_us: u64
```

Timestamps are microseconds since the Unix epoch, stored as `u64`. **`META` is excluded from the
determinism guarantee and from `content_hash`** (see §7): it carries volatile, environment-derived
data. The engine's deterministic `save_to_bytes(doc)` never emits `META`; the shell's
`save_with_metadata(doc, meta)` appends it.

### 3.7 `THMB` — embedded thumbnail (ancillary, optional)

```
thumb_format : u8               (0 = PNG, 1 = raw RGBA; others reserved)
thumb_w      : u16
thumb_h      : u16
thumb_len    : u32              (≤ chunk length remaining; else Corrupt)
thumb_bytes  : [u8; thumb_len]  (opaque to the engine)
```

The dependency-free engine cannot *encode* a PNG, so the thumbnail bytes are produced by the shell
(or the `codec` crate) and passed through verbatim; the engine writer stores the opaque blob and the
reader returns it opaque. Also excluded from determinism.

### 3.8 Trailer — verified file checksum

The final 16 bytes of the file are `file_checksum : u128 = hash_bytes(file[0 .. N-16])`, using the
engine's own 128-bit hash (`util::hash_bytes`). The loader recomputes it over everything before the
trailer and returns `IoError::Corrupt("checksum")` on mismatch **before** trusting any chunk body.
This is the integrity check v4 wrote but never verified.

---

## 4. Pixel / tile encoding — the heart of v6

### 4.1 The unit is the engine's 32×32 tile

The engine stores pixels as a grid of `Option<Arc<Tile>>`, `Tile = [Rgba8; 1024]` (`buffer.rs`). An
absent tile (`None`) is fully transparent and costs nothing. v6 mirrors this exactly:

- **Absent tiles are never stored and never referenced.** Sparsity is expressed by *omission* from a
  layer's reference list — there is **no dense present-flag array**, so the 9× gutter multiplier that
  taxed every empty tile in v4 (576 flag bytes per empty 256² layer) disappears.
- A **present** tile is always a full 1024-pixel tile (edge tiles include their transparent padding),
  so codecs operate on a uniform 1024-px unit and round-trips preserve the exact tile.

### 4.2 The content-addressed pool (the answer to on-disk COW / animation redundancy)

There is **one global pool for the whole file**. Building it (writer side) is a deterministic
traversal:

```
pool: Vec<Tile>            // unique tiles, in first-appearance order
index: Map<TileContent, u32>
for f in frames (order 0..F):
  for l in f.layers (order 0..L):
    for gi in 0..tiles_per_layer:          // ascending grid index
      if let Some(tile) = layer.pixels.tile(gi):   // present tiles only
        id = index.get_or_insert(tile.bytes, || { pool.push(tile); pool.len()-1 })
        emit reference (gi, id) into FRMS for this layer
```

- **Dedup key is the full tile content** (the 4096 tile bytes), so two value-equal tiles collapse to
  one pool entry regardless of `Arc` identity; a hash may be used as a fast pre-filter but content
  equality is authoritative (no hash-collision hazard). A fast path keys on the `Arc` pointer first
  (pointer-equal ⇒ identical), which makes the common animation case near-free to encode.
- **Order is first-appearance in the canonical traversal**, so identical documents produce identical
  pools and identical references ⇒ byte-identical files.

This is the whole ballgame: a static background layer shared by 64 frames is **16 tiles in the pool
and 64×16 tiny references**, not 64 full copies. Duplicated layers, held frames, and onion-skin
duplicates all collapse the same way. And because the loader turns each pool entry into a single
`Arc<Tile>` shared by every reference, **the loaded document has the same RAM footprint as the
authored one** — v4, which mints a fresh `Arc` per occurrence, does not.

Materialized-but-transparent tiles (a tile that was drawn then fully erased without `compact()`) are
preserved faithfully: such a tile is a legitimate pool entry (it encodes as `SOLID` transparent, 5
bytes) and its presence is kept, so `load(save(doc))` reproduces the exact tile-presence set and the
exact `content_hash`. The writer never silently compacts.

### 4.3 Per-tile codec menu (never expands)

Each pool entry is `codec:u8` followed by a self-delimiting body over the tile's 1024 pixels in
row-major local order. The writer computes the encoded size for every **applicable** codec and picks
the **smallest**; ties break to the **lowest codec id**. Fully deterministic; no floats.

| id | Name | Applicable when | Body | Size (bytes incl. codec byte) |
|---:|------|-----------------|------|-------------------------------|
| 0 | `RAW`     | always (the ceiling) | 1024 × `rgba` | `1 + 4096 = 4097` |
| 1 | `SOLID`   | all 1024 px equal    | one `rgba` | `1 + 4 = 5` |
| 2 | `RLE`     | always               | `(run:var, rgba)*` until Σrun=1024 | `1 + Σ(len(run)+4)` |
| 3 | `IDX4`    | ≤ 16 distinct colours | `n:u8` + `n×rgba` + 1024 × 4-bit index (512 B) | `1 + 1 + 4n + 512` |
| 4 | `IDX8`    | ≤ 256 distinct colours| `n_minus_1:u8` + `n×rgba` + 1024 × 8-bit index (1024 B) | `1 + 1 + 4n + 1024` |

- **`RAW`** guarantees no tile is ever more than 1 byte over its raw pixel bytes — the hard ceiling
  that fixes v4's worst-case RLE expansion.
- **`SOLID`** captures flat fills and (critically) transparent-but-present tiles cheaply.
- **`RLE`** captures ordinary coherent pixel art; `run` is a varint so a long run costs 1–2 bytes.
  Decode rejects `run == 0` or `Σrun > 1024` (`Corrupt`).
- **`IDX4/IDX8`** capture the noisy/dithered case that RLE inflates: a 2-colour dither tile is
  `IDX4` at `1+1+8+512 = 522` bytes instead of RLE's ~6 KB. Index tables are ordered by first
  appearance (deterministic); the 4-bit variant packs two indices per byte, low nibble first.
  Decoders reject any index `≥ n` (`Corrupt`).

**Why no whole-pool or whole-file compression?** Because it would add a dependency (`zstd`/`flate2`)
or a hand-rolled DEFLATE, both of which fight priorities 1–3 (determinism knobs, build reliability,
audit surface). The pool already removes the dominant redundancy (duplication); the per-tile menu
removes the second (poor coding of a single tile). See §11.

### 4.4 Indexed colour, honestly

v6 does **not** tie pixels to the document's named palettes. Those palettes are swatch lists, not a
constraint on pixels — a layer may contain any RGBA. Instead, indexed coding is **per-tile and
local** (`IDX4/IDX8` above): a small colour table derived from the tile's own pixels. This is
lossless and adaptive (it helps exactly the tiles that have few colours, whatever those colours are),
where a global indexed mode would be either lossy or inapplicable to arbitrary imported art.

---

## 5. Canvas vs. storage and the gutter

The engine separates the **canvas** (user-facing, 8..=256) from the **storage** area (`3w × 3h`: the
canvas plus a full-canvas gutter on each side, where moved/pasted pixels are preserved). v6 keeps the
distinction and stores enough to reconstruct it exactly, but pays nothing for empty gutter:

- `MHDR` stores `canvas_w/h` **and** `gutter_w/h` (4 bytes) → the file is self-describing; storage
  and the tile grid are derived from them (§3.1). Storing the gutter (v4 re-derives it) future-proofs
  the file against a change to `Document::gutter_for`.
- Gutter **content** is real, recoverable data, so it is persisted — but only via the sparse tile
  references (§3.4/§4.2). An empty gutter contributes **zero** bytes (no tiles, no flags). This is the
  direct fix for v4's "the gutter triples every dimension" tax: the cost now scales with *occupied*
  tiles, not with the storage grid.
- Tile references use the **storage** tile grid, so a moved pixel sitting off-canvas round-trips to
  the same off-canvas position. If a future build changes the gutter policy so the derived storage
  differs from the file's authored `gutter_w/h`, the loader reconstructs at the authored geometry and
  re-blits into the new storage at the canvas origin (the same lift v4 already does for old files).

---

## 6. Selection serialization

Covered byte-for-byte in §3.5. Design notes:

- The mask is **storage-sized** and serialized as its packed 1-bit words (`Mask::as_words`,
  row-major, `u64`), or as **bit-RLE** when that is smaller — the common empty/full/marquee selection
  collapses to a few bytes instead of the 72 KB raw worst case for a 768×768 mask.
- Selection is an **ancillary** chunk: a reader that skips it simply loads a document with no
  selection, which is always safe. It is persisted for crash-recovery parity with the editor (the
  mask travels *inside* the document), but the **combine mode** (Replace/Add/…) stays transient tool
  state and is not persisted.
- Selection is **not** folded into `content_hash` (§8.3), so thumbnail caches and goldens don't churn
  when only the selection changes — preserving the v4 property.

---

## 7. Metadata and thumbnail

Both are **optional, ancillary, and deliberately outside the deterministic core**:

- **What's in-file (optional):** title, author, created/modified timestamps, tool name + version
  (`META`), and a thumbnail blob (`THMB`). This lets a `.mkpx` travel self-contained — a real
  improvement over v4, where all of this lives only in shell sidecars (`meta.json`, `thumb.png`).
- **Why they're carved out of determinism:** timestamps and thumbnails are environment- and
  time-dependent; if they were in the deterministic payload, two saves of the same document would
  differ and goldens would fork. So:
  - The engine's `save_to_bytes(doc)` — the function tests and goldens use — emits **only** the
    deterministic critical chunks (+ `SELC` if a selection exists). It is byte-identical across runs
    and platforms.
  - The shell's `save_with_metadata(doc, meta, thumb)` appends `META`/`THMB`. These bytes *are*
    covered by the file checksum (integrity) but are *excluded* from the determinism claim and from
    `content_hash`.
- **Thumbnail production stays out of the engine** (which can't encode PNG); `THMB` is an opaque
  pass-through so the dependency-free charter holds.

---

## 8. Integrity, versioning, forward-compatibility

### 8.1 Integrity

- **Verified whole-file checksum** (§3.8): a 128-bit `hash_bytes` over `file[0 .. N-16]`, checked
  before any chunk body is trusted. Catches truncation and bit-rot that don't happen to violate a
  structural invariant — the gap v4 left open.
- **Structural validation** is layered on top: magic, version, every count against a hard cap, every
  index against its domain, every varint canonical/in-range, every chunk length against the slice.

### 8.2 Versioning

- `version:u16 = 6` in the preamble identifies the container generation. A v6 reader accepts exactly
  `6` and returns `IoError::UnsupportedVersion(v)` otherwise. (No migration path is required; the app
  is pre-release. Older files are simply not v6.)
- **Growth without a version bump** is the normal case, handled by the chunk model (§8.3), so the
  `version` field is reserved for a genuinely incompatible reframing of the container itself.

### 8.3 Forward-compatibility

- **Ancillary chunks are skippable.** A future `Cxyz` ancillary chunk (e.g. layer groups, tags,
  colour-profile) is added with `critical=0`; every existing reader skips it by `length` and loses
  nothing it understood. New readers pick it up.
- **Critical chunks are gated.** A genuinely load-bearing new section is added with `critical=1`; old
  readers correctly refuse rather than silently mis-load — `UnknownCriticalChunk`.
- **`content_hash`** in `MHDR` mirrors `Document::content_hash()` (canvas size + per-frame duration +
  per-layer name/visible/locked/opacity + present-tile hashes). It excludes selection and metadata.
  It is stored for cache/golden identity and *may* be recomputed and cross-checked on load as a cheap
  extra guard; it is **not** the integrity mechanism (that's §8.1).

---

## 9. Error handling and hardening

The loader is a single forward pass that **never panics** and returns a typed error:

```rust
pub enum IoError {
    BadMagic,
    UnsupportedVersion(u16),
    UnknownCriticalChunk([u8; 4]),
    Truncated,
    Corrupt(&'static str),   // carries a short reason
}
```

Hardening rules (each maps to a concrete check):

1. **Bounded allocations only.** No `Vec::with_capacity(n)` where `n` comes from the file until `n`
   has been checked against a hard cap **and** against the bytes actually remaining. Caps:

   | Quantity | Cap | Rationale |
   |---|---|---|
   | canvas w/h | 8..=256 | engine invariant |
   | storage w/h | ≤ 768 | canvas + full gutter |
   | `tiles_per_layer` | ≤ 576 | derived from storage |
   | `frame_count` | 1..=1024 | `MAX_FRAMES` |
   | `layer_count` | 1..=64 | `MAX_LAYERS` |
   | `pool_count` | ≤ 131072 | `MAX_TILE_POOL`; bounds pool decode RAM to ≤ 512 MiB |
   | `palette_count` | ≤ 4096 | sanity |
   | `color_count` | ≤ 1024 | sanity |
   | name length | ≤ 1024 | sanity |
   | `word_count` (selection) | ≤ 9216 | `MAX_SEL_WORDS` (768×768 bits) |
   | varint | ≤ 5 bytes / ≤ u32 | canonical LEB128 |
   | any chunk `length` | ≤ bytes-before-trailer | framing |

2. **Every read is bounds-checked** against the slice (the `Reader` primitive returns `Truncated`
   rather than indexing out of range).
3. **Every index is domain-checked:** `pool_ref < pool_count`; `grid_index < tiles_per_layer` and
   strictly ascending; colour-table index `< n`; active indices clamped.
4. **No unbounded loops.** Id generators are seeded with `IdGen::starting_at(max_id + 1)` (never a
   warm-up loop), so a crafted id like `0xFFFF_FFFF` cannot spin the loader — preserving the v4 [F-2]
   mitigation. RLE/varint decoders make monotonic progress with a per-step bound (`Σrun ≤ 1024`;
   ≤ 5 varint bytes).
5. **Checksum first.** The trailer checksum is verified before chunk bodies are trusted, so a
   corrupted length/count is caught up front in the common bit-rot case.
6. **Optional file-size guard.** The loader may reject an input slice larger than a configured
   `MAX_FILE` (e.g. 256 MiB) up front; all internal caps already bound work below that regardless.

The Tier-1 round-trip gate is preserved: `load(save_to_bytes(doc))` yields a document with an equal
`content_hash()` (same tiles, presence set, palettes, durations, layer attributes, ordering).

---

## 10. Worked size examples (v6 vs. v4)

Fixed overhead in v6 is: preamble 8 B + `MHDR` (9+31) + `PALS` (9 + table) + `TILE` (9 + pool) +
`FRMS` (9 + structure) + trailer 16 B. Structural per-frame/per-layer cost is a handful of bytes;
the interesting numbers are the pixel bodies.

### 10.1 Empty 256×256 document (1 frame, 1 empty layer)

| | v4 | v6 |
|---|---:|---:|
| Present-tile bookkeeping | 576 present-flag bytes (24×24 storage grid) | **0** (no tiles referenced) |
| Approx total | **≈ 723 B** | **≈ 150 B** |

v6 win: **~4.8×**, and it *scales* — the empty-gutter tax that grows with canvas size in v4 is gone.

### 10.2 64-frame animation, one detailed static background + one small moving sprite (128×128)

Assume the background covers the canvas (4×4 = 16 tiles, each a detailed ~2 KB-RLE tile) and is
identical in all 64 frames; a foreground sprite touches ~4 tiles per frame, mostly unique.

| | v4 | v6 |
|---|---:|---:|
| Static background | 64 × 16 × ~2 KB re-serialized = **≈ 2.0 MB** | 16 unique tiles in pool once = **≈ 32 KB** + 64×16 refs ≈ **≈ 3 KB** |
| Foreground (~256 unique tiles) | ~256 × ~2 KB = ~0.5 MB | ~256 × ~2 KB = ~0.5 MB (pooled once) |
| Present-flag tax | 144 tiles × 2 layers × 64 frames = **≈ 18 KB** | **0** |
| Approx total | **≈ 2.5 MB** | **≈ 0.57 MB** |

v6 win: **~4–5×**, dominated entirely by collapsing the duplicated background — the headline result.
Load is also *faster*: each unique tile is decoded once (not 64×), and references become `Arc`
clones.

### 10.3 Noisy 128×128 frame fully covered by a 2-colour dither

Canvas region = 16 tiles, each an identical 2-colour checkerboard.

| | v4 | v6 |
|---|---:|---:|
| Per tile | RLE ≈ 6 KB (1.5× **expansion** — every pixel breaks the run) | `IDX4` = 522 B |
| Dedup | none → 16 × 6 KB | identical pattern → **1** pooled tile = 522 B |
| Approx pixel total | **≈ 98 KB** | **≈ 0.5 KB** (or ~8.3 KB if the 16 tiles differ) |

v6 win: **~12×** even without dedup (never-expand codec menu), and ~190× with dedup. This is the case
v4 handles *worst*.

---

## 11. Over-engineering watch — what we deliberately left out

Things considered and **rejected**, to keep the format simple, deterministic, and dependency-free:

- **General-purpose compression (zstd / DEFLATE / a hand-rolled entropy coder).** Rejected: adds a
  dependency (fights reliable Windows/Android builds and the fast headless loop) or a large,
  determinism-sensitive, audit-heavy hand-roll. The **pool + per-tile menu** already removes the two
  dominant redundancies (duplication, poor single-tile coding) in a few dozen lines. If a real corpus
  later shows a big residual win, a single *ancillary* `Czst` "whole-pool compressed" chunk could be
  added behind a feature flag without touching the core — but not until measured.
- **Cross-tile / cross-frame delta filters (predictors, motion vectors).** Rejected: complex, easy to
  get non-deterministic, and mostly redundant with exact-tile dedup for pixel-art animation (which
  tends to reuse whole tiles, not shift them by sub-tile amounts).
- **Random access / streaming / partial (single-frame) loads.** Rejected: the whole-file, in-memory
  model comfortably meets the < 300 ms budget (the loader is one pass; unique tiles decode once). The
  chunk framing means we *could* add an index later, but building one now is speculative.
- **A global indexed-colour mode keyed to document palettes.** Rejected as lossy/inapplicable to
  arbitrary art; per-tile local `IDX4/IDX8` gets the win losslessly (§4.4).
- **Free-form key/value metadata soup.** Rejected in favour of a small fixed `META` field set — fewer
  ways to be non-deterministic or oversized, and everything the shell actually needs.
- **Reserved padding / alignment.** Rejected: growth is via chunks, not reserved bytes; alignment
  buys nothing for a byte-oriented, whole-file parse.

**The simplest version that still wins.** If forced to cut to the bone, ship exactly these three
ideas and nothing else: **(1)** the chunked container with a verified checksum, **(2)** the
content-addressed tile pool with sparse per-layer references (this alone captures the animation win
and deletes the present-flag tax), and **(3)** two tile codecs — `RAW` and `RLE` — with the
"smallest wins" rule. That minimal subset already beats v4 decisively on every §10 example; `SOLID`,
`IDX4`, `IDX8`, `SELC`-RLE, `META`, and `THMB` are strictly additive polish that each pay for
themselves in bytes or portability, and each can be added or dropped independently.

---

## 12. Cheat sheet — field order

```
Preamble:  "MKPX"(4)  version:u16=6  reserved:u16=0
Chunk TLV: type:[u8;4]  flags:u8(bit0=critical)  length:u32  payload[length]

MHDR: canvas_w:u16 canvas_h:u16 gutter_w:u16 gutter_h:u16
      frame_count:u16 active_frame:u16 active_palette:u16 loop_mode:u8 content_hash:u128
PALS: palette_count:var  [ name:str color_count:u16 (rgba×color_count) ]…
TILE: pool_count:var  [ codec:u8 body… ]…          # body per §4.3, self-delimiting
      codec 0 RAW  : rgba×1024
      codec 1 SOLID: rgba
      codec 2 RLE  : (run:var, rgba)…  until Σrun=1024
      codec 3 IDX4 : n:u8         (n×rgba) (4-bit index × 1024)   # ≤16 colours
      codec 4 IDX8 : n_minus_1:u8 (n×rgba) (8-bit index × 1024)   # ≤256 colours
FRMS: [ frame_id:u32 duration_us:u32 active_layer:u16 layer_count:u16
        [ layer_id:u32 name:str flags:u8 opacity:u8 blend:u8
          tile_ref_count:var  [ grid_delta:var pool_ref:var ]… ]… ]…
SELC?: mask_w:u16 mask_h:u16 sel_codec:u8
       (0) word_count:var (u64×word_count)   |   (1) run_count:var (var×run_count)
META?: present:u16  [strings in bit order]  [created_unix_us:u64] [modified_unix_us:u64]
THMB?: thumb_format:u8 thumb_w:u16 thumb_h:u16 thumb_len:u32 bytes[thumb_len]

Trailer:  file_checksum:u128 = hash_bytes(file[0 .. N-16])
str  := len:u16 + utf8[len]            (lossy on read, ≤1024 for names)
var  := canonical unsigned LEB128, ≤5 bytes for u32, reject overlong
ints := little-endian; rgba := r,g,b,a straight (non-premultiplied)
```

---

## 13. Reference implementation sketch (informative)

Save (deterministic core):

```
compact-free traversal builds (pool, refs)         // §4.2
write preamble
write MHDR, PALS
write TILE  { pool_count; for tile in pool: min-size codec record }   // §4.3
write FRMS  { for frame: header; for layer: header; ascending refs }
if doc.selection: write SELC (min of raw-words / bit-RLE)
append file_checksum = hash_bytes(bytes_so_far)
```

Load (single pass, panic-free):

```
check magic/version; verify trailer checksum over file[0..N-16]
scan chunks in [8..N-16] -> table{type -> (off,len,flags)}   // reject dup critical / unknown critical
MHDR -> geometry, counts, active indices (validated & clamped)
PALS -> palettes (or default ramp if empty)
TILE -> Vec<Arc<Tile>> pool  (decode each codec once; bounds-checked)
FRMS -> for each layer: fresh storage RgbaBuffer; for each ref: install Arc::clone(pool[ref]) at grid_index
SELC -> mask if dims match storage, else drop
META/THMB -> opaque/optional
seed IdGen::starting_at(max_id+1); assemble Document
```

The load path allocates `pool_count` `Arc<Tile>` once and then only clones `Arc`s, so a 64-frame
animation with a shared background costs one decode of the background and 63 pointer clones — the
inverse of v4's per-occurrence re-decode, and the reason the < 300 ms budget is met with wide margin.

*End of v6 specification.*
