# HDR colors and palettes in the Makapix Editor — analysis

**Date:** 2026-08-10 · **Status:** exploratory survey — costs, risks, pros, and cons only.
This document deliberately draws **no go/no-go conclusion** and proposes no spec changes; it is not an
implementation commitment. `SPEC.md` §1.3, §6.1, and §25 #3 explicitly decided *no >8-bit, no wide
gamut, no linear-light* for v1, and this analysis does not amend that.

**Question analyzed:** many phones now have HDR screens — what would it cost, and what would it risk,
for the Makapix Editor to support *authoring* HDR colors and palettes (artists picking colors brighter
than SDR white and/or outside the sRGB gamut, and having them render that way on capable screens)?
Editor-local support and "HDR through the Club" are costed separately, because the cliff between them
is one of the main findings. Platform focus: Android + iOS; Windows is treated only as a place that
must degrade gracefully to SDR.

---

## 1. Two different things hide inside "HDR"

They are separable, and the cheapest credible design supports only the first:

- **Headroom** — luminance above SDR reference white ("glow"). Delivered on phones via extra display
  nits; per-pixel it is a brightness multiplier over the SDR rendition. This is what makes neon signs,
  lava, muzzle flashes, and CRT-style bloom *actually emit* on an HDR screen.
- **Gamut** — chromaticities outside sRGB (Display P3, Rec.2020): more saturated primaries, not more
  brightness. Requires a real color-space tag plus conversion math everywhere colors are mixed.

Phone-HDR still images in 2026 are dominated by **gain-map formats**: an SDR base image plus a
low-resolution brightness-multiplier map, so the same file degrades to plain SDR on non-HDR screens
([Ultra HDR](https://developer.android.com/media/platform/hdr-image-format) = JPEG + gain map,
Android 14+; Apple Adaptive HDR in HEIC, iOS 17+; **ISO 21496-1** is the converging cross-vendor
standard, written alongside Ultra HDR since Android 15 and read by iOS 18). This matters for Makapix
because the gain-map model maps *exactly* onto "SDR pixels + per-color glow metadata" (option A below).

## 2. Where the codebase stands (the load-bearing facts)

Verified against the tree on 2026-08-10:

1. **One pixel type.** `Rgba8` (`crates/engine/src/color.rs:8`) — 8-bit straight RGBA, sRGB — is
   `Eq + Hash` and baked into `Tile([Rgba8; 1024])` (`buffer.rs`), the content-addressed tile
   dictionary, and the `.mkpx` v10 `TILE_BYTES = 4096` constant. Changing its width forks the buffer,
   the history, the hash, and the file format at once.
2. **The blend stack is integer u8 end to end** (`mul255`, `composite`, the 11 blend modes) precisely
   so goldens are byte-identical across platforms. The only sanctioned float-ish path is the Levels γ
   curve, which was deliberately routed through hand-rolled `util::det_pow` instead of libm.
3. **The engine core is dependency-free by policy**, so no color-management library (ICC, lcms, skcms)
   can live there; any gamut math would be hand-rolled fixed-point in the `det_*` style.
4. **Zero color-management plumbing exists end to end.** No ICC/`gAMA`/`cHRM`/`cICP` is read or
   written by any codec path; imports go through `image`'s `to_rgba8()` (16-bit PNGs are silently
   truncated); the display path is `mkpx_display` RGBA bytes → Dart premultiply →
   `ui.decodeImageFromPixels(..., PixelFormat.rgba8888)` with no `ui.ColorSpace` anywhere.
5. **Publish is SDR by construction.** The server accepts PNG/GIF/WebP/BMP only (SPEC-CLUB §journal;
   `conformance.dart` checks extension, bytes, dimensions — never bit depth or color space). The app's
   recommended upload is **lossless WebP — a format that is fundamentally 8-bit and cannot carry HDR,
   ever** (VP8L is frozen at 8-bit ARGB). GIF likewise. The server re-encodes the non-native variants
   with Pillow, which would strip any HDR metadata that survived upload.
6. **Android memory wall.** The scudo ~4 KiB size class — where the 4 KiB pixel tiles live — caps at
   ~1.0 GiB/process; the shipped budgets (96 MiB history, 256/320 MiB document) were tuned against
   exactly this tile size (`docs/memlab/REPORT.md`).

## 3. The Flutter display cliff (shared by every option)

