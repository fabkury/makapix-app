# Makapix `.mkpx` File Format — **Version 10** (synthesis of v5 + v9)

**Status:** Design specification, ready for implementation.
**Scope:** The native, lossless working-state format of the Makapix Editor. Supersedes `SPEC.md §17`
(legacy v1–v4) and the exploratory v5–v9 drafts. **No backward compatibility** with any prior format
is required or provided; a v10 reader reads only v10.
**How it was chosen:** v10 merges the two mature drafts — **v5** (predictor-free tile dictionary,
RLE ref-grids, verify-on-encode, DEFLATE) and **v9** (byte-deterministic canonical encoder, hardened
container, hostile-input rigor) — resolved by four explicit product decisions (§2).

**One-line pitch.** A typed-chunk container whose pixels live in a single **content-addressed tile
dictionary** (identical tiles stored once, `Arc`-COW sharing restored on load), with a per-tile
**smallest-wins codec** (`RAW`/`RLE`/`INDEXED`) that never inflates; a **byte-deterministic** canonical
encoder with a cheap **incremental autosave** path; **validated integrity** (whole-file CRC + a verified
content hash + verify-on-encode); and an **optional pure-Rust DEFLATE envelope** applied only to explicit
saves, at the periphery, so the engine core stays dependency-free.

---

## 1. Goals & non-goals

**Goals**
- **Lossless, integer-exact** persistence of the whole document — every frame, layer, palette, the
  selection, and every 32-bit straight-RGBA value (including RGB under `alpha = 0`).
- **Byte-deterministic** output: for a fixed engine build, a given document encodes to a byte-identical
  file *per profile* (§2, §14). Goldens never fork per platform.
- **Small files**, driven by **content-addressed tile deduplication** (the dominant lever for animation
  and layered art) and a **per-tile codec menu with a RAW floor** (never inflates).
- **Cheap, frequent autosave**: the 10 s-debounced autosave re-encodes only the tiles a stroke touched
  (§15.2), and never pays for compression (§16).
- **Dependency-free engine core; pure-Rust deps only at the periphery** — matching the engine charter.
  The only third-party code is a pure-Rust DEFLATE (`miniz_oxide`) in the *peripheral* compact envelope
  (§16), never in the core loader.
- **Robustness**: truncated/corrupt saves are detected (whole-file CRC), reconstruction is verified
  (content hash), and an explicit save is verified before it is trusted (verify-on-encode).

**Non-goals**
- Cross-user interchange or archival (the Club shares *rendered* PNG/GIF, never `.mkpx`). A portable
  export format, if ever wanted, is separate and out of scope.
- Backward compatibility with v1–v4.
- Lossy compression of any kind.
- Random-access / partial-frame / streaming loads (whole-file model; heavy-document optimization is
  explicitly deprioritized).

---

## 2. Decisions that shaped v10 (the record)

| # | Decision | Chosen | Consequence |
|---|----------|--------|-------------|
| 1 | Correctness & output contract | **Byte-deterministic single canonical encoder** (v9), *per profile* | One canonical encoder; exact-byte goldens; autosave cheap via an incremental `Arc`-cache, not a second heuristic mode. |
| 2 | Gradient predictor codec (`DELTA_RLE`) | **Skip** (v9 codec set) | Codecs are `RAW`/`RLE`/`INDEXED`; codec IDs `≥3` reserved so a predictor can be added later without a format bump. |
| 3 | Cel pool (per-layer layout dedup) | **Drop** (v5 structure) | A single tile dictionary; each layer emits its own **RLE tile-ref grid**. Simpler; layout redundancy across held frames is not deduped (accepted). |
| 4 | Optional DEFLATE on the streams | **Enable now, compact/export only, not autosave** | DEFLATE is a **peripheral envelope** (pure-Rust `miniz_oxide`), keeping the engine core dep-free and the untrusted-input loader decompressor-free. |

The Q1×Q4 interaction — "byte-deterministic single file" vs "compress only some saves" — is resolved by
**two byte-deterministic profiles**, `plain` (autosave) and `compact` (explicit/export), §14/§16.

---

## 3. Terminology & constants

