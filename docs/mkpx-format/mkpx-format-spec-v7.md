# `.mkpx` Format — Specification **v7**

> **Status.** A complete, implementable design for a *brand-new, from-scratch* binary document
> format for the Makapix Editor. This is a clean break: **no backward compatibility** with the
> current on-disk format is provided or required. A v7 reader reads only v7.
>
> **Audience.** A Rust engineer implementing `crates/engine/src/io.rs` against the existing data
> model (`document.rs`, `buffer.rs`, `selection.rs`, `color.rs`, `util.rs`). Every structure here
> maps directly onto types that already exist in the engine; no new engine dependencies are
> introduced.
>
> **Charter constraints honoured.** Pure-Rust, **dependency-free** codec; `#![forbid(unsafe_code)]`
> compatible; **little-endian, integer-exact, no floats** in the persisted pixel path; a
> **panic-free** loader that rejects hostile input with typed errors and bounded allocations;
> deterministic, **byte-identical output for identical documents** so goldens never fork per platform.

---

## 1. Design goals and priorities

v7 is optimised, in strict priority order, for:

1. **Faithful, lossless capture** of the engine's document model — canvas, gutter/storage, frames,
   layers, palettes, animation, and the live selection — with a `load(save(doc))` semantic
   round-trip that the engine can gate in CI.
2. **Determinism.** One document ⇒ exactly one byte sequence, on every platform, forever. All
   integers little-endian; no floats anywhere in the file; a fully specified *canonical writer*
   (traversal order, dedup order, per-tile method choice, tie-breaks) so goldens are stable.
3. **Hardening.** A hostile or truncated file can never panic, never over-allocate, and never
   produce an inconsistent document. Every length and count is bounds-checked *before* it is
   trusted; every chunk is CRC-verified; the reconstructed document is hash-verified.
4. **Small files that mirror the engine's own compression wins.** The engine already keeps pixels
   sparse (empty tiles cost nothing) and copy-on-write (identical `Arc<Tile>` shared across
   frames/layers). v7's headline job is to **carry those two wins onto disk**, which the current
   format throws away: it deduplicates identical tiles globally, and it never pays a per-tile tax
   for empty gutter.
5. **Speed.** Single forward pass, table-driven CRC, O(present-pixels) reconstruction, and — as a
   bonus — the on-disk tile pool maps 1:1 onto `Arc<Tile>` sharing, so loading *restores* in-RAM
   COW instead of exploding it. The 64-frame / 8-layer / 128×128 budget (< 300 ms) is met with
   large margin.
6. **Self-description and forward-compatibility.** A real chunked container (type + length + CRC)
   with a critical/ancillary rule, so a `.mkpx` can carry its own thumbnail and metadata and travel
   without sidecar files, and so future readers can skip data they don't understand — or correctly
   *refuse* data they must understand but don't.

**Tradeoffs taken deliberately.** We do **not** add a general-purpose LZ/entropy stage (it would
mean a dependency or a large in-house LZ, for marginal gain over dedup + indexed color on real
pixel art). We do **not** support partial/streaming/random-access loads (files are small; the
whole-file model is kept). We keep the format *whole-document* and *state-based* — no undo history,
no action log. See §11.

---

## 2. Container structure and framing

A v7 file is an **8-byte signature** followed by a sequence of **chunks**, ending with the `ENDF`
chunk. This is a PNG-style container: self-framed, integrity-checked, and forward-extensible.

### 2.1 Signature (8 bytes, fixed)

```
0x89 0x4D 0x4B 0x50 0x58 0x0D 0x0A 0x1A
 │    └─────"MKPX"────┘   │    │    └ 0x1A  Ctrl-Z: halts `type`/`cat` dumping binary to a console
 │                        │    └── 0x0A  LF   ┐ detect newline translation by text-mode transfer
 │                        └─────── 0x0D  CR   ┘
 └── 0x89  high bit set: detect 7-bit-stripping / text-mode mangling
```

A file whose first 8 bytes are not exactly this ⇒ `BadMagic`. The signature is **distinct from any
prior Makapix format** (which began with the ASCII bytes `MKPX`), so old files cleanly fail the
magic check rather than mis-parsing.

### 2.2 Chunk framing

Every chunk, in order:

| Field     | Type     | Bytes | Notes                                                        |
|-----------|----------|-------|-------------------------------------------------------------|
| `length`  | `u32` LE | 4     | Length of `payload` only (not type/CRC). Bounds-checked.    |
| `type`    | `[u8;4]` | 4     | Four ASCII letters (`A`–`Z`, `a`–`z`). Identifies the chunk. |
| `payload` | bytes    | `length` | Chunk-specific. May be empty.                            |
| `crc`     | `u32` LE | 4     | CRC-32 (IEEE, §8.1) over `type` **and** `payload`.          |

