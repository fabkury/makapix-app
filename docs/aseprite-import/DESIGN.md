# Aseprite file support — design record

**Status: designed, not implemented.** Grilled to shared understanding on 2026-08-12; awaiting
a go-ahead. Decision of record: ADR 0005. Glossary terms (Open vs. Import): `CONTEXT.md`,
Editor vocabulary.

## What and why

Let users open `.ase`/`.aseprite` files as native layered Makapix drawings. Aseprite is the
de-facto standard pixel-art editor, so this is an onboarding funnel: existing artists bring
their work into Makapix to continue, publish, and remix on the Club. Scope is **opening
only** — no Aseprite export, and no `.ase` in the flat Import-image flow (both were considered
and declined; see Non-goals).

## Licensing reality (constrains the method, not the feasibility)

Aseprite has **not** been open-source since 2016: v1.1 relicensed from GPLv2 to a proprietary
source-available EULA (compile for personal use allowed; code reuse and redistribution not).
Consequences:

- **Never port code from Aseprite's `src/`.** Implement clean-room from the published spec
  (`docs/ase-file-specs.md` in their repo — maintained precisely so third parties can
  implement the format) and from permissively licensed references only (`asefile`, `ase-rs`,
  LibreSprite — the GPL fork of the pre-2016 codebase).
- Owning a real Aseprite copy (~$20, or personal-use compile) is legitimate and is the plan
  for authoring test fixtures.

## Format survey (as of the 2026 spec)

Friendly territory — structurally similar in spirit to `.mkpx` v10's typed-chunk container:

- Little-endian binary; 128-byte header (magic `0xA5E0`); frames (magic `0xF1FA`), each a list
  of size-prefixed typed chunks. Unknown chunks are skippable by design, so import degrades
  gracefully against future Aseprite versions.
- Chunks: old palette (0x0004/0x0011), layer (0x2004), cel (0x2005), cel extra (0x2006),
  color profile (0x2007), external files (0x2008), mask (deprecated, 0x2016), path (0x2017),
  tags (0x2018), palette (0x2019), user data (0x2020), slice (0x2022), tileset (0x2023).
- Cel pixel data is zlib/DEFLATE (RFC 1950/1951). Cel types: raw (deprecated but still found
  in ancient files), linked (frame reuse), compressed image, compressed tilemap.
- Color depths: 32-bpp RGBA, 16-bpp grayscale, 8-bpp indexed (transparent index).
- Blend modes 0–18: Normal, Multiply, Screen, Overlay, Darken, Lighten, Color Dodge,
  Color Burn, Hard Light, Soft Light, Difference, Exclusion, Hue, Saturation, Color,
  Luminosity, Addition, Subtract, Divide.
- Canvas up to 65535×65535; frame/layer counts effectively unbounded; per-frame durations in
  ms; layer groups (nestable) with visibility/opacity; per-cel opacity; palettes with optional
  per-entry names; tags/slices/user data as workflow metadata.

## Feature mapping

| Aseprite | Makapix fate |
|---|---|
| Blend modes | All 10 Tier-1 modes map 1:1 (Multiply, Screen, Overlay, Darken, Lighten, Addition, Subtract, Difference, Exclusion, HardLight). The other 8 fall back to Normal + toast. |
| Layer opacity, names, visibility | Direct map (`Layer.opacity`, `Layer.name`, hidden imports as hidden). |
| Per-cel opacity | Baked into pixel alpha (deterministic integer math). |
| Per-frame durations | ms → `duration_us` through the existing clamp. |
| Indexed / grayscale | Converted to RGBA; transparent index → alpha 0. |
| Palette (+ names) | Becomes the document palette, **Aseprite order preserved** (no auto-sort — ramp order is author intent); entry names map onto color names; >256 colors truncate silently; palette named after the file. |
| Linked cels | Materialized; the `.mkpx` tile dictionary re-dedups on save, so no size blowup. |
| Layer groups | Flattened depth-first; ancestor visibility ANDs in, ancestor opacity multiplies in (integer-exact); group names prefix into children ("Head/outline"); non-Normal group blends count as blend fallbacks. |
| Tilemaps + tilesets | **Rasterized** to ordinary pixel layers (indices + flip bits expanded via the tileset) — visually identical; only the tile workflow is lost. |
| Tags, slices, user data, paths, color profile | Dropped silently (metadata-only; profile ignored, everything treated as sRGB per engine doctrine). Loop mode defaults to Loop. |
| Canvas >256×256, >64 layers, >1024 frames | **Refused** with a clear message naming the actual size/count and the cap. |

