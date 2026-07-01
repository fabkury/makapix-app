# `.mkpx` Format — Introspection of the Current Design (v4)

> **Purpose.** A ground-truth, code-derived description of how the `.mkpx` container is
> structured **today**, as a foundation for deciding whether it can be better engineered.
> This is a *descriptive audit*, not a redesign. It records exactly what the code does,
> where it diverges from the written SPEC, and which structural properties matter for any
> future work.
>
> **Sources read** (all line references verified against the tree at time of writing):
> - `crates/engine/src/io.rs` — the whole codec (`save_to_bytes` / `load_from_bytes`).
> - `crates/engine/src/buffer.rs` — the tiled COW buffer + tile (de)serialization helpers.
> - `crates/engine/src/document.rs` — the data model that gets serialized.
> - `crates/engine/src/color.rs` — the `Rgba8` pixel type.
> - `crates/engine/src/selection.rs` — the selection `Mask` word layout.
> - `crates/engine/src/util.rs` — the `Hasher` used for the footer content hash.
> - `crates/ffi/src/lib.rs`, `crates/engine/src/session.rs` — how save/load are invoked.
> - `app/lib/editor/persistence/drawing_store.dart` — how the shell stores the bytes on disk.
> - `SPEC.md` §8.3, §12, §17 — the written contract (and where the code diverges from it).

---

## 1. What `.mkpx` is, in one paragraph

`.mkpx` is the editor's **lossless native document format**: a single, flat, little-endian
binary blob that captures a whole animated pixel-art document — canvas size, palettes,
animation loop mode, every frame with its layers, every layer's sparse tiled pixels, and
(optionally) the live selection mask. It is produced and consumed **entirely by the Rust
engine** (`crates/engine/src/io.rs`); the Flutter shell only moves the opaque byte buffer
around (save it, load it, hand it to a background isolate for export). It is **not** a
transport/publish format — publishing rasterizes to PNG/GIF instead (`SPEC.md` §21) — and it
is **not** an action log (replay logs are a test artifact only, `SPEC.md` §17).

The current on-disk version is **`FORMAT_VERSION = 4`** (`io.rs:17`). The loader still reads
v1–v4 (`io.rs:265`).

---

## 2. Where it sits in the architecture

```
Flutter shell (Dart)                         Rust engine
────────────────────                         ───────────
DrawingStore.save(bytes)  ──file──►  doc.mkpx / doc.mkpx.bak / doc.mkpx.tmp
        ▲                                         │
        │ Uint8List                               │  (opaque bytes; shell never parses them)
        │                                          
engine.save()  ── FFI: mkpx_save ──►  Session::save_bytes ──► io::save_to_bytes(&Document)
engine.load(b) ── FFI: mkpx_load ──►  Session::load_bytes ──► io::load_from_bytes(&[u8])
```

- **FFI seam** (`crates/ffi/src/lib.rs:224`, `:240`): `mkpx_save` returns a malloc'd buffer +
  length (freed via `mkpx_free_bytes`); `mkpx_load` returns `0`/`-1`. Only bytes cross the
  boundary — consistent with the project's "strings-and-bytes only" C ABI rule.
- **Session wrappers** (`session.rs:2442`, `:2445`): `save_bytes` is a thin pass-through;
  `load_bytes` replaces the document and resets transient session state (clipboard, paste/move
  drafts) but deliberately does **not** clear the selection, because the selection now travels
  *inside* the document for crash recovery.
- **Shell persistence** (`drawing_store.dart`): each drawing is a directory
  `<base>/drawings/<id>/` holding `doc.mkpx` (+ `.bak`, `.tmp` for atomic replace), plus
  **sidecar** `meta.json` and `thumb.png`. Crash-safety (tmp-write + rename + keep-old-as-bak)
  lives in the **shell**, not the format. The thumbnail and metadata live **beside** the file,
  not inside it (see §9 and §10).

---

## 3. On-disk byte layout (v4, exactly as written)

Everything is little-endian. There are **no chunk length prefixes and no chunk type tags** —
the format is a **fixed-order positional stream**. The reader advances a cursor field-by-field
(`Reader` in `io.rs:90`); it knows where each field is only because the order is fixed.