To advance past any chunk a reader needs only `length`: read 4 + 4 + `length` + 4 bytes. This is how
a reader **skips unknown data** (§2.4).

### 2.3 Chunk types (this version)

| Type   | Crit? | Once? | Purpose                                                     | §  |
|--------|-------|-------|------------------------------------------------------------|----|
| `HEAD` | crit  | 1     | Document header: dimensions, geometry, loop, active indices, content hash. | 3 |
| `PALT` | crit  | 1     | Palette table.                                             | 4  |
| `TILE` | crit  | 1     | Global tile pool (unique 32×32 tile blobs).               | 5  |
| `CELS` | crit  | 1     | Cel pool (unique sparse tile-maps = per-layer pixel content). | 6 |
| `FRMS` | crit  | 1     | Frames and their layers (attributes + cel references).     | 7  |
| `seln` | anc   | 0/1   | Selection mask.                                            | 8  |
| `meta` | anc   | 0/1   | Document metadata (title/author/timestamps/tool/license).  | 9  |
| `thmb` | anc   | 0/1   | Embedded PNG thumbnail.                                    | 9  |
| `ENDF` | crit  | 1     | End-of-file marker (empty payload).                       | 10 |

### 2.4 Critical vs. ancillary; the forward-compat rule

Criticality is encoded in **the case of the type's first letter** (as in PNG): **uppercase first
letter ⇒ *critical*; lowercase first letter ⇒ *ancillary*.** The remaining three letters' case is
free (they are chosen here for readability).

A reader that encounters a chunk type it does not recognise:

* **Ancillary** (first letter lowercase): **skip it** (use `length`) and continue. This is the
  mechanism by which a future minor version can add optional data (new metadata forms, extra
  sidecar-like blobs) that old readers safely ignore.
* **Critical** (first letter uppercase): **fail** with `UnknownCriticalChunk`. The file requires
  understanding this chunk to be interpreted correctly, and this reader cannot, so it must refuse
  rather than silently produce a wrong document.

This makes "ignore unknown chunks" a *real, enforced* property — not the incidental "reader happens
to stop early" behaviour of the previous format.

### 2.5 Ordering rules (canonical writer, tolerant reader)

The **canonical writer** emits chunks in exactly this order:

```
signature, HEAD, [meta], PALT, TILE, CELS, FRMS, [seln], [thmb], ENDF
```

The **reader** enforces:

* `HEAD` is the **first** chunk; `ENDF` is the **last** chunk and the file ends immediately after
  its CRC (guards against a truncated or trailing-garbage tail).
* Each critical chunk `HEAD PALT TILE CELS FRMS ENDF` appears **exactly once**, in the relative
  order `HEAD → PALT → TILE → CELS → FRMS → ENDF` (ancillary chunks may appear anywhere between
  `HEAD` and `ENDF`). Because `TILE` precedes `CELS` precedes `FRMS`, every reference resolves in a
  single forward pass.
* Each ancillary chunk appears **at most once**.

Any violation ⇒ `Corrupt`. Fixing the order in the reader keeps it a single forward streaming pass
(no whole-file buffering of chunk offsets) and keeps the canonical byte layout unambiguous.

---

## 3. `HEAD` — document header

Fixed 34-byte payload, little-endian:

| Off | Field            | Type       | Bytes | Meaning / validation                                             |
|-----|------------------|------------|-------|------------------------------------------------------------------|
| 0   | `format_major`   | `u8`       | 1     | `= 7`. If `> 7` ⇒ `UnsupportedVersion` (refuse). If `< 7` ⇒ `UnsupportedVersion`. |
| 1   | `format_minor`   | `u8`       | 1     | `= 0`. A reader for major 7 accepts any minor (unknown minors only add ancillary chunks / reserved fields). |
| 2   | `canvas_w`       | `u16`      | 2     | 8..=256, else `Corrupt`.                                          |
| 4   | `canvas_h`       | `u16`      | 2     | 8..=256, else `Corrupt`.                                          |
| 6   | `storage_w`      | `u16`      | 2     | Full storage width incl. gutter (§5.2 geometry). Validated (below). |
| 8   | `storage_h`      | `u16`      | 2     | Full storage height incl. gutter.                                |
| 10  | `loop_mode`      | `u8`       | 1     | 0=Loop, 1=Once, 2=PingPong; any other value ⇒ Loop (tolerant).  |
| 11  | `flags`          | `u8`       | 1     | Reserved; writer writes 0; reader ignores unknown bits.          |
| 12  | `active_frame`   | `u32`      | 4     | Clamped to `frame_count-1` on load.                              |
| 16  | `active_palette` | `u16`      | 2     | Clamped to `palette_count-1` on load.                            |
| 18  | `content_hash`   | `u128`     | 16    | `doc.content_hash()` (`util::Hash`), LE. Verified after load (§8.2 of hardening / §3.1). |