| Term | Meaning |
|------|---------|
| **Document** | The artwork: canvas, timeline of frames, palettes, selection, metadata. |
| **Frame** | One animation cell: a duration and an ordered list of layers. |
| **Layer** | One buffer in a frame: name, visible/locked, opacity, blend. |
| **Tile** | A fixed **32×32** block of straight RGBA; the unit of storage, dedup, and codec choice. |
| **Storage area** | Persisted pixel extent = canvas + gutter (§13). |
| **Tile dictionary** | The deduplicated set of distinct non-empty tiles (§7). Index `0` = implicit transparent, never stored. |
| **Tile-ref grid** | A layer's row-major grid of dictionary indices over the storage tile grid, RLE-encoded (§8). |

```
TILE_SIZE = 32     TILE_AREA = 1024     TILE_BYTES = 4096
Canvas          8..=256 per axis
Frames/doc      1..=1024
Layers/frame    1..=64
Frame duration  16_667..=1_000_000 µs
Pixels          8-bit STRAIGHT (non-premultiplied) RGBA, sRGB, byte order R,G,B,A
Integers        little-endian, fixed width, EXCEPT varint = unsigned LEB128 (canonical, minimal)
Tile-local pixel index   i = y*32 + x,   x,y ∈ 0..31
MAX_DICT_TILES  1 << 24   (bounds decode; far above frames*layers*cells)
MAX_SEL_BYTES   73_728    (ceil(768*768 / 8))
MAX_STR         4096
CRC             CRC-32C (Castagnoli, poly 0x1EDC6F41 reflected), pure-Rust table
```

---

## 4. Container structure

A `plain` `.mkpx` file is an 8-byte signature followed by a linear sequence of typed chunks, with
`HEAD` first and `INTG` last.

### 4.1 Signature (8 bytes, hardened)

```
0x89  'M'(4D)  'K'(4B)  'P'(50)  'X'(58)  0x0D  0x0A  0x1A
```
PNG-style: `0x89` (high bit → detect 7-bit/text-mode stripping), `0x0D 0x0A` (CRLF↔LF translation),
`0x1A` (DOS-EOF truncation). Distinct from legacy `MKPX…` files, which cleanly fail the magic check.
Mismatch ⇒ `BadMagic`. (The **`compact` envelope**, §16, uses a distinct signature so a reader can tell
the two apart before doing anything else.)

### 4.2 Chunk framing

| Field | Type | Notes |
|-------|------|-------|
| `fourcc` | `u8[4]` | Chunk type (ASCII). |
| `chunk_flags` | `u8` | bit0 = **critical**; other bits reserved 0. |
| `length` | `u32` | Payload length; must satisfy `length ≤ bytes_remaining`. |
| `payload` | `u8[length]` | Chunk-specific (§5–§12). |

**Reader rules.** `HEAD` MUST be first, `INTG` MUST be last, and the file MUST end immediately after
`INTG`. Defined chunks have fixed criticality (below). An **unknown** `fourcc`: critical bit set ⇒
`UnsupportedChunk`; else **skip** by `length`. A duplicate of any critical chunk ⇒ `Corrupt`. Order of
chunks between `HEAD` and `INTG` is otherwise unconstrained, but the **canonical writer** emits the
fixed order below (part of byte-determinism, §14).

| FourCC | Critical | Presence | § |
|--------|:--------:|----------|---|
| `HEAD` | ✔ | 1, first | 5 |
| `TILE` | ✔ | 1 | 7 |
| `FRMS` | ✔ | 1 | 8 |
| `UPAL` | – | 0–1 | 9 |
| `SELC` | – | 0–1 | 10 |
| `THMB` | – | 0–1 | 11 |
| `META` | – | 0–1 | 11 |
| `INTG` | ✔ | 1, last | 12 |

Canonical writer order: `HEAD, TILE, FRMS[, UPAL][, SELC][, THMB][, META], INTG`. The engine core
never emits `THMB`/`META` (those are shell/periphery additions, §11/§14).

---

## 5. `HEAD`

Fixed payload, little-endian:

| Type | Field | Notes |
|------|-------|-------|
| `u16` | `format_version` | `10`. Else `UnsupportedVersion`. |
| `u16` | `canvas_w` | 8..=256. |
| `u16` | `canvas_h` | 8..=256. |
| `u16` | `gutter_left` | persisted per-side margin, px (§13). |
| `u16` | `gutter_top` | px. |
| `u16` | `gutter_right` | px. |
| `u16` | `gutter_bottom` | px. |
| `u32` | `frame_count` | 1..=1024. |
| `u16` | `active_frame` | clamped to `frame_count-1` on load. |
| `u16` | `active_palette` | 0-based; `0xFFFF` = none. |
| `u8` | `loop_mode` | 0 Loop · 1 Once · 2 PingPong (unknown → Loop). |
| `u8` | `head_flags` | bit0 has `SELC` · bit1 has `THMB` · others reserved 0. |
| `u128` | `content_hash` | `Document::content_hash()` (§12.2). **Verified on load.** |