However colors are *stored*, nothing glows unless the pixels reach the screen through an HDR-capable
surface — and **Flutter cannot do that for app-rendered content today**:

- Framework [wide-gamut support](https://docs.flutter.dev/release/breaking-changes/wide-gamut-framework)
  (float `Color` components, `DisplayP3`) is **iOS + Impeller only**; that is *gamut*, and whether
  extended-range values above 1.0 actually reach EDR headroom from Flutter content is unverified —
  it would need a spike, not an assumption.
- On Android, Impeller renders SDR; there is no supported path to an HDR/extended-range swapchain or
  to displaying gain-map images from Dart. Community consensus for HDR stills is currently "platform
  views with native viewers" (see the [immich discussion](https://github.com/immich-app/immich/discussions/7262)).
- The native escape hatches exist but are heavy: Android 14+ has `Gainmap`/`ImageDecoder` +
  `Display.getHdrSdrRatio`, Android 15 adds `Window.setDesiredHdrHeadroom`; iOS has
  `UIImage.preferredImageDynamicRange` and CAMetalLayer EDR. Using them means platform views or a
  native texture path *under* the Flutter UI — for the live editor canvas (60 fps repaint from
  `display_bytes`) that is a rendering-architecture project on each platform, and it interacts with
  the app's existing renderer fragility (the PowerVR/Impeller overscroll saga, the AXTree crash).

**Consequence:** the display leg is a prerequisite research spike for *any* HDR option, its cost is
mostly outside this repo's control (upstream Flutter), and until it lands, "HDR support" could only
ship as metadata that nothing displays — or as exported files whose glow is visible only in *other*
apps (Google Photos, Apple Photos, Chrome).

## 4. Three candidate color models, ranked

### A. Glow accents — 8-bit pixels + per-color HDR headroom metadata *(ranked #1)*

Pixels stay `Rgba8` sRGB. A palette color (or any exact RGBA value) can be tagged with a headroom
factor — e.g. 0–2 stops, quantized to keep it byte-deterministic. At display/export time, a color→gain
map keyed on exact RGBA identity (which `Eq + Hash` makes natural) boosts those pixels into headroom.
This is the pixel-art-native reading of "HDR colors and palettes": the artist marks *this* neon cyan
as emissive; every pixel painted with it glows.

- **Engine cost: small.** An ancillary metadata table (the `UPCN` per-color-name chunk is an exact
  structural precedent — a `UPHD` sibling is a day's format work), a DSL verb or two, no change to
  pixels, tiles, blending, hashes, undo, or budgets. Old loaders skip the ancillary chunk: **.mkpx
  stays v10-compatible.** Goldens untouched; the compositor never sees the boost.
  One semantic wrinkle to design honestly: pixels are deliberately *not* palette-constrained, so the
  binding must be by RGBA value (any pixel matching the tagged value glows), or coarser (per-layer),
  or the glow map lives beside the palette but applies canvas-wide. Value-keyed is deterministic and
  simple; it does mean you can't have the same RGBA both glowing and not glowing in one document.
- **Export cost: moderate, with a format problem.** Gain-map generation from a value-keyed boost table
  is trivial and deterministic (the gain map is flat per color region). But the only *mature* carrier
  is Ultra HDR — **JPEG-based, i.e. lossy DCT on hard pixel edges**, which is close to sacrilege for
  this product. Lossless-ish alternatives are all bleeding-edge: PNG + `cICP` (PNG 3rd edition; a
  [gain-map PNG proposal](https://github.com/w3c/png/issues/380) exists but is not ratified), or AVIF
  (10-bit, decodes broadly on modern phones; a pure-Rust encoder such as `ravif` could sit quarantined
  in `crates/codec` under the existing policy, but lossless AVIF is slow and fat). In 2026 there is
  **no widely-supported lossless HDR interchange format** — the sharpest external constraint on the
  whole idea.
- **Display cost: the full §3 cliff.** Unavoidable, and it dwarfs the engine work.
- **Pros:** every engine invariant survives; zero memory impact against the Android wall; SDR fallback
  is *by construction* the artwork itself (exactly the gain-map philosophy); palette-centric UX fits
  the product's existing palette manager and per-color-name precedent; artistically it targets the one
  thing HDR genuinely adds to pixel art (emissive accents), not photographic tonality.
- **Cons:** it is headroom-only — no wide gamut, so "HDR" purists may call it partial; a color's glow
  is invisible on the Windows dev build and every SDR phone (an in-editor SDR *preview* of glow —
  simulated bloom — is its own little rendering feature); value-keyed semantics are a new concept to
  teach; and it still buys nothing until the display cliff is solved.

### B. 16-bit integer pixels + color-space tag *(ranked #2)*

`Rgba16` (or 10-bit packed), a document-level color-space/transfer tag (sRGB, P3, Rec.2100-PQ), all
blend math widened to integer u16 (`mul255` → `mul65535` preserves exactness), gamut conversion as
hand-rolled fixed-point matrices in the `det_*` tradition.

- **Cost: a whole-codebase project.** New tile size (8 KiB) → `.mkpx` v11 (breaking; the tile
  dictionary, RLE/INDEXED encodings, and `TILE_BYTES` all fork), every golden and content-hash
  re-baked, the CLI probe wire formats (`#RRGGBBAA`, ascii/pixel/hash probes) extended, the FFI packed
  u32 color and Dart hex parsing changed, color pickers/palette UI redesigned for deep color, both
  import and export paths rewritten (16-bit PNG in/out is fine; **the recommended WebP publish format
  is impossible at 16-bit**, GIF likewise — the publish story must change formats, not just widths).
- **Memory: doubles pixel and undo tile bytes on the platform with a hard ~1 GiB wall.** The shipped
  256/320 MiB document and 96 MiB history budgets buy half the frames×layers; separately, 8 KiB tiles
  move out of the scudo size class the wall was measured on, so the memlab work would need re-running
  from scratch before any budget claim is trusted.
- **Pros:** real deep-color authoring — gamut *and* headroom; integer-exact determinism is preserved
  in principle; honest foundation if HDR ever became core to the product.
- **Cons:** enormous blast radius for a niche gain (pixel art rarely needs 65,536 levels per channel);
  most of the visible benefit (glow) is deliverable by A at ~5% of the cost; and it still ends at the
  same display cliff and the same immature interchange formats.

### C. Float linear-light pipeline *(ranked #3)*

The industry-standard HDR compositing model (f16/f32 linear, tone-mapped at output).

- **Cons dominate:** it collides head-on with the determinism doctrine. IEEE basic ops are nominally
  reproducible, but FMA contraction, SIMD codegen, and libm transcendentals make byte-exact goldens
  fragile across three platforms — the exact fight the repo already refused once when it built
  `det_pow` rather than call `powf`. Memory is 4–8× per pixel. Linear-light compositing also *changes
  every existing artwork's appearance* (sRGB-space lerp vs linear lerp produce different mid-blends),
  breaking the "goldens never fork" contract at the semantic level, not just the byte level.
- **Pro:** it is what a from-scratch HDR compositor would look like. Makapix is not from-scratch.

**Ranking rationale:** A delivers the artist-visible essence of the request (emissive palette colors)
while leaving the five load-bearing constraints of §2 intact; B is what A escalates to only if wide
gamut ever becomes a real user demand; C trades away the engine's defining invariant for a modeling
purity this product doesn't need.

## 5. Editor-local vs Club reach — where the cliff is

**Editor-local package** (draw, view your own work in HDR on-device): engine metadata (small, option
A) + palette/picker UX (small) + the §3 display spike (large, partly blocked upstream) + HDR-aware
export for sharing outside the Club (moderate, format-constrained). Feasible to scope once the
display spike answers yes on at least one platform.

**Club package** (HDR art as a first-class published thing) adds, on top:

- **Server contract:** a new accepted upload shape (gain-map sidecar, new format, or metadata field),
  vault validation, and a variant pipeline that *preserves* HDR — today Pillow re-encodes variants
  and would strip it. The as-uploaded `art_url` byte-identity contract helps (the native file
  survives verbatim), but every derived variant and thumbnail goes SDR.
- **Every other client:** the website (independent repo — CSS `dynamic-range` queries and
  gain-map-capable browsers exist, but it is real work there), older app versions (render glow-less
  — acceptable-by-design under A, but a consistency decision), feed rendering in *this* app (the
  feed decode path is `instantiateImageCodec` → SDR; HDR feeds re-enter the §3 cliff at scroll
  scale), and hardware players (Divoom-class RGB565 panels — permanently SDR; fine, but the contract
  must say so).
- **Social-layer policy:** HDR posts out-glow SDR posts in a mixed feed — an attention arms race with
  a known backlash precedent (Instagram's boosted-HDR complaints; platforms now clamp headroom).
  The Club would need a norm or a cap (e.g. maximum stops, or feed-level tone-down, or HDR only on
  the detail page), which is a product decision, not a technical one.

The split verdict the costs imply: **editor-local is an engine-cheap, display-expensive feature;
Club reach roughly doubles the surface and adds two codebases (server, website) plus a policy
question.** Nothing about A forecloses the Club extension later — the gain-map model is exactly the
"SDR base stays canonical" shape a mixed ecosystem needs.

## 6. Consolidated pros, cons, risks

**Pros**
- Emissive pixel art (neon, CRT bloom, light sources) is a genuinely strong aesthetic fit — arguably
  a better use of headroom than photography, since artists control every pixel.
- Palette-native UX: "mark this color as glowing" extends the existing palette manager naturally
  (per-color names already set the precedent).
- Differentiation: no mainstream pixel-art editor (Aseprite et al.) authors HDR; Makapix could be
  first, on both the tool and the community side.
- Option A's gain-map alignment means SDR devices, old clients, and hardware players see the intact
  artwork by construction — graceful degradation is free.

**Cons**
- The display leg — the part that makes it real — is blocked on upstream Flutter on Android and
  unverified on iOS; until then the feature is invisible or platform-view-shaped.
- No mature lossless HDR interchange format exists; the mature one (Ultra HDR) is lossy JPEG.
- The recommended publish format (lossless WebP) can never carry HDR; the Club story forces a format
  change or a sidecar.
- Headroom is not reproducible even among HDR phones: available boost varies with device, ambient
  light, and user brightness (at max manual brightness, headroom ≈ 1.0 and the glow vanishes). The
  artist cannot fully control the result — a philosophical clash with a byte-deterministic product.
- Windows dev builds and SDR phones need a simulated preview or artists author blind.

**Risks**
- *Invariant erosion:* B and C touch the determinism/memory/format contracts that the last year of
  engineering (memlab budgets, `.mkpx` v10, det_* doctrine) was built to protect. A avoids this; the
  risk is choosing B/C for purity reasons.
- *Upstream dependency:* betting UI work on Flutter HDR surfaces that may land late or iOS-first.
- *Ecosystem fragmentation:* HDR posts that look different (or broken) per client, per app version,
  per browser — support burden and artist confusion.
- *Feed dynamics:* glow as engagement bait degrading the Club's feel; needs a policy answer before
  the first HDR post, not after.
- *Format churn:* committing to a carrier (Ultra HDR vs cICP-PNG vs AVIF vs ISO 21496-1 sidecar)
  while the standards race is still running.

## 7. Cheaper adjacent tiers (mentioned for completeness, not analyzed in depth)

- **Display-only boost:** render existing SDR art with mild extra headroom on capable screens, no
  authoring. Engine untouched; still pays the full §3 display cliff; artistically it's a filter, and
  the Instagram precedent suggests restraint.
- **Export-only HDR:** editor stays SDR; an "Export as Ultra HDR / HDR PNG" item derives a glow from
  luminance heuristics or a one-off user mask. Cheapest way to experiment with real files on real
  phones (visible in Google/Apple Photos today) without touching display, engine, or Club — a
  plausible spike vehicle for learning the gain-map toolchain.

## 8. Facts that would change this analysis if they became true

Recorded as observations, not recommendations:

1. Flutter ships HDR/extended-range rendering (or gain-map image display) on Android and iOS — the
   display cliff, the dominant cost, collapses.
2. ISO 21496-1 gain maps land in a lossless carrier with broad decode (PNG ratification + OS
   support) — the interchange-format problem collapses.
3. The server's variant pipeline gains HDR awareness (or variants are deprecated in favor of the
   byte-identical native file) — half the Club cost collapses.
4. Evidence of demand: pixel artists elsewhere adopting emissive/HDR workflows, or Club users asking
   for it — the "niche gain" assessment in §4B would need revisiting.

---

*Repo facts in §2/§4/§5 were verified against the working tree on 2026-08-10. Platform claims:
[Android Ultra HDR](https://developer.android.com/media/platform/hdr-image-format),
[Flutter wide-gamut migration guide](https://docs.flutter.dev/release/breaking-changes/wide-gamut-framework),
[PNG gain-map proposal](https://github.com/w3c/png/issues/380), and the
[immich Ultra HDR discussion](https://github.com/immich-app/immich/discussions/7262) for the
Flutter-app state of the art.*