Total: **34 bytes**.

**Storage-geometry validation.** The gutter is a *derived* engine policy (`Document::gutter_for`),
not free-form. The reader computes `expected = gutter_for(canvas)` and requires:

```
storage_w == canvas_w + 2*gutter.w   and   storage_h == canvas_h + 2*gutter.h
```

i.e. today, `storage_w == 3*canvas_w` and `storage_h == 3*canvas_h`. Mismatch ⇒
`Corrupt("storage geometry")`. Storing the storage dimensions **explicitly** (rather than only
re-deriving them, as the old format did) buys three things: the file is self-describing and
greppable; the cel grid's index bounds (§6) are checked against a value carried *in the file*; and a
future engine that changes the gutter policy needs only to relax this equation, not a format bump.
See §5.2 for how the storage grid, not the canvas, is what tiles are addressed against.

**Derived grid.** From `storage_w/h` the reader derives, once:

```
tiles_x   = ceil(storage_w / 32)
tiles_y   = ceil(storage_h / 32)
num_tiles = tiles_x * tiles_y            // e.g. 256² canvas → 768² storage → 24×24 = 576
```

`num_tiles` is the modulus for every grid index in the cel pool.

### 3.1 The content hash is *used*

`content_hash` is the engine's existing 128-bit FNV-derived document hash
(`Document::content_hash`, over canvas size + every frame's duration + every layer's
name/visible/locked/opacity + present-tile pixels). After the reader has fully reconstructed the
`Document`, it **recomputes** the hash and compares:

```
if rebuilt.content_hash() != head.content_hash { return Err(Corrupt("content hash mismatch")); }
```