Explicit per-side gutter margins (v5) make the file self-describing and let the load-time remap (§13)
stay clean if the runtime gutter policy ever changes. Storage geometry is derived:
`storage_w = canvas_w + gutter_left + gutter_right` (same for height), `tiles_x = ceil(storage_w/32)`,
`tiles_y = ceil(storage_h/32)`, `cells = tiles_x*tiles_y`. Loader validates `storage_w,storage_h ≤ 768`
⇒ `cells ≤ 576`.

---

## 6. Primitives

- **`varint`** — canonical unsigned LEB128, minimal on write. Reader rejects > 5 bytes for a `u32`
  field, overflow, or a non-minimal trailing group ⇒ `Corrupt("varint")`. Every varint that sizes an
  allocation is additionally bounded by the bytes remaining (§19).
- **`str`** — `varint` byte-length (≤ `MAX_STR = 4096`) + UTF-8 bytes, decoded lossily (the content
  CRC already catches byte corruption, so a lossy decode keeps the loader infallible on content).
- **`rgba`** — 4 bytes `r,g,b,a`, straight.

---

## 7. `TILE` — the tile dictionary

The deduplicated set of distinct **non-empty** tiles for the whole document. Dictionary index `0` is
the implicit fully-transparent tile and is **never stored**; the *i*-th stored entry is index *i*
(1-based). Identical tiles anywhere — across frames, layers, or grid positions — share one entry, and
one shared `Arc<Tile>` after load (§17), restoring the engine's in-RAM COW.

```
varint tile_count                         (0..=MAX_DICT_TILES)
repeat tile_count:
    u8      codec                         (§7.1; unknown ⇒ Corrupt)
    payload                               (self-delimiting per codec)
```

Entries are not length-prefixed — each codec is exactly self-delimiting, and the whole-file CRC (§12)
frames the chunk. Every tile decodes to exactly 4096 straight-RGBA bytes (row-major). Edge tiles are
full 32×32; storage-external pixels are canonically `(0,0,0,0)`, so tile bytes (hence dedup and
hashing) are unambiguous (§13).

### 7.1 Per-tile codecs

The canonical encoder computes the size of every *applicable* codec and picks the **smallest**; ties
break to the **lowest codec id** (deterministic, integer-only ⇒ byte-identical goldens). Codec IDs
`≥ 3` are **reserved** (e.g. a future `DELTA_RLE` predictor — see §21); a decoder meeting a reserved/
unknown id ⇒ `Corrupt`.

| id | Name | Applicable | Payload | Size |
|---:|------|-----------|---------|------|
| 0 | `RAW` | always (the floor) | `rgba × 1024` | `1 + 4096` |
| 1 | `RLE` | always | `(run:varint(1..=1024), rgba)` until Σrun = 1024 | `1 + Σ(len(run)+4)` |
| 2 | `INDEXED` | ≤ 256 distinct colours | `count_minus_1:u8` + `rgba × ncolors` + packed indices | `1 + 1 + 4·ncolors + ceil(1024·k/8)` |