`string(s)` means: `u16` byte-length (truncated to `u16::MAX`) followed by that many UTF-8
bytes. On read, bytes are decoded with `from_utf8_lossy` (`io.rs:123`).

### 3.1 Header

| Field | Type | Bytes | Notes |
|---|---|---|---|
| Magic | `[u8;4]` | 4 | ASCII `"MKPX"` (`io.rs:11`). Mismatch → `IoError::BadMagic`. |
| FormatVersion | `u16` | 2 | Written as `4`. Reader accepts `1..=4`; anything else → `UnsupportedVersion`. |
| Flags | `u16` | 2 | **Always written `0`; read into `_flags` and ignored.** Reserved (SPEC claimed bit0 = "has thumbnail" — never implemented). |
| Canvas width | `u16` | 2 | `doc.size.w` (8..=256). |
| Canvas height | `u16` | 2 | `doc.size.h`. Validated with `size.in_range()` on load. |
| active_frame | `u32` | 4 | Clamped to `frames.len()-1` on load. |
| loop_mode | `u8` | 1 | `0`=Loop, `1`=Once, `2`=PingPong (`io.rs:147`). |

The **canvas** size is stored; the **storage** size (canvas + gutter) is **not** — it is
re-derived on load from a fixed policy (see §5).

### 3.2 Palette table

| Field | Type | Bytes |
|---|---|---|
| palette_count | `u16` | 2 |
| active_palette | `u16` | 2 |
| per palette → name | `string` | 2 + len |
| per palette → color_count | `u16` | 2 |
| per palette → colors | `[u8;4] × count` | 4 each (r, g, b, a straight RGBA) |

If a loaded file has zero palettes, the loader injects the built-in default 16-color ramp
(`io.rs:296`, `document.rs:112`).

### 3.3 Frame / layer / tile body

```
frame_count : u32
repeat frame_count times:
    frame.id            : u32
    frame.duration_us   : u32     (clamped to 16_667..=1_000_000 on load)
    frame.active_layer  : u32     (clamped to layers.len()-1 on load)
    layer_count         : u16     (load rejects 0 or > MAX_LAYERS=64)
    repeat layer_count times:
        layer.id        : u32
        layer.name      : string
        flags           : u8      (bit0 = visible, bit1 = locked)
        opacity         : u8
        blend           : u8      (always 0 = Normal; read into `_blend`, ignored)
        num_tiles       : u32     (MUST equal the buffer's tile count, else Corrupt)
        repeat num_tiles times:
            present     : u8      (0 = absent/transparent, 1 = present)
            if present == 1:
                tile RLE payload  (variable; see §4)
```

Tiles are emitted in **storage-grid row-major index order** (`for i in 0..num_tiles`,
`io.rs:199`). `num_tiles` is `ceil(storage_w/32) · ceil(storage_h/32)` for v4 (storage-sized
buffers). The present-flag is **inline, one byte per tile**, interleaved with the data — it is
*not* a packed bitmap.

### 3.4 Selection chunk (v3+)

| Field | Type | Bytes | Notes |
|---|---|---|---|
| present | `u8` | 1 | `0` = no selection (nothing follows). |
| mask width | `u16` | 2 | Storage-sized in v4. |
| mask height | `u16` | 2 | |
| word_count | `u32` | 4 | Rejected if `> MAX_SEL_WORDS = 9216` (`io.rs:22`). |
| words | `u64 × word_count` | 8 each | Packed 1-bit-per-pixel, row-major (`selection.rs:49`). |

On load, a mask whose `(w,h)` doesn't match the re-derived **storage** size is **silently
dropped** (kept out of the document, but the document still loads) — see `read_selection`,
`io.rs:237`. This is how stale v1–v3 (canvas-sized) masks and any corrupt size are handled.

### 3.5 Footer

| Field | Type | Bytes | Notes |
|---|---|---|---|
| content_hash | `u128` LE | 16 | `doc.content_hash()` (`io.rs:230`). |