This makes loading *semantically self-verifying*: a successful load guarantees a document that
hashes to the stored value. Combined with per-chunk CRC (byte integrity), integrity is now real —
directly closing the old format's "footer hash written but never verified" gap. The hash covers the
*artwork only*; it excludes the selection and all ancillary chunks, so selection or metadata edits
never churn the hash (matching the engine's existing thumbnail-cache/golden discipline).

---

## 4. `PALT` — palettes

Payload:

```
palette_count : uvarint            // 0..=1024, else Corrupt
repeat palette_count:
    name        : string           // §2.6-style: uvarint byte-len (≤ 4096) + UTF-8
    color_count : uvarint           // 0..=65536, else Corrupt
    colors      : { r:u8, g:u8, b:u8, a:u8 } × color_count   // straight RGBA
```

Palettes are stored in document order; `active_palette` (in `HEAD`) indexes into them. If
`palette_count == 0`, the loader injects the built-in default 16-colour ramp
(`Palette::default_palette`) and clamps `active_palette` to 0 — matching current behaviour so a
palette-less file still opens usefully.

**Primitive: `uvarint`** (used throughout). Unsigned LEB128, little-endian 7-bit groups, high bit =
"more follows". The writer always emits the **minimal** encoding. The reader rejects an encoding
longer than 5 bytes or one that overflows `u32` ⇒ `Corrupt("varint")`. Every `uvarint` that sizes an
allocation is additionally clamped against the remaining input length before any `Vec` is reserved
(§8.2).

**Primitive: `string`** = `uvarint` byte length (capped at 4096, else `Corrupt("string too long")`)
followed by that many bytes, validated as **strict UTF-8** (`Corrupt("invalid utf-8")` on failure —
stricter than the old lossy decode; names originate as valid Rust `String`s, so valid files always
pass, and crafted invalid bytes are rejected).

---

## 5. `TILE` — the global tile pool

This chunk, together with `CELS` (§6), is the heart of v7 and the biggest departure from the prior
format. It stores **each distinct 32×32 tile exactly once for the whole document**, regardless of
how many layers, frames, or grid positions use it.

### 5.1 Why a pool

The engine's `RgbaBuffer` is a grid of 32×32 tiles; identical tiles are `Arc`-shared in RAM
(copy-on-write). A static background repeated across 1024 frames is *one* `Arc<Tile>` in memory. The
prior format serialised every frame's every tile in full, so that one shared tile hit the disk up to
1024 times. v7 restores the sharing: tiles live in a content-addressed pool and are referenced by
index. This also deduplicates a tile that appears at *different grid positions* (a repeated motif),
which even the in-RAM COW does not, because COW is per-buffer-slot.

Absent (fully transparent) tiles are **never** in the pool and never referenced — sparsity is free
(the prior format's per-tile "present" byte, paid even for every empty gutter tile, is gone; see the
256² example in §12).

### 5.2 Canvas, storage, and the gutter — all uniform

The engine keeps a **full gutter of one canvas on every side** (`storage = 3w × 3h`) so pixels
pushed off-canvas by Move/paste are preserved. v7 makes **no distinction** between canvas tiles and
gutter tiles: it stores the present tiles of the *whole storage grid*. Off-canvas content in the
gutter is therefore preserved exactly, and **empty gutter tiles cost nothing** (they are simply
absent from every cel). The canvas-vs-storage geometry is recorded once in `HEAD` (`canvas_*` +
`storage_*`); there is no separate canvas-only pixel path.

### 5.3 Chunk layout

```
tile_count : uvarint                // 0 .. TILE_POOL_MAX (§8.2), else Corrupt
repeat tile_count:
    method  : u8                    // 0=RAW 1=SOLID 2=RLE 3=INDEXED (unknown ⇒ Corrupt)
    payload : method-specific, self-delimiting (below)
```

Tiles are referenced elsewhere by 0-based index into this pool (`0 .. tile_count`).

### 5.4 Per-tile methods

A tile is 1024 pixels in **row-major local order** (y·32 + x), each a straight `Rgba8`.

**`0x00` RAW** — 4096 bytes, `[r,g,b,a] × 1024`. The guaranteed fallback; a tile never costs more
than `1 + 4096` bytes, so encoding **never expands** (unlike the prior RLE, which could bloat noisy
tiles to 1.5×).

**`0x01` SOLID** — 4 bytes `[r,g,b,a]`. The entire tile is this one colour. Covers flat fills and,
notably, a *materialised-but-transparent* tile (`SOLID 00 00 00 00`), so presence is preserved
losslessly (§6.3).

**`0x02` RLE** — run-length over the row-major stream:
```
run_count : uvarint                 // ≥ 1
repeat run_count: { run:uvarint(1..=1024), rgba:[u8;4] }
```
The reader validates `Σ run == 1024` and every `run ≥ 1`, else `Corrupt("rle")`. `uvarint` runs make
short runs cheaper than the prior fixed `u16`.

**`0x03` INDEXED** — a per-tile local palette plus bit-packed indices. This is the pixel-art
workhorse and the single biggest size win on dithered/limited-palette tiles, exactly where RLE lost.
```
ncolors : u8                        // 2..=255 literal; 0 encodes 256. (1 colour would be SOLID.)
palette : { r,g,b,a } × ncolors     // distinct colours in first-appearance (row-major) order
indices : bit-packed, k bits each, 1024 indices, row-major
          where k = ceil(log2(ncolors))  ∈ 1..=8   (derived, not stored)
          packed LSB-first within each byte, low index first
          → exactly ceil(1024*k / 8) = 128*k bytes
```
The reader derives `k`, reads `128*k` index bytes, and validates every index `< ncolors`
(`Corrupt("index")`). Sizes: a 2-colour tile = `1+8+128 = 137 B`; 16-colour = `1+64+512 = 577 B`;
256-colour = `1+1024+1024 = 2049 B` — all well under RAW's 4096.

### 5.5 Canonical method choice (writer)

For each unique tile the canonical writer computes the encoded size of every *applicable* method and
picks the **smallest**; ties break toward the **lowest method id**. Applicability: SOLID iff all
1024 pixels equal; INDEXED iff distinct-colour count ≤ 256; RLE and RAW always. This is pure integer
logic (no float), so the choice is identical on every platform → byte-identical goldens.

---

## 6. `CELS` — the cel pool (per-layer pixel content)

A **cel** is one layer's pixel content: a sparse map from tile-grid-index → tile-pool-index. Cels
are themselves pooled and deduplicated, so a layer whose pixels are identical across many frames
(the classic static background, or a repeated key frame) is stored **once** and referenced many
times. Tile dedup (§5) removes duplicate *pixels*; cel dedup removes duplicate *layouts*. Together
they collapse animation redundancy to near-optimal.

### 6.1 Chunk layout

```
cel_count : uvarint                 // 0 .. CEL_POOL_MAX (§8.2)
repeat cel_count:
    present_count : uvarint          // 0 .. num_tiles
    repeat present_count:
        gap       : uvarint          // grid index delta − 1 (see below)
        tile_ref  : uvarint          // index into TILE pool: 0 .. tile_count
```

**Grid indices** are emitted **strictly ascending** and **delta-encoded** to stay small even for a
large sparse grid. Decoding: start `prev = -1`; for each entry, `grid_index = prev + 1 + gap`; then
`prev = grid_index`. The reader validates `grid_index < num_tiles` and strict ascent, and
`tile_ref < tile_count`, else `Corrupt("cel")`. `present_count == 0` is a valid **empty cel** — a
fully transparent layer — and all such layers dedup to it.

Cels are referenced by 0-based index into this pool (`0 .. cel_count`) from `FRMS` (§7).

### 6.2 Reconstruction restores COW

The reader materialises each tile-pool entry into exactly **one** `Arc<Tile>`. For each cel it builds
a prototype storage-sized `RgbaBuffer`, placing that shared `Arc` at each present grid slot. A layer
referencing the cel takes a cheap clone of the prototype (a `Vec<Option<Arc<Tile>>>` clone = `Arc`
clones only). Thus every layer that shared a tile in the original document **shares the same
`Arc<Tile>` again after load** — the on-disk pool maps 1:1 onto in-RAM COW, so loading rebuilds the
memory-sharing the editor relies on instead of exploding it into private copies.

### 6.3 Presence fidelity

Presence is taken from the engine's own signal — `RgbaBuffer::tile_bytes(i).is_some()` — exactly as
today. A present-but-transparent tile is a real pool entry (`SOLID 00000000`) referenced by its
cel, so it survives the round-trip and the `content_hash` check (§3.1) even though it is visually
identical to absence. This preserves the engine's present/absent distinction bit-for-bit.

---

## 7. `FRMS` — frames and layers

Payload:

```
frame_count : uvarint                // 1..=1024 (MAX_FRAMES), else Corrupt
repeat frame_count:
    frame_id     : u32               // stable identity; re-seeds IdGen (below)
    duration_us  : u32               // clamped to 16_667..=1_000_000 on load
    active_layer : uvarint            // clamped to layer_count-1 on load
    layer_count  : uvarint            // 1..=64 (MAX_LAYERS), else Corrupt
    repeat layer_count:
        layer_id   : u32             // stable identity; re-seeds IdGen
        name       : string
        attr_flags : u8              // bit0 = visible, bit1 = locked; other bits reserved (0)
        opacity    : u8              // 0..=255
        blend      : u8              // 0 = Normal; reserved for future modes (unknown ⇒ Normal)
        cel_ref    : uvarint          // index into CELS pool
```

`frame_id` / `layer_id` are persisted (as in the current model) so stable identities survive a
save/load. On load, the id generators are seeded to `max_seen_id + 1` **directly**
(`IdGen::starting_at`), never by counting up to a stored id — a crafted `0xFFFFFFFF` cannot spin the
loader (this preserves the existing hardening property). Ids do not participate in `content_hash`.

`active_frame` (from `HEAD`) and each frame's `active_layer` are clamped to valid ranges on load.
`duration_us` is clamped like the engine's `clamp_duration`. `frame_count == 0` ⇒ `Corrupt` (a
document always has ≥ 1 frame).