## Decisions of record (grilling, 2026-08-12)

1. **Layered Open only.** An `.ase` file opens as a new layered drawing — the gesture is a
   sibling of Open `.mkpx`, not of Import. No flat-Import variant, no export.
2. **Entry point:** the existing Open picker accepts `['mkpx','ase','aseprite']`. OS file
   association (Android intent-filters / iOS UTIs) deferred.
3. **Fidelity doctrine — faithful-or-refuse for structure:** over-cap canvas/layers/frames
   refuse outright. No downscale (destroys pixel art), no truncation ("which 64 layers?" has
   no good answer), no overflow-merge.
4. **Degrade-with-notice for representation:** the 8 unmapped blend modes fall back to Normal.
   Accepted wrinkle: the original mode is not stored, so a future Tier-2 engine cannot
   auto-upgrade old imports.
5. **Notice = one toast, only when the look changes** (blend fallbacks are the only such
   case). Metadata-only losses are silent.
6. **Tilemaps rasterize** rather than refuse or skip — nothing is unrepresentable about their
   pixels.
7. **Parser: hand-rolled in `crates/codec`**, using the already-present `miniz_oxide` (zero
   new shipped dependencies). `asefile` enters **dev-deps only** as a differential-fuzzing
   oracle. Shipping `asefile` was declined: hostile-input allocation behavior outside our
   control, drags flate2/image versions, release cadence coupling.
8. **Fixtures authored in a real Aseprite copy** (ground truth incl. 1.3 tilemaps), committed
   to the repo. LibreSprite alone can't author tilemaps (pre-1.3 fork).

## Architecture sketch

- `crates/codec`: clean-room `.ase` parser → a layered intermediate (layers with name/
  visibility/opacity/blend + full-canvas RGBA, per-frame durations, palette with names).
  Bounds-before-alloc: every declared dimension/count validated against caps and budgets
  before any allocation; decompressed cel size bounded by declared cel dimensions.
- `crates/engine`: document assembly from the intermediate — a sibling of the `.mkpx` loader
  (NOT of `import.rs`, which is the flat into-current-document path). Existing memory-budget
  loader refusal applies unchanged.
- Flutter: the Open flow routes `.ase`/`.aseprite` bytes over the existing bytes-only FFI
  seam; new drawing lands in the drawing store (title from filename), autosaves, and starts
  its Journal with a captured-base Chapter — the Replay model already covers this case.
- Testing: golden fixtures (matrix: 3 color depths × groups/linked cels/tilemaps/all 18 blend
  modes/named palettes/raw cels), `asefile` differential fuzzing, cargo-fuzz target on the
  parser. Dev-deps are unconstrained by repo policy.

## Costs and risks

- **Cost:** parser + assembly + fixtures ≈ 1.5–3k lines of Rust, several focused days;
  tilemap rasterization ≈ +1 day; Flutter side nearly free (extend picker, route bytes).
- **Risks:** parser security (mitigated: bounds-first parsing, budgets, fuzzing — the exact
  threat model the codebase is built for); spec drift (low — skippable chunks); licensing
  hygiene (solved by clean-room discipline); **disappointment rate** — real files over
  256×256 bounce with no in-app recourse, so the refusal message must be excellent.

## Non-goals (explicitly declined)

- Aseprite **export** (revisit only if demand appears after import ships; it would be the
  only layered escape hatch, but PNG/GIF/WebP/sprite-sheet cover flat interchange).
- `.ase` in the flat Import-image picker.
- OS-level file association in v1.
- `.ase` as a Club upload/attachment type (the `.mkpx` attachment contract stays frozen;
  publish still converts to PNG/GIF/mkpx — zero server changes).
- Tier-2 blend modes (separate feature if ever); preserving unsupported Aseprite features for
  round-trip.