**The footer is written but never read.** `load_from_bytes` returns after the selection chunk
and never consumes or verifies these 16 bytes (`io.rs:377`). So the "integrity footer" is
effectively **write-only / vestigial** in the current loader (see §7).

---

## 4. Tile pixel encoding — sparse presence + per-tile RLE

Two layers of compaction, both intrinsic to the engine (no external compression library — the
engine is `#![forbid(unsafe_code)]` and **dependency-free** by charter):

1. **Sparsity.** The pixel buffer is a grid of **32×32 tiles** (`buffer.rs:14`). An untouched
   tile is `None` and serializes to a **single `0` byte**. Only materialized tiles carry data.
   This is what keeps mostly-empty pixel art small.

2. **Per-tile RLE.** A present tile's 1024 pixels (4096 raw bytes) are run-length encoded as a
   sequence of `(run: u16, pixel: [u8;4])` pairs over the tile's **row-major local order**
   (`rle_encode_tile`, `io.rs:25`; decode `rle_tile`, `io.rs:129`):

   ```
   run₀ (u16) | r g b a | run₁ (u16) | r g b a | …   until Σ run == 1024
   ```

   - A run is 6 bytes and covers up to 1024 identical consecutive pixels.
   - **Best case** (flat-filled tile): 1 run = **6 bytes** for the whole 4096-byte tile.
   - **Worst case** (every pixel differs from its predecessor): 1024 runs =
     **6144 bytes**, i.e. a **1.5× expansion** over the raw 4096 bytes. RLE is not a
     guaranteed shrink; noisy dithered tiles cost more than raw.
   - Decode is bounds-checked: `run == 0` or `Σ run > 1024` → `IoError::Corrupt` (`io.rs:135`).

### Properties of this scheme worth naming

- **Runs never cross tile boundaries.** Coherence is only exploited *within* a 32×32 tile, and
  only along the row-major scan (horizontal runs; vertical coherence helps only when it
  produces long horizontal runs across a flat region).
- **The RLE unit is a full 4-byte RGBA pixel, not a palette index.** Even though the document
  carries palettes, pixels are stored as **raw RGBA** — there is **no indexed-color mode**. A
  16-color image still pays 4 bytes per distinct run-pixel.
- **No cross-tile, cross-layer, or cross-frame deduplication.** In memory, identical tiles are
  `Arc`-shared (COW), so a static background repeated across 100 frames costs one tile's RAM.
  **On disk that sharing is lost** — each frame/layer re-serializes its tiles in full. For
  animation with a static layer, this is the single largest redundancy in the format.

---

## 5. Canvas vs. storage, and the gutter (why v4 exists)

The document distinguishes the **canvas** (user-facing size, 8..=256) from the **storage** area
(`SPEC.md` §8.3, `document.rs:175`): each layer buffer is `3w × 3h` — the canvas plus a
**full-canvas gutter on every side** — so pixels pushed off-canvas by Move/paste are preserved
and recoverable. The gutter is **derived** from the canvas size (`gutter_for(size) = size`) and
**never stored**, so it cannot desync from undo/redo.

The format's version history tracks how this interacts with serialization:

| Version | Tile bytes | Tiles are… | Selection chunk |
|---|---|---|---|
| **v1** | raw 4096 B/tile | canvas-sized | none |
| **v2** | per-tile RLE | canvas-sized | none |
| **v3** | per-tile RLE | canvas-sized | present (canvas-sized mask) |
| **v4** | per-tile RLE | **storage-sized** (canvas + gutter) | present (**storage-sized** mask) |

**Load-time migration** (`io.rs:326`, `:346`): v4 tiles deserialize straight into a
storage-sized buffer. v1–v3 tiles deserialize into a canvas-sized buffer, which is then
**lifted into the gutter'd storage at the canvas origin** via `blit_over`. v1–v3 selection
masks are canvas-sized, mismatch the storage dimensions, and are therefore dropped (§3.4). The
`u16` Flags field and the `u8` blend byte are reserved-but-unused growth room.

---

## 6. What determinism / correctness guarantees the format holds

- **Little-endian throughout**, fixed field order, integer-exact pixels (no float ever stored)
  → goldens never fork per platform (`SPEC.md` §5, §17.2).