---

## 8. `seln` — selection

The engine's selection is a **first-class, storage-sized** 1-bit `Mask`, persisted for crash safety.
Ancillary because it is editor state, not artwork: a reader that skips it merely loses the selection.

Payload:

```
mask_w     : u16                     // must equal storage_w
mask_h     : u16                     // must equal storage_h
word_count : uvarint                 // must equal ceil(mask_w*mask_h / 64); ≤ MAX_SEL_WORDS = 9216
words      : u64 × word_count        // packed 1-bit-per-pixel, row-major, LE (Mask::as_words layout)
```

On load, a mask whose `(w,h)` do not match the document's storage size is **dropped** (the document
still loads without a selection) — identical to today's "stale-size mask" handling and the natural
guard for any size mismatch. `word_count > MAX_SEL_WORDS` ⇒ `Corrupt` (bounds the allocation against
a crafted count; 9216 is the largest legal storage grid, 768×768/64). `Mask::from_words` validates
the exact word count and defensively trims out-of-range tail bits. The combine *mode* (Replace/Add/…)
is transient tool state and is **not** persisted, matching the current model.

Absent `seln` chunk ⇒ no selection (the common case; nothing is written).

---

## 9. `meta` and `thmb` — self-describing metadata (both ancillary, optional)

The prior format carried **no** identity and kept title/author/timestamps in a sidecar `meta.json`
and the thumbnail in a sidecar `thumb.png`. v7 *optionally embeds* both so a single `.mkpx` can
travel without its directory (share one file, not a folder). They remain **ancillary and excluded
from the determinism gate** (§3.1): the canonical writer used for goldens omits volatile fields
(timestamps) unless explicitly supplied, so two saves of the same artwork stay byte-identical. The
shell may still keep sidecars for fast library listing; the two are not mutually exclusive.

**`meta`** — a small key/value set:
```
field_count : uvarint                // ≤ 256
repeat field_count:
    key   : string                   // short ASCII key
    value : string                   // UTF-8
```
Well-known keys (all optional, free-form otherwise): `title`, `author`, `created`, `modified`
(RFC-3339 UTF-8 timestamps), `tool` (e.g. `makapix/<version>`), `license`, `source_id`. Unknown keys
are preserved-on-read but ignored semantically.

**`thmb`** — an embedded preview:
```
format   : u8                        // 0 = PNG (only value defined)
width    : u16
height   : u16
byte_len : uvarint                   // ≤ THUMB_MAX = 1 MiB, else Corrupt
bytes    : [u8; byte_len]            // a complete PNG file
```
PNG keeps the thumbnail directly displayable and is produced by the existing codec crate. The size
cap bounds the allocation.