- **`RAW`** — the ceiling; no tile ever exceeds `1 + 4096` bytes (fixes v4's RLE inflation on noise).
- **`RLE`** — identical-consecutive-pixel runs over the row-major scan; `run ≥ 1`, `Σ run == 1024`
  (else `Corrupt`). Varint runs make short runs cheap.
- **`INDEXED`** — `ncolors = count_minus_1 + 1 ∈ 1..=256`; local colour table in first-appearance
  (row-major) order; `k = bits_needed(ncolors)` (`0` for a solid tile, up to `8`), **not stored**;
  1024 indices packed **MSB-first**, pixel 0 in the high bits, `ceil(1024·k/8)` bytes. `k = 0` (solid)
  writes **zero** index bytes ⇒ 5-byte tile, so `INDEXED` subsumes the old `SOLID` and preserves a
  materialised-but-transparent tile (`INDEXED, ncolors=1, rgba=0000`). Reader validates every index
  `< ncolors` ⇒ else `Corrupt`. A 2-colour dither tile = `1+8+128 = 137 B` (where v4's RLE bloated to
  ~6 KB). Indexing is **per-tile and local** — lossless for any RGBA (imports, gradients, alpha), and
  never tied to the document palettes.

**Deduplication is the encoder's job.** It content-addresses tiles (the canonical 4096-byte form) and
emits each distinct tile once. The dedup hash is *not* part of the format (a hash pre-filter plus a
full byte compare avoids any collision hazard). See §15 for the incremental/canonical encoder.

---

## 8. `FRMS` — frames, layers, tile-ref grids

```
varint frame_count                        (== HEAD.frame_count)
repeat frame_count:
    u32     frame_id                      (opaque, preserved across save/load)
    u32     duration_us                   (clamped 16_667..=1_000_000 on load)
    u16     active_layer                  (clamped to layer_count-1 on load)
    u16     layer_count                   (1..=64)
    repeat layer_count:
        u32     layer_id                  (opaque)
        str     name
        u8      flags                     (bit0 visible · bit1 locked; others reserved 0)
        u8      opacity
        u8      blend                     (0 Normal; unknown → Normal)
        # tile-ref grid: exactly cells row-major cells, run-length encoded (v5):
        repeat until `cells` cells emitted:
            varint  run_len               (≥ 1)
            varint  tile_index            (0 transparent; else 1..=tile_count into TILE)
```

The **RLE ref-grid** (from v5) absorbs the transparent gutter and flat regions in one long run, and
folds a flat fill spanning many tiles (all pointing at one dictionary entry) into a single run. It
replaces v9's per-cell sparse list; with the cel pool dropped (decision 3) each layer simply carries
its own grid. The canonical form uses **maximal runs** (greedy). Reader validates `Σ run_len == cells`,
`run_len ≥ 1`, and `tile_index ≤ tile_count` ⇒ else `Corrupt`.

`frame_id`/`layer_id` are persisted; on load the id generators are seeded to `max_seen_id + 1`
**directly** (`IdGen::starting_at`), never by a warm-up loop — a crafted `0xFFFFFFFF` can't spin the
loader. Ids do not participate in `content_hash`.

---

## 9. `UPAL` — user palettes (ancillary)

Named swatch sets the artist curates — a UI concern, **not** compression (a palette may list unused
colours and omit used ones; pixels are never palette-constrained).

```
varint palette_count                      (≤ 256)
repeat palette_count:
    str     name
    u16     color_count                   (≤ 65536)
    rgba × color_count
```
`HEAD.active_palette` indexes this list; if absent/empty the loader injects the built-in default
16-colour ramp and clamps `active_palette`.

---

## 10. `SELC` — selection (ancillary, bbox-packed)

The selection is a **storage-sized** 1-bit mask, persisted for crash recovery. Ancillary (a reader that
skips it just loads no selection); **not** folded into `content_hash` (so a selection change never
churns caches/goldens); the combine *mode* (Replace/Add/…) is transient tool state, not persisted.

```
u8 tag       (0 RECT · 1 BITS · 2 EMPTY)
  EMPTY (2): no further bytes → an all-zero storage-sized mask (distinct from "no SELC chunk" = None).
  RECT  (0): bbox_x, bbox_y, bbox_w, bbox_h : u16 (storage coords) — every pixel in the bbox selected.
  BITS  (1): bbox_x, bbox_y, bbox_w, bbox_h : u16, then ceil(bbox_w*bbox_h/8) bytes, bbox bits
             row-major, LSB-first.
```
The bbox encoding (from v9) makes a rectangular marquee 9 bytes and bounds any shape to its bounding
box, instead of a fixed ~73 KiB storage plane. On load, a bbox outside the reconstructed storage size
(stale/crafted) ⇒ selection **dropped**, document still loads. Packed bytes bounded by `MAX_SEL_BYTES`.

---

## 11. `THMB`, `META` (ancillary, shell-written)

Both optional, both **excluded from the deterministic engine core** (§14) — they carry volatile data
(timestamps, a rasterized preview) and are written only by the shell/periphery when a self-contained
file is wanted (the shell otherwise keeps sidecar `thumb.png`/`meta.json`).

**`THMB`** — `tw:u16, th:u16, codec:u8` (`0` RAW · `1` RLE over `tw*th` straight-RGBA · `2` opaque PNG
blob), then payload. Codecs 0/1 are engine-encodable (dependency-free); `2` is produced by
`crates/codec` (the `image` crate) or the shell.

**`META`** — typed key/value:
```
varint entry_count                        (≤ 256)
repeat entry_count:
    str  key                              ("title","author","created_us","modified_us","software",…)
    u8   value_type                       (0 str · 1 u64 · 2 i64 · 3 bytes(varint len))
    value
```
Unknown keys preserved/ignored.

---

## 12. `INTG` — integrity (critical, last)

```
u32 crc32c        // CRC-32C over bytes [0 .. start_of_INTG], i.e. signature + every preceding chunk
```

### 12.1 Whole-file CRC
Covers the signature and all preceding chunks (including their headers), up to but not including
`INTG`. A mismatch yields a distinct `Incomplete`/`Corrupt` error so autosave-recovery can fall back to
`doc.mkpx.bak` rather than load garbage. Whole-file (not per-chunk) CRC is chosen because there are no
partial/streaming reads — one CRC is simpler and sufficient (this drops v9's per-chunk CRC as
over-engineering here). CRC-32C is used for its strong error detection; a pure-Rust table keeps the
*value* platform-identical.

### 12.2 Content hash (semantic integrity)
After reconstruction, the loader recomputes `Document::content_hash()` and compares it to
`HEAD.content_hash` ⇒ `Corrupt("content hash mismatch")` on mismatch. The CRC proves *bytes survived
the channel*; the content hash proves *the artwork was rebuilt correctly* (it catches a codec/logic
bug the CRC can't, since the header hash is computed from the correct in-RAM document). The hash covers
canvas size + per-frame duration + per-layer name/visible/locked/opacity + present-tile pixels; it
excludes selection, palettes, ids, and loop mode — matching the engine's existing hash so cache/golden
keys are unchanged.

---

## 13. Storage, gutter & coordinates

Each layer buffer covers a **storage area** = canvas + an off-canvas **gutter** per side (the engine's
runtime policy is a full canvas per side ⇒ `3w × 3h`), where Move/paste park recoverable off-canvas
pixels. v10:
- Persists explicit per-side margins in `HEAD` (v5) — self-describing.
- Stores gutter **content** only via the RLE ref-grid; an empty gutter is one long transparent run ⇒
  ~free (the sparse win, achieved without v9's `gutter_mode` enum).
- On load, maps the persisted storage area onto the engine's runtime storage area by **aligning canvas
  origins** — re-expanding when the persisted gutter is smaller than runtime (the same lift the legacy
  loader used). If a future build changes the gutter policy, only this alignment changes; the file is
  already self-describing.

Storage-external pixels of an edge tile are canonically `(0,0,0,0)` (§7), keeping tile bytes, dedup,
and hashing unambiguous.

---

## 14. Determinism contract

- **Pixels are integer-exact.** 8-bit straight sRGB; out-of-bounds tile pixels canonically
  `(0,0,0,0)`; all engine colour math is integer-exact, so decoded buffers are byte-identical across
  platforms and rendered goldens never fork.
- **Byte-determinism, per profile.** For a fixed engine build (including the pinned `miniz_oxide` used
  by the compact envelope), a given document encodes to a **byte-identical** file within each profile:
  - **`plain`** (autosave; §16) — the canonical uncompressed container. Fully engine-owned and
    **unconditionally** deterministic (no third-party code in the byte path).
  - **`compact`** (explicit/export; §16) — the *same* canonical container wrapped in a DEFLATE envelope
    at a **fixed level**; byte-deterministic for the pinned dependency version.
  The canonical encoder fixes: chunk order (§4.2), dictionary order (first-appearance traversal),
  smallest-wins codec choice with lowest-id tie-break (§7.1), maximal-run RLE (§8), and first-
  appearance colour tables (§7.1). No floats anywhere in the persisted path.
- **Correctness gate.** The Tier-1 gate remains `decode(encode(doc)) ≡ doc` by content hash
  (`assert.roundtrip`); byte-exact goldens are additionally viable on the `plain` profile and are the
  regression tripwire. (Chosen over v5's looser "encoders may drift" stance: v10's encoder is fixed and
  canonical.)

Two profiles is the honest reconciliation of "byte-deterministic single file" with "compress only
explicit saves" — it is **not** v5's two heuristic *modes*; it is one canonical encoder with a
documented compression parameter.

---

## 15. Encoding: canonical writer, incremental autosave, verify-on-encode

### 15.1 Canonical writer
One encoder produces the canonical `plain` bytes: build the dictionary in first-appearance order,
choose each tile's smallest codec, RLE each layer's ref-grid maximally, assemble chunks in canonical
order, append the whole-file CRC.

### 15.2 Incremental autosave (cheap, byte-identical)
Autosave (§16) must cost work proportional to the edit, not the document, while producing the *same*
canonical bytes. The writer keeps a persistent memo `tile_ptr → (content_hash, encoded_bytes)`; the
engine's `Arc<Tile>` COW means an untouched tile keeps its pointer and the dirty set is exactly what a
stroke changed. Per save:
- **dirty flag / content hash** short-circuit an unchanged document (skip the write entirely);
- **pointer hit** reuses a tile's cached hash + encoded bytes (no re-hash, no codec re-search);
- **pointer miss** (a dirtied tile) hashes + runs the codec chooser once, then inserts.
Cost ≈ O(dirtied tiles) + O(cells) for the ref-grids. The memo is pure memoization: output is
byte-identical to a from-scratch encode. (Off-thread IO: the engine encodes on its thread; the
resulting `Vec<u8>` is handed to a background isolate for the atomic tmp→rename→bak write.)

### 15.3 Verify-on-encode
- **`compact`/explicit save: REQUIRED.** After encoding, decode the produced bytes and assert a
  pixel-identical round-trip (`content_hash`). On mismatch, fall the offending tile(s) back to `RAW`
  and re-verify. An explicit save is thus **never** silently corrupted, regardless of codec edge cases
  (e.g. RGB under `alpha = 0`). (From v5.)
- **`plain`/autosave: RECOMMENDED, incremental** — verify only the dirtied tiles (cheap) or rely on the
  next explicit save's full verify.

---

## 16. Encoding profiles & the DEFLATE envelope (dependency boundary)

There are two profiles; the **decoder auto-detects** which by signature.

**`plain`** — the canonical container of §4–§12. Written by the **engine** (`crates/engine`,
zero-dependency, `#![forbid(unsafe_code)]`). Used by the 10 s autosave and any dispose/flush. No
compression. This is the only format the engine core reads or writes, so its untrusted-input loader
contains **no decompressor**.

**`compact`** — for explicit "Save `.mkpx`" / source export. The canonical `plain` bytes wrapped in a
peripheral envelope:
```
signature   0x89 'M' 'K' 'P' 'Z' 0x0D 0x0A 0x1A     // 'Z' distinguishes compact from plain ('X')
u32         uncompressed_len                          // bounded; sizes the inflate buffer (bomb guard)
u32         crc32c                                    // CRC-32C over the DEFLATE stream (early corruption catch)
bytes       deflate_stream = raw-DEFLATE(plain_bytes) // pinned miniz_oxide, fixed level
```
`open(bytes)`: detect signature; if compact, verify CRC, inflate into `≤ uncompressed_len` bytes, then
feed the inner `plain` bytes to the engine loader (which verifies the inner `INTG` + content hash); if
plain, load directly. `save_compact(doc)`: engine encodes `plain`, periphery deflates.

**Where it lives (dependency boundary).** The DEFLATE envelope is **peripheral**, implemented in
`crates/codec` / `crates/ffi` (and mirrored into `crates/cli` so the `mkpx` harness can round-trip
compact files) — exactly where the charter permits **pure-Rust** deps. `miniz_oxide` is chosen: pure
Rust, no `build.rs`/C/NDK, Android-clean, the inflate/deflate that backs PNG. The engine core stays
dependency-free and its hostile-input loader never inflates untrusted data (inflate happens at the
periphery, under an explicit `uncompressed_len` bomb bound).
*Alternative (if you prefer one read path in the engine over a dep-free core):* move `miniz_oxide` into
`crates/engine` behind a per-chunk `transform` flag on `TILE`/`FRMS`, as a single bounded exception to
the zero-dep rule. v10 recommends the peripheral envelope to keep the just-affirmed dep-free-core policy
intact.

---

## 17. Decoder / load path (linear, panic-free)

1. Detect signature (`plain` vs `compact`); `compact` → verify envelope CRC, inflate (bounded), recurse
   on the inner bytes. Wrong magic ⇒ `BadMagic`.
2. Verify `format_version == 10` (else `UnsupportedVersion`).
3. Verify `INTG` CRC over the file body (else `Incomplete`/`Corrupt`; caller may fall back to `.bak`).
4. Parse `HEAD` (first). Walk chunks; unknown critical → error, unknown ancillary → skip; reject
   duplicate criticals; require `INTG` last and EOF after it.
5. Decode `TILE` into `Vec<Arc<Tile>>`; index `0` is one shared transparent `Arc` (or `None`).
6. For each layer in `FRMS`, expand the RLE ref-grid into a storage-sized buffer whose cells reference
   the **same `Arc<Tile>`** for identical indices — **restoring in-RAM COW sharing on load**.
7. Map persisted storage onto runtime storage by aligning canvas origins (§13).
8. If `SELC` present and its dimensions match runtime storage, apply it; else drop.
9. Recompute `content_hash`; compare to `HEAD` (§12.2).

---

## 18. Integrity summary

Three independent layers, each catching a distinct failure mode, with minimal overlap:
- **Whole-file CRC-32C** (`INTG`) — truncation (crash mid-autosave) and bit-rot.
- **Content-hash verify** (load) — a reconstruction/codec/logic error.
- **Verify-on-encode** (compact/explicit) — never *persist* a corrupt explicit save.
Plus the **compact envelope CRC** — corruption of the compressed transport before inflation.

---

## 19. Hardening against corrupt/hostile input

The loader returns a typed `IoError` and **never panics**:
`BadMagic · UnsupportedVersion(u16) · Incomplete · Corrupt(&'static str) · TooLarge(&'static str) ·
UnsupportedChunk([u8;4])`.

- **Bounds on every read**; any field/count reading past end ⇒ `Incomplete`.
- **Caps on every count** (violation ⇒ `Corrupt`/`TooLarge`): canvas 8..=256; storage ≤ 768; cells ≤
  576; frames 1..=1024; layers 1..=64; `palette_count ≤ 256`; `color_count ≤ 65536`; `str ≤ 4096`;
  `tile_count ≤ MAX_DICT_TILES`; `SELC` bytes ≤ `MAX_SEL_BYTES`; `uncompressed_len` ≤ a fixed inflate
  cap; varint ≤ 5 bytes/u32.
- **Bounded allocation**: reserve `min(count, remaining_bytes / MIN_ENTRY_BYTES)` — a crafted
  `tile_count = 2^24` in a small file cannot force a giant allocation. The inflate buffer is bounded by
  `uncompressed_len` (a decompression-bomb guard), which is itself capped.
- **Every index domain-checked**: `tile_index ≤ tile_count`; `INDEXED` index `< ncolors`; `active_*`
  clamped; `duration_us` clamped; RLE `Σ run == 1024`; ref-grid `Σ run_len == cells`.
- **Ids seeded, not looped**; **varints length/overflow-checked**; **CRC + content hash verified**.
- **Tolerant where the engine already is**: empty palette → default; stale selection → dropped; unknown
  `blend`/`loop_mode`/reserved bits → defaults.

---

## 20. Versioning & extensibility

- Exactly one supported version (`10`); the reader rejects anything else. No migration ladder.
- **Additive without a version bump**: a new **ancillary** chunk (old readers skip it), or a new **tile
  codec** in reserved ids `≥ 3` (only files that use it need a newer reader). A codec `id`, not a
  container change, is where a future **`DELTA_RLE` predictor** would land if measurement ever justifies
  it (decision 2).
- A `format_version` bump is reserved for changes that break **critical** parsing (signature, framing,
  or `HEAD`/`TILE`/`FRMS` grammar).

---

## 21. Over-engineering watch — what v10 cut, and why

Trimmed by the four decisions and by keeping only what earns its place:
- **No cel pool** (decision 3). The tile dictionary already dedups pixels; a second pool to dedup
  per-layer *layouts* added a concept for a second-order win (repeated ref-grids across held frames).
  The RLE ref-grid keeps each layout small; the residual loss is accepted.
- **No `DELTA_RLE` / spatial predictor** (decision 2). Gradient/dodge-burn tiles store as `RAW` (never
  inflating). A codec id is reserved so it can return, measurement-driven, without a format change.
- **No per-chunk CRC.** One whole-file CRC-32C is simpler and sufficient without partial reads.
- **No `gutter_mode` enum / no compact gutter-trim.** Explicit persisted margins + an RLE-free-gutter
  already make empty gutter ~free; a trim pass is marginal.
- **No compression on the autosave path, no compression in the engine core** (decision 4). DEFLATE is
  peripheral, pure-Rust, explicit-save-only.
- **No second heuristic encoder mode** (decision 1). One canonical encoder + an incremental cache, not
  v5's fast/compact effort levels.
- **No random access / streaming / partial-frame load; no undo/action log; no lossy path; no global
  palette; no WebP/`image`/C toolchain in persistence.**

**What v10 deliberately keeps as the minimal winning core:** hardened signature + `HEAD` + a
deduplicated `TILE` dictionary (`RAW`/`RLE`/`INDEXED`, smallest-wins, RAW floor) + `FRMS` with RLE
ref-grids + whole-file CRC + verified content hash + verify-on-encode. `SELC` (bbox), `UPAL`,
`THMB`/`META`, the incremental autosave cache, and the compact DEFLATE envelope are each independent,
individually-droppable increments.

---

## 22. Field-order cheat sheet

```
plain signature:  89 4D 4B 50 58 0D 0A 1A
chunk := fourcc:[u8;4]  chunk_flags:u8(bit0=critical)  length:u32  payload[length]

HEAD: format_version:u16=10 canvas_w:u16 canvas_h:u16
      gutter_l:u16 gutter_t:u16 gutter_r:u16 gutter_b:u16
      frame_count:u32 active_frame:u16 active_palette:u16 loop_mode:u8 head_flags:u8 content_hash:u128
TILE: tile_count:varint  { codec:u8  payload… }×          (1-based; index 0 = implicit transparent)
        0 RAW     : rgba×1024
        1 RLE     : { run:varint(1..=1024) rgba }×  (Σrun==1024)
        2 INDEXED : count_minus_1:u8  rgba×ncolors  indices[ceil(1024*k/8)]  (k=bits_needed, MSB-first)
FRMS: frame_count:varint
        { frame_id:u32 duration_us:u32 active_layer:u16 layer_count:u16
          { layer_id:u32 name:str flags:u8 opacity:u8 blend:u8
            { run_len:varint tile_index:varint }×  (Σrun_len==cells) }× }×
UPAL?: palette_count:varint { name:str color_count:u16 rgba×color_count }×
SELC?: tag:u8 [ bbox_x:u16 bbox_y:u16 bbox_w:u16 bbox_h:u16 [packed bits LSB-first] ]
THMB?: tw:u16 th:u16 codec:u8 payload…
META?: entry_count:varint { key:str value_type:u8 value }×
INTG: crc32c:u32  (over signature..pre-INTG)   # file ends here

compact envelope (peripheral): 89 4D 4B 50 5A 0D 0A 1A  uncompressed_len:u32  crc32c:u32  DEFLATE(plain)
str    := len:varint(≤4096) + utf8   (lossy)
varint := canonical unsigned LEB128, ≤5 bytes for u32
ints   := little-endian; rgba := r,g,b,a straight
```

---

## Appendix — deltas from v5 and v9

| From v5 (kept) | From v9 (kept) | Changed / dropped |
|---|---|---|
| Typed-chunk container w/ critical flag byte | Hardened 8-byte signature | Cel pool — **dropped** (was v9) |
| Single content-addressed tile dictionary | Byte-deterministic canonical encoder | `DELTA_RLE` predictor — **dropped** (was v5); id reserved |
| RLE tile-ref grid (1-based, 0=transparent) | Incremental `Arc`-cache autosave | Per-chunk CRC — **dropped** (was v9) → whole-file CRC-32C (v5) |
| Whole-file CRC-32C integrity | `content_hash` in header, verified on load | v5 "encoders may drift" — **replaced** by v9 byte-determinism |
| Verify-on-encode (compact) | bbox `SELC` (EMPTY/RECT/BITS) | v5 per-chunk `transform` — **moved** to a peripheral envelope |
| Explicit gutter margins + origin remap | Typed `META`; bounded-alloc hostile-input rigor | DEFLATE now enabled (compact/export only), pure-Rust, peripheral |
| Optional pure-Rust DEFLATE (`miniz_oxide`) | Reserved future codec ids | |

*End of v10 specification.*