- **Round-trip invariant** (Tier-1 gate, `SPEC.md` §17.2; tests in `io.rs:396`+): `load(save(doc))`
  is semantically identical — same tiles, palettes, durations, layer attributes, ordering. The
  test asserts equal `content_hash()` before/after.
- **Hardened loader** against crafted files: canvas size range-checked; frame/layer counts
  capped (`MAX_FRAMES=1024`, `MAX_LAYERS=64`); selection word count capped; every read is
  bounds-checked and returns a typed `IoError` (`BadMagic` / `UnsupportedVersion` / `Truncated`
  / `Corrupt`) — **never a panic** (`SPEC.md` §17.2). Id generators are seeded with
  `starting_at(max_id+1)` rather than looping, so a crafted id like `0xFFFFFFFF` can't spin the
  loader (`util.rs:148`, `io.rs:374`).
- **Selection is not folded into `content_hash`** (`io.rs:214`), so thumbnail caches and goldens
  don't churn when only the selection changes.

---

## 7. The footer content-hash, examined

- **Written:** 16 bytes, `doc.content_hash()` — a 128-bit FNV-1a-derived hash over two lanes,
  the second lane mixing byte position to resist transposition collisions (`util.rs:15`).
  `content_hash` covers canvas size + each frame (duration + each layer: name, visible, locked,
  opacity, and the buffer's present-tile hash) — see `document.rs:248`, `buffer.rs:185`.
- **Never verified on load.** The loader stops after the selection chunk; the 16 footer bytes
  are trailing data it never reads (`io.rs:377`). Consequences:
  - Integrity is **not** actually checked at load — a bit-flip in the body is caught only if it
    happens to violate a structural invariant (bad run, bad count, truncation), not by the hash.
  - The footer *is* a de-facto forward-compat cushion: because the reader stops early, appending
    the footer (or any future trailing chunk) doesn't break older-style parsing.

This is a concrete, low-risk place where the current design under-delivers on its own stated
"integrity footer" goal.

---

## 8. What is **deliberately not** in the file

- **No undo/redo history** (`SPEC.md` §17). History is document-level and transient.
- **No thumbnail** (SPEC §17 described an optional thumbnail chunk + a Flags bit; neither is
  implemented). The shell keeps a **sidecar `thumb.png`** instead (`drawing_store.dart`).
- **No document metadata** — title, author, timestamps, license, tool version. Those live in the
  shell's **sidecar `meta.json`**, not the format.
- **No selection combine mode** (Replace/Add/…) — that's transient tool state, not persisted.
- **No storage/gutter geometry** — re-derived from canvas size on load.

Everything the format omits that the app still needs is carried in **sidecar files** managed by
the Dart shell, not by the container itself.

---

## 9. Size characteristics (quantitative)

Fixed overhead is small: header ≈ 17 bytes + palette table + per-frame/per-layer headers +
16-byte footer. The interesting costs are structural:

- **Present-flag tax scales with the gutter.** Storage is `3w × 3h`, so the tile grid is **9×**
  the canvas tile grid. Every tile — including empty gutter tiles — writes **1 present-flag
  byte**. A 256×256 canvas → 768×768 storage → **24×24 = 576 tiles**, i.e. **576 flag bytes per
  layer even when the layer is completely empty**, multiplied across every layer and frame.
- **RLE can expand.** Worst-case noisy tiles are ~1.5× their raw size (§4). RLE is a bet on
  flatness that pixel art usually wins but dithering loses.
- **Animation redundancy is unbounded.** No inter-frame dedup (§4): a static layer duplicated
  across N frames is serialized N times, even though it is one `Arc` in RAM.
- Perf budget the format must satisfy: a 64-frame / 8-layer / 128×128 `.mkpx` should open in
  **< 300 ms** (`SPEC.md` §23).

---

## 10. Divergences between `SPEC.md` §17 and the implementation

The written spec describes a more elaborate container than the code implements. These gaps are
important context for "could it be better engineered" — some are intentional simplifications,
some are unfinished intent:

| SPEC §17 says | Code actually does | Kind of gap |
|---|---|---|
| Pixel tiles are **zstd-compressed** | **Per-tile RLE**, no zstd anywhere | Intentional — zstd would violate the engine's dependency-free charter (`SPEC.md` §4). SPEC text is stale. |
| Footer is a **crc32 of payload** | 16-byte **FNV-128 content hash**, **not verified on load** | Both stale text *and* an unfinished check. |
| Optional **thumbnail chunk** (+ Flags bit0) | No thumbnail in-file; **sidecar `thumb.png`** | Unimplemented; moved to the shell. |
| "Per-layer **tile-index bitmap**" marks present tiles | **1 byte per tile**, inline, interleaved with data | Different (and 8× larger than a bitmap) mechanism. |
| "**Chunked**" container with sizes (`HeaderChunk size`, …) | **Flat positional stream**, no length prefixes, no type tags | Not chunked in the TLV sense; "ignore unknown trailing chunks" holds only trivially (reader stops early). |

Everything else in §17 (state-based not action-log; straight-RGBA tiles; only non-empty tiles
written; no history; selection persisted v3+ and dropped on size mismatch; palettes persisted;
little-endian; typed errors never panics; the `load(save)` round-trip gate) **matches the code**.

---

## 11. Structural observations for any future re-engineering

Neutral, code-grounded facts (not proposals) that would shape a redesign discussion:

1. **On-disk COW is lost.** The biggest structural redundancy: in-RAM `Arc`-shared tiles are
   fully duplicated on disk across frames/layers. A content-addressed tile pool (hash → tile,
   store each unique tile once, reference by index) would collapse animation and duplicated
   layers directly.
2. **Palettes are carried but unused for pixel storage.** No indexed-color path exists; RGBA is
   stored raw even for tiny palettes. An indexed mode is an obvious lever for typical pixel art.
3. **RLE is 1-D and tile-local.** It captures horizontal runs inside 32×32 tiles only. It
   ignores vertical coherence, inter-tile coherence, and can expand on noise. A predictor +
   entropy stage, or per-tile codec choice, would dominate it — but must stay dependency-free
   and integer-exact to preserve determinism.
4. **The gutter triples every dimension.** Any per-tile bookkeeping (present flags today) pays a
   9× multiplier from the storage area. A redesign should decide whether the gutter belongs in
   the persisted form at all, or should be reconstructed like it already is for geometry.
5. **The container is flat and whole-file, in memory.** No chunk framing, no random access, no
   streaming, no partial (single-frame) load. Fine for the size budget; a constraint if files
   grow or if partial loads become useful. Real chunk framing (type + length) would also make
   the "ignore unknown chunks" forward-compat promise real instead of incidental.
6. **Integrity is nominal.** The footer hash is unverified; corruption is caught only by
   structural invariants. Verifying the footer (or a per-chunk checksum) is nearly free to add.
7. **The format holds no identity/metadata.** Title, author, tool version, timestamps, and the
   thumbnail all live in shell sidecars. A self-describing container would let a `.mkpx` travel
   without its directory.

---

## 12. Quick reference — field-order cheat sheet

```
"MKPX"                                   4  magic
version:u16 flags:u16 w:u16 h:u16        10 header
active_frame:u32 loop_mode:u8            5
pal_count:u16 active_pal:u16             4
  per palette: name(str) ncolors:u16 [rgba*4]…
frame_count:u32
  per frame: id:u32 dur_us:u32 active_layer:u32 layer_count:u16
    per layer: id:u32 name(str) flags:u8 opacity:u8 blend:u8 num_tiles:u32
      per tile: present:u8 [ (run:u16 rgba:4)… until 1024px ]
selection: present:u8 [ w:u16 h:u16 nwords:u32 (word:u64)… ]   # v3+
footer: content_hash:u128                # written, NOT read
str := len:u16 + utf8[len]               # from_utf8_lossy on read
```

---

*Introspection report generated from a read-through of the codec and its data model. Every
claim above is traceable to a cited `file:line`. It intentionally does not propose a new format —
it establishes the baseline the format-improvement investigation starts from.*