---

## 10. `ENDF` — end marker

Empty payload (`length == 0`); CRC over the 4 type bytes only. The reader requires that the input
ends **immediately** after `ENDF`'s CRC. This catches a truncated tail and rejects trailing garbage,
giving a definite "file is complete" signal that the prior format (which simply stopped reading
early) never had.

---

## 11. Integrity, versioning, forward-compatibility

### 11.1 Integrity — two independent layers

1. **Byte integrity: per-chunk CRC-32** (IEEE 802.3, reflected polynomial `0xEDB88320`, init
   `0xFFFFFFFF`, final XOR `0xFFFFFFFF` — the standard zlib/PNG CRC), computed over `type ‖ payload`
   and stored LE. The reader recomputes and rejects any mismatch (`BadCrc`) *before trusting the
   payload*. Trivially implemented dependency-free from a 256-entry table (const or built once).
2. **Semantic integrity: content-hash verification.** After reconstruction, the document is
   re-hashed and compared to `HEAD.content_hash` (§3.1); mismatch ⇒ `Corrupt`. A byte flip that
   somehow slips past a CRC (or a logic error in a third-party writer) still cannot yield a silently
   wrong document.

### 11.2 Versioning

`HEAD.format_major` gates the reader. This engine's v7 reader accepts **major 7 only**; a lower or
higher major is `UnsupportedVersion`. There is deliberately **no in-engine migration** from earlier
formats — the clean-break mandate — and the distinct signature (§2.1) makes old files fail fast at
the magic check. Should conversion ever be wanted, it belongs in a separate offline tool, not the
hot codec path.

`format_minor` distinguishes backward-compatible revisions **within** major 7: a minor bump may only
(a) add *ancillary* chunks, or (b) assign meaning to *reserved* fields/bits. A major-7 reader ignores
minors it doesn't know, skipping unknown ancillary chunks and unknown reserved bits. Anything that
would change how existing critical chunks are interpreted requires a **major** bump — and, by §2.4,
even a stray unknown *critical* chunk forces an old reader to refuse rather than misread.

### 11.3 Forward-compatibility summary

* Unknown **ancillary** chunk → skipped via `length`.
* Unknown **critical** chunk → hard refuse (`UnknownCriticalChunk`).
* Reserved header bits / `blend` / `flags` → writer 0, reader ignores unknown values (tolerant).
* New optional data → new ancillary chunk + minor bump.
* Semantic change to pixels/frames/geometry → new critical chunk and/or major bump.

---

## 12. Error handling and hardening against hostile files

The loader returns `Result<Document, MkpxError>` and **never panics** (no indexing, no `unwrap`, no
unchecked arithmetic on file-derived values). Error taxonomy:

```
enum MkpxError {
    BadMagic,
    UnsupportedVersion { major: u8, minor: u8 },
    Truncated,                       // ran off the end of the input
    BadCrc { chunk: [u8;4] },        // chunk CRC mismatch
    UnknownCriticalChunk([u8;4]),    // critical chunk this version can't interpret
    TooLarge(&'static str),          // a declared count/length exceeds its hard cap
    Corrupt(&'static str),           // structural/semantic invariant violated
}
```

### 12.1 Bounded allocation — the core anti-DoS discipline

**No `Vec::with_capacity(n)` is ever called on an unvalidated `n`.** Every count/length that sizes an
allocation is checked against **both** a hard cap **and** the bytes actually remaining in the input
(a count claiming N elements of ≥ M bytes each is rejected immediately if `N*M` exceeds the remaining
input — a crafted "1,000,000 frames" in a 200-byte file fails before allocating). Hard caps:

| Quantity                | Cap                    | Source                                             |
|-------------------------|------------------------|----------------------------------------------------|
| `canvas_w`, `canvas_h`  | 8..=256                | `Size::in_range`                                   |
| `frame_count`           | ≤ 1024                 | `MAX_FRAMES`                                        |
| `layer_count` per frame | ≤ 64                   | `MAX_LAYERS`                                        |
| `num_tiles`             | ≤ 576                  | derived from max storage 768×768                    |
| `word_count` (seln)     | ≤ 9216                 | `MAX_SEL_WORDS`                                     |
| `palette_count`         | ≤ 1024                 | this spec                                           |
| `color_count`/palette   | ≤ 65536                | this spec                                           |
| `string` byte length    | ≤ 4096                 | this spec                                           |
| `tile_count` (`TILE_POOL_MAX`) | ≤ 1<<24 (16,777,216) | far above `frames*layers*num_tiles`; each entry also validated against remaining bytes |
| `cel_count` (`CEL_POOL_MAX`)   | ≤ 1<<20 (1,048,576)  | ≥ `frames*layers` (65,536) with headroom          |
| `thmb` `byte_len`       | ≤ 1 MiB                | `THUMB_MAX`                                         |
| `uvarint`               | ≤ 5 bytes, fits `u32`  | overlong/overflow ⇒ `Corrupt`                      |

### 12.2 Value validation

Beyond sizes: strict UTF-8 for strings; `Σ run == 1024` and `run ≥ 1` for RLE; INDEXED index `< ncolors`; cel grid indices strictly ascending and `< num_tiles`; `tile_ref < tile_count`; `cel_ref < cel_count`; `active_*` clamped; `duration_us` clamped; per-chunk CRC verified before use; single-occurrence and ordering rules (§2.5); `content_hash` verified (§3.1); trailing-byte check after `ENDF` (§10). Ids are re-seeded directly, never by a loop (§7). Every one of these turns a crafted file into a typed error, never a panic and never an unbounded allocation.

---

## 13. Worked size examples (rough byte counts, vs the current format)

Fixed overheads: signature 8 B; per-chunk framing 12 B (4 len + 4 type + 4 CRC); `HEAD` = 34 + 12 =
46 B; `ENDF` = 12 B. "Current" figures use the prior format's positional stream (per-tile 1-byte
present flag over the **storage** grid + per-tile RLE + full re-serialisation per frame).

### 13.1 Empty 256×256 document (1 frame, 1 empty layer, default 16-colour palette)

Storage 768×768 → `num_tiles = 576`, all absent.

| Chunk | v7 bytes | Note |
|-------|----------|------|
| signature + HEAD | 8 + 46 | |
| PALT | ≈ 86 | name "Default" + 16×4 colours |
| TILE | 13 | `tile_count = 0` |
| CELS | 14 | one empty cel |
| FRMS | ≈ 39 | 1 frame, 1 layer "Layer 1" |
| ENDF | 12 | |
| **Total** | **≈ 218 B** | |

**Current format: ≈ 727 B** — dominated by **576 present-flag bytes** for the empty storage grid
(one per gutter tile) plus a 16-byte unverified footer. v7 is **~3.3× smaller**, and pays **zero**
for empty gutter.

### 13.2 64-frame 128×128 animation: one static flat-colour background + one distinct 32×32 sprite per frame

Storage 384×384 → `num_tiles = 144`; the canvas occupies the centre 4×4 = 16 tiles.

* **Background:** a full-canvas flat fill = 16 canvas tiles of one colour → all identical → **1**
  tile-pool entry (`SOLID`, 5 B) + **1** cel (~48 B) referenced by all 64 frames.
* **Foreground:** 64 distinct noisy sprites → 64 tile-pool entries (INDEXED, ~600 B each) + 64
  one-tile cels (~3 B each).

| Chunk | v7 bytes |
|-------|----------|
| signature + HEAD + PALT | ≈ 140 |
| TILE | ≈ 38.5 KB (1 solid + 64 sprites) |
| CELS | ≈ 0.24 KB |
| FRMS | ≈ 2.7 KB (64 frames × 2 layers) |
| ENDF | 12 |
| **Total** | **≈ 41.5 KB** |

**Current format: ≈ 281 KB** — every frame re-serialises the background layer (present bytes + tile
data) *and* the foreground, with **no** dedup: the static background alone costs ~15 KB across the
64 frames instead of ~50 B. v7 is **~6.8× smaller**, and if the sprites reused tiles (a looping walk
cycle) v7 would dedup those too, while the current format cannot.

### 13.3 One noisy dithered 256×256 frame (RLE's worst case)

Content fills the canvas centre = 64 tiles, each highly varied.

* **16-colour dither (typical pixel art):** each tile → INDEXED `1+64+512 = 577 B` → ≈ **37 KB**.
  The current format's RLE, defeated by ~1-pixel runs, spends up to `1024 runs × 6 B = 6144 B`/tile →
  ≈ **393 KB**. v7 is **~10× smaller** on the exact case RLE loses.
* **True 24-bit noise (not pixel art):** > 256 distinct colours/tile → RAW `4097 B`/tile → ≈
  **262 KB**; the current format's RLE *expands* to ≈ 393 KB. v7 wins by **never expanding** (RAW is
  the floor).

---

## 14. Performance

Loading is a single forward pass. Per chunk: a table-driven CRC over its bytes. Tile decode is
O(pixels) with only integer work; dedup means the reader decodes each *unique* tile once and clones
`Arc`s thereafter. For the 64f / 8l / 128² budget, even with no dedup the upper bound is
`64·8·16 ≈ 8192` present-tile references over `≤ 8192` unique tiles ⇒ ~8.4 M pixels decoded (tens of
MB of memcpy) — comfortably under 300 ms; realistic dedup makes it far less. Because reconstruction
shares one `Arc<Tile>` per pool entry, **peak load memory is lower than the current format's** (which
inflates every shared tile into a private copy). The `content_hash` re-verification is one extra
O(present-pixels) pass and stays within budget.

---

## 15. Over-engineering watch — what was deliberately left out

**Left out on purpose:**

* **General LZ / entropy coding (e.g. Deflate, zstd).** Would require either a dependency
  (violating the engine's dependency-free charter and risking the Windows/Android build and the fast
  headless test loop) or a large in-house LZ to maintain and fuzz. On real pixel art, `SOLID` +
  `INDEXED` + tile/cel dedup already capture the wins an LZ would; the only case they miss —
  high-entropy *photographic* imports — is out of scope for a pixel-art editor and is bounded by the
  RAW floor. **If** a future need arises, an in-house LZ would slot in as a new tile `method` id
  (forward-compatible) rather than a container change. Flagging explicitly: **no external
  dependency is proposed.**
* **Inter-frame pixel deltas / motion prediction.** The cel + tile pools already capture *structural*
  repetition (the thing animations actually have). Pixel-level diffing between frames would add real
  complexity and would break the clean tile-pool ↔ `Arc<Tile>` mapping, for marginal gain.
* **Random access / partial (single-frame) / streaming loads.** Files are small and always loaded
  whole; the chunked framing already permits it later if ever needed, without a redesign.
* **Undo history / action log.** Transient, document-level; never persisted (matches the model).
* **Encryption, signing, tile-level compression dictionaries, arbitrary per-chunk codecs.** None
  earn their complexity here.
* **Larger-than-32² prediction or per-region palettes.** The 32² tile is the engine's native unit;
  respecting it keeps the reader's reconstruction a direct `Arc<Tile>` fill.

**The simplest version that still wins.** Strip v7 down to **tile-pool dedup + `RAW`/`SOLID` methods
+ per-chunk CRC**, dropping `INDEXED`, `RLE`, and the cel pool (emit one cel per layer): that alone
eliminates the per-tile gutter present-tax and deduplicates flat regions and repeated tiles across
frames, already beating the current format on §13.1 and §13.2. `INDEXED` (the §13.3 win) and the cel
pool (the static-background-across-many-frames win) are the next two increments and can land
independently. Because **method choice and dedup are entirely writer-side**, a minimal writer that
emits only `RAW`/`SOLID` and one cel per layer still produces valid v7 files that the full reader
loads correctly — the **reader must support every method and the pools; the writer may grow into
them.** The shipped canonical writer implements the full set so goldens are stable.

---

## 16. Field-order cheat sheet

```
signature: 89 4D 4B 50 58 0D 0A 1A                                  8 bytes

chunk := len:u32  type:[u8;4]  payload[len]  crc:u32(type‖payload)   framing (×N)

HEAD payload (34):
  major:u8 minor:u8 canvas_w:u16 canvas_h:u16 storage_w:u16 storage_h:u16
  loop_mode:u8 flags:u8 active_frame:u32 active_palette:u16 content_hash:u128

PALT payload:
  palette_count:uvarint
    per palette: name:string  color_count:uvarint  [rgba:4]×color_count

TILE payload:
  tile_count:uvarint
    per tile: method:u8
      0 RAW     : [rgba:4]×1024
      1 SOLID   : rgba:4
      2 RLE     : run_count:uvarint  { run:uvarint, rgba:4 }×run_count   (Σrun==1024)
      3 INDEXED : ncolors:u8(0=256)  [rgba:4]×ncolors  indices[128*k]   (k=ceil(log2 ncolors))

CELS payload:
  cel_count:uvarint
    per cel: present_count:uvarint  { gap:uvarint, tile_ref:uvarint }×present_count
             (grid_index = prev+1+gap, ascending, < num_tiles)

FRMS payload:
  frame_count:uvarint
    per frame: frame_id:u32 duration_us:u32 active_layer:uvarint layer_count:uvarint
      per layer: layer_id:u32 name:string attr_flags:u8 opacity:u8 blend:u8 cel_ref:uvarint

seln payload (ancillary):
  mask_w:u16 mask_h:u16 word_count:uvarint [word:u64]×word_count

meta payload (ancillary):
  field_count:uvarint  { key:string, value:string }×field_count

thmb payload (ancillary):
  format:u8 width:u16 height:u16 byte_len:uvarint bytes[byte_len]

ENDF payload: (empty)

primitives:
  uvarint := LEB128, minimal, ≤5 bytes, fits u32
  string  := uvarint len(≤4096) + strict-UTF-8 bytes
  all multi-byte integers little-endian
  crc     := CRC-32/IEEE (0xEDB88320, init/xorout 0xFFFFFFFF) over type‖payload
```

---

*End of `.mkpx` v7 specification. Every structure maps onto an existing engine type; the codec is
pure Rust, dependency-free, integer-exact, panic-free, and deterministic.*
