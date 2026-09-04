# Makapix Editor feature-gap inventory

**Date:** 2026-09-03 · **Status: brainstorm, nothing scheduled.** Nothing in this document is
committed work; it is the ranked reference list to pick from. **Sources:** code sweep of the engine
verb catalog (`crates/engine/src/session/parse.rs`), the tool catalog (`app/lib/editor/tools.dart`),
menus, dialogs, and palette I/O at `ba9ca686`; `STATUS.md` §"Remaining gaps"; and a 2026-09-03 web
survey of the competition — desktop (Aseprite 1.3.18, Pro Motion NG 8, Pixelorama 1.2, LibreSprite,
Piskel, GraphicsGale, Pyxel Edit, rx, Lospec Pixel Editor, Pixel Composer) and mobile (Pixaki 4.6,
Resprite R59, Pixquare 2.72, Dotpict, Pixel Studio 5.5, Pixilart, 8bit Painter, Procreate's pixel
workflow). Sources are listed at the end.

**Scope and boundaries (decided 2026-09-03):**

- **Editor only, no server changes.** Nothing here needs `makapix.club` or the Club API to change.
- **Animator territory excluded.** Scenes, stage, props, tweens, keys, camera moves belong to the
  `animator` branch (`docs/animator/`), not to the editor.
- **Engine doctrine respected.** No runtime deps in `crates/engine`, integer-exact determinism,
  8-bit premultiplied RGBA, the four memory budgets, `panic = "abort"`. Ideas that strain a rule are
  kept and **flagged**, not dropped.
- **Standing decisions are honored.** Items parked by earlier decision (HDR, i18n, Aseprite import,
  eraser un-erase, playlists, web build, key-rebinding UI 6.B, Animator hooks) are listed once in
  §6 and **not** re-ranked.
- **Both personas weigh equally:** 📱 the phone hobbyist (touch-first, small canvases, posts to the
  Club) and 🎨 the serious pixel artist (tablet/desktop, stylus or keyboard, sprites and long
  animations). Each item is scored for both so divergences are visible.

**Scoring legend.** Value = H / M / L per persona. Effort = **S** (≲ half a day) · **M** (a day
or two) · **L** (multi-day) · **XL** (a week or more, or a document-model change). Lands in:
**E** engine verb · **S** shell (Dart) · **C** codec · **F** new FFI export · **D** document model
or `.mkpx` chunk · **J** journal/replay implication (a new verb is additive and replays forever;
anything that feeds *external bytes* into the document needs a journal chapter cut, like Import).

---

## 0. Baseline — what the editor already has

Read `STATUS.md` §"Tools & editing" for the full table. The short version, so this document stands
alone: Pencil (pixel-perfect) · Brush · Airbrush ×3 · Eraser · Bucket (threshold, contiguous, all
layers) · Gradient (linear/radial, 2–8 colors, smoothstep) · Line · Shape (rect/ellipse/triangle,
fill/outline, ratio lock) · Ruler (length + angle) · Dodge/Burn · Eyedropper (frame/layer source) ·
Move (layer/pixels/selection, wrap) · Copy/Paste with clipboard swatch · Select
(rect/oval/lasso, add/sub/intersect) · Select by color · Select layer alpha · HSV · Brightness/
Contrast · Levels · Flip · Rotate (90s + free angle, cleanEdge) · Resize (cleanEdge) · Invert ·
AA toggle · Precision off-finger cursor with act-by-button · Slow (geared) drags · Repeat-redo ·
64 layers (opacity, 10 blend modes, lock, hide, merge down, copy to all frames, move-group) ·
1,024 frames (durations, fps presets, playhead, drag reorder, loop-wrapping onion skin) · palettes
(page, naming, sort, from-artwork, .gpl/.json in, .gpl out, five presets) · import of every raster
format with Fit/Stretch/Crop + Place · Open raster as a new drawing · export PNG/WebP stills, GIF and
lossless animated WebP, with integer scale · `.mkpx` v10 · deterministic replay with Watch-replay
and timelapse export (MP4/GIF/WebP) · keyboard shortcuts v1 · hidden tools · 512² canvases.

**Already in the engine, never surfaced in the UI** (each is a shell-only S):

| Capability | Where | Surfacing cost |
|---|---|---|
| `SetLoopMode(Loop\|Once\|PingPong)` | `parse.rs`; only `replay/visible_index.dart` references it | Playback chip + honor in GIF/WebP export (→ A9) |
| `SelectPoly` (polygonal lasso), `SelectCircle` | engine `ToolKind`s, not in the tool grid | A fourth Select-tool mode (→ B20) |
| Gradient **stop positions** (`SetGradientStops`) | engine; UI spaces colors evenly | Draggable stops on a bar (→ B21) |
| `encode_sprite_sheet` | `crates/codec/src/lib.rs:806`, wired to nothing | Export dialog entry (→ B1) |
| `FillNoise(seed)` | stress primitive | Seeded noise/jumble brush (→ C7) |
| `usedcolors` probe / `mkpx_used_colors_sorted_json` | CLI + artwork-colors page | Live color-count badge (→ C9) |
| GIF quantizer | `crates/codec/src/lib.rs:653` | Dither toggle + loop count (→ C10) |

---

## 1. Ranked gap list

### Tier A — high value for both personas, effort ≤ M

These are the "table stakes" the survey found in three or more competitors *and* that fit the
architecture cheaply. Any one of them is a sensible next feature.

| # | Gap | 📱 | 🎨 | Effort | Lands in | Competitors |
|---|-----|----|----|--------|----------|-------------|
| A1 | **Symmetry / mirror drawing** (H · V · both; optional diagonal + rotational) | H | H | M–L | E J | Aseprite, PMNG (cyclic), Pixelorama, LibreSprite, rx, Piskel, Pixaki, Resprite, Pixquare, Pixel Studio, Pixilart |
| A2 | **Dither patterns** on Pencil/Brush/Eraser/Bucket/Gradient (Bayer 2×2/4×4/8×8, lines, dots, bricks; no offset) — **designed 2026-09-04**: `docs/patterns/DESIGN.md` + ADR 0025 | H | H | M | E J | Aseprite (gradient + bucket), PMNG, Piskel, Pyxel, Pixelorama, Pixaki (13 patterns), Resprite, Pixquare, Pixel Studio |
| A3 | **Alpha lock** ("lock transparency": paint only where the layer already has pixels) | H | H | S | E J | Aseprite, LibreSprite, Pixelorama, Pixaki, Resprite, Pixquare |
| A4 | **Replace color** (A → B; layer · frame · all frames scope) | H | H | S–M | E J | Aseprite, Piskel, GraphicsGale, Pixaki (cel/layer/project), Pixquare |
| A5 | **Outline** (1-px stroke around opaque pixels: color, inside/outside, 4/8-connected; layer or selection) | H | H | S–M | E J | Aseprite, Pixelorama, Resprite (layer style), Pixquare, Pixel Studio, Dotpict |
| A6 | **Touch undo/redo gestures** (two-finger tap undo, three-finger redo, hold = rapid) + **long-press eyedropper** on the canvas | H | M | S–M | S | Pixaki, Resprite, Pixquare, Procreate; long-press pick: Pixaki, Resprite, Pixquare |
| A7 | **Reference image underlay** (opacity, lock to canvas, not part of the document) — plus the **remix source as reference** (§4 N4) | M–H | H | M | S | Aseprite, Pixelorama, Lospec, Pixaki (full-res layers), Pixquare, Dots (tracing template) |
| A8 | **Onion skin range · opacity · tint** (prev/next counts, per-side toggle) | M | H | S–M | E F | Aseprite, LibreSprite, Pixelorama, Pixaki (10 frames), Pixquare |
| A9 | **Loop mode UI** — Loop / Once / Ping-pong for playback **and** GIF/WebP export | M | M | S | S C | Aseprite, Pixelorama, LibreSprite, Pixquare |
| A10 | **Trim to content** (canvas to the union of non-transparent bounds across all frames) | M | H | S | E | Aseprite (export), Lospec, Pixquare (export) |
| A11 | **Grid options** (spacing e.g. 8/16 px tile grid, color, subdivisions) + **checker/background settings** (colors, cell size, solid color) | M | H | S–M | S | every desktop tool; Pixaki, Pixquare |
| A12 | **Canvas presets in New** (Game Boy 160×144, PICO-8 128×128, NES 256×240, C64 320×200, Club sizes) with an optional paired palette | M | M | S | S | Lospec, Pixaki, Pixel Studio |

### Tier B — high value for one persona, or A-value at L effort

| # | Gap | 📱 | 🎨 | Effort | Lands in | Competitors |
|---|-----|----|----|--------|----------|-------------|
| B1 | **Sprite-sheet export UI** (rows/cols/horizontal/vertical, padding, scale, JSON frame data) — the encoder exists | L | H | S–M | S C | Aseprite, Pixelorama, Piskel, Pyxel, PMNG, GraphicsGale, Pixaki, Resprite, Pixquare |
| B2 | **Sprite-sheet import** (slice a grid into frames; cell size or rows/cols) | L | H | M | S C | Aseprite, Piskel, Pyxel, PMNG, rx |
| B3 | **APNG export** (a former SPEC must-have; hand-muxed fcTL/fdAT like the WebP muxer) | L–M | M | M | C | Pixelorama, Pixaki, Resprite, Pixquare |
| B4 | **Frame tags / clips** (name, range, direction, color; export per tag) | L | H | L | D S C | Aseprite, LibreSprite, Pixelorama, Pixquare, Resprite (clips) |
| B5 | **Frame range ops** (multi-select frames; reverse; insert/duplicate N; bulk duration already exists) | M | H | M | E S | Aseprite, Pixelorama, PMNG, Pixquare (drag-range) |
| B6 | **Shading ink** (brush shifts each pixel to its palette-ramp neighbor, up or down) | M | H | M | E J | Aseprite, PMNG, LibreSprite, Pixelorama, Pyxel, Pixquare |
| B7 | **Palettize** (quantize layer/frame/all to the active palette, optional dither) | M | H | M | E J | Aseprite, GraphicsGale, Pixelorama, Pixel Studio, Pixquare (indexed) |
| B8 | **Palette ramp generator** (N steps between two swatches, HSV/OKLab) + **more palette formats** (Lospec `.hex`, JASC `.pal`, PNG strip in; `.hex`/JSON/PNG out) | M | H | S | S | Aseprite, PMNG, GraphicsGale, Pixquare, Resprite |
| B9 | **Live 1× preview panel** (small always-looping preview while zoomed in) | M | H | M | S | Aseprite, Pixelorama, GraphicsGale, Piskel, Pixaki, Pixel Studio (mini-map) |
| B10 | **Stylus support**: (a) finger/pen roles + palm rejection ("only draw with pen") — S; (b) pressure → size/opacity dynamics — M | M | H | S / M | S / E J | Pixquare, Pixel Studio, Procreate, Resprite, Aseprite, Pixelorama, PMNG |
| B11 | **Custom brushes** (capture the selection as a stamp; flip/rotate) | M | H | L | E J | Aseprite, PMNG, LibreSprite, Resprite, Pixquare, Pixel Studio |
| B12 | **Clipping mask** (layer clips to the alpha of the layer below) | M | H | M | E D | Pixelorama, Pixaki, Resprite, Pixquare, Pixilart, Dotpict |
| B13 | **Text tool** (bundled pixel fonts, rasterized in Dart, placed with the Paste draft) | M | M | M | S J | Aseprite, Pixelorama, GraphicsGale, PMNG, Resprite, Pixquare, Pixel Studio |
| B14 | **Preferences screen** (default canvas, grid/onion defaults, checker, theme, haptics, confirm-destructive, autosave interval, left-handed) | M | M | M | S | every desktop tool; Pixaki, Pixquare |
| B15 | **Line angle snap** chip (0/45/90 + isometric 26.57° + 30°) for touch — Shift-constrain exists only with a keyboard | M | H | S | S | Pixaki (isometric lock), Pixquare (perfect angle), PMNG |
| B16 | **Tiled / seamless mode** (3×3 repeat display; strokes wrap across edges) | L–M | H | M | E S | Aseprite, PMNG, LibreSprite, Pixelorama, Piskel, Pixel Studio |
| B17 | **OS clipboard interop** (copy pixels out as PNG; paste an image from another app) | M | H | M | S J | Aseprite, Pixelorama, Pixaki, Procreate |
| B18 | **Eyedropper loupe** (magnified ring + color chip while dragging) | M | M | S | S | Resprite, Pixquare, Procreate |
| B19 | **Selection refinements**: expand/contract/border by N px; stroke the selection outline; selection → new layer | M | M | S–M | E | Aseprite, Pixelorama, Resprite (fill/stroke selection) |
| B20 | **Polygonal lasso** (surface `SelectPoly`) | L | M | S | S | Aseprite, Pixelorama, Pixaki |
| B21 | **Gradient stop positions UI** (engine has them) | L | M | S–M | S | Aseprite |
| B22 | **Left-handed / mirrored layout** | M | M | S–M | S | Pixaki, Pixquare, Resprite |
| B23 | **Canvas view rotation** (two-finger, opt-in; 90° steps on desktop) | M | M | M | S | Pixaki, Pixquare, Procreate, Pixel Studio |
| B24 | **Merge visible / flatten frame** · **move a layer to another frame** | L | M | S | E | Aseprite, Lospec, Pixelorama |

### Tier C — small nice-to-haves

| # | Gap | 📱 | 🎨 | Effort | Lands in |
|---|-----|----|----|--------|----------|
| C1 | Playback speed multiplier (0.25×–3×) for preview only | L | M | S | S |
| C2 | Quick-shape: draw-and-hold snaps a freehand stroke to a line/ellipse | M | M | M | S |
| C3 | Stroke stabilizer (input smoothing before `PointerMove`; replay unaffected) | L | M | S | S |
| C4 | Color harmonies in the picker (complement, triad, analogous) | L | M | S | S |
| C5 | Rounded rectangle · N-gon in the Shape tool | L | M | S–M | E |
| C6 | Curve (Bézier) tool | L | M | M | E |
| C7 | Seeded **noise / jumble** brush (the deterministic PRNG makes this a natural fit) | L | L | S | E |
| C8 | Adjustments: **posterize** · **gradient map** (luminance → palette ramp) · **curves** | L | M | S–M each | E |
| C9 | **Color-count badge** + palette-limit warning ("17 colors, palette has 16") | M | M | S | S |
| C10 | GIF export: dither toggle for the quantizer · loop count · transparent-color choice | M | M | S | C |
| C11 | Export: frame range · per-frame PNG ZIP · selection only · "with grid lines" | M | M | S each | S C |
| C12 | Undo history panel (jump to any state; the history is already a list) | L | M | M | S F |
| C13 | Duplicate drawing / "use as template" in My Drawings | L | M | S | S |
| C14 | Guides (draggable H/V lines) + snap-to-grid for figures and selections | L | M | M | S |
| C15 | Pixel aspect ratio display (2:1 for C64/Atari) | L | L | S | S |
| C16 | Draw while playing (auto-advance frames, PMNG "AnimPainting") | L | M | M | S E |
| C17 | Right-button = secondary color on desktop (needs a Secondary slot; today Primary + Prev only) | L | M | S–M | S E |

### Tier D — big bets, model changes, or product decisions first

| # | Gap | 📱 | 🎨 | Effort | Why it is here |
|---|-----|----|----|--------|----------------|
| D1 | **Layer groups / folders** (+ isolated group compositing) | L | M–H | XL | Document model + `.mkpx` chunk + compositor + every layer sheet. Table stakes on desktop; rarely missed on a phone with 64 flat layers |
| D2 | **Linked cels** (one static layer shared by many frames) — or the cheaper **"edit on all frames"** mode (a stroke replayed on every frame's same-index layer, rx multi-brush) | M | H | XL / L | Frames own their layers today; `DuplicateLayerToFrames` is the workaround. The replay-mode variant is shell-only + one verb and gets 70 % of the value |
| D3 | **Indexed-color document mode** | L | M | XL | Conflicts with the 8-bit-RGBA-everywhere doctrine; B7 Palettize + C9 covers most of the use |
| D4 | **Tilemap / tileset layers** (rect/iso/hex, auto-tile) | L | M–H | XL | A game-asset workflow; product question: is the Club a game-dev community? Aseprite, Pixelorama, PMNG, Pyxel, Resprite, Pixquare all have it |
| D5 | **Non-destructive layer effects** (Pixelorama, Resprite layer styles) | L | M | XL | The engine bakes everything; A5 Outline as a destructive op covers the common case |
| D6 | **Multiple open documents / tabs** | L | M | L | The shell mounts one editor page (CLAUDE.md "one pillar at a time"); drawings switch via My Drawings |
| D7 | **Lospec palette browser in-app** (fetch from lospec.com) | M | M | S–M | Not a Makapix server change, but the editor works offline by design and this adds an external host; a policy call |
| D8 | Color cycling (palette animation) | L | L | L | Retro niche; the compositor has no palette indirection |
| D9 | Skew/shear · perspective transforms | L | M | M–L | Another draft-adjust-commit tool over cleanEdge; low demand |
| D10 | **Scripting for users** ("Run DSL script…" sheet) | L | M | S | The DSL exists; the sheet is trivial. The question is whether to expose an internal contract to users. Macros (§4 N1) is the safer product |

---

## 2. Table-stakes matrix

Features the survey found in **three or more** competitors (desktop or mobile), against Makapix
today. ✅ present · ◑ partial · ○ absent.

| Table-stakes feature | Makapix | Ref |
|---|---|---|
| Pixel-perfect stroke | ✅ Pencil "Perfect" | — |
| Symmetry / mirror painting | ○ | A1 |
| Dither brush / pattern paint | ○ | A2 |
| Alpha lock | ○ | A3 |
| Replace color | ○ | A4 |
| Outline | ○ (Shape's Outline is a draw mode) | A5 |
| Shading ink (palette-ramp shift) | ○ | B6 |
| Lighten/darken tool | ✅ Dodge/Burn | — |
| Custom brushes | ○ | B11 |
| Spray/airbrush | ✅ ×3 modes | — |
| Rect/ellipse/lasso/magic-wand selection with add/sub/intersect | ✅ (magic wand = Select by color, contiguous) | — |
| RotSprite-class rotation + scale | ✅ cleanEdge | — |
| Text tool | ○ | B13 |
| Indexed mode / apply palette | ○ | B7 / D3 |
| Palette from image | ✅ From artwork colors | — |
| Palette ramps | ○ | B8 |
| Hue/sat · brightness/contrast · levels | ✅ | — |
| Blend modes | ✅ 10 | — |
| Layer groups | ○ | D1 |
| Clipping masks | ○ | B12 |
| Reference image / layer | ○ | A7 |
| Lock layers | ✅ | — |
| Tilemap layers | ○ | D4 |
| Onion skin with ranges + tint | ◑ toggle only, fixed tint | A8 |
| Frame tags | ○ | B4 |
| Linked cels | ○ (copy to all frames) | D2 |
| Ping-pong / reverse playback | ◑ engine only | A9 |
| Real-time preview panel | ◑ film-strip thumbnails | B9 |
| Sprite-sheet export | ◑ codec only | B1 |
| Sprite-sheet import | ○ | B2 |
| JSON frame metadata | ○ | B1 |
| APNG | ○ | B3 |
| Animated WebP | ✅ | — |
| Video export | ✅ timelapse MP4 (not plain animation MP4) | C11 |
| Scale on export | ✅ 1–32× | — |
| Custom keyboard shortcuts | ◑ fixed defaults, loader ready | §6 |
| Multiple documents | ○ | D6 |
| Themes | ○ | B14 |
| Autosave / crash recovery | ✅ | — |
| Pixel grid with custom size/color | ◑ 1-px on/off | A11 |
| Checker background settings | ○ | A11 |
| Two-finger undo / three-finger redo | ○ | A6 |
| Long-press eyedropper | ○ (desktop right-click / hold-S only) | A6 |
| Two-finger canvas rotation | ○ | B23 |
| Quick-pinch fit | ◑ menu "Fit to screen" + double-tap in crop/place pages | S |
| Offset / precision cursor | ✅ Precision mode (best in class) | — |
| Left-handed layout | ○ | B22 |
| Finger-vs-stylus roles | ○ | B10a |
| Stylus pressure | ○ | B10b |
| Timelapse export | ✅ (Pixaki still lacks it) | — |
| Cloud sync of drawings | ○ (server-side; out of scope) | — |

Where Makapix is **ahead** of the field: deterministic replay + Watch-replay + timelapse, the
Precision off-finger cursor with act-by-button, Slow geared drags, Repeat-redo, AA on pixel-art
figures, the `.mkpx` tile-dedup format, and the built-in social layer.

---

## 3. Tier A and B detail — how each would land here

Sketches only; each becomes its own design note (and usually an ADR) before implementation.

### A1 — Symmetry / mirror drawing

- **Engine.** `SetSymmetry(mode, ax, ay)` — mode ∈ {Off, H, V, Both, (later) Diag, Rot N}; the axis
  defaults to the canvas center and is a half-pixel-aware integer (odd canvases mirror through a pixel
  column, even ones between two). Every stroke dab, figure raster, and bucket seed is duplicated
  through the axis **into the same coat**, so overlapping mirrored coverage resolves by the existing
  max-coverage rule (ADR 0007) and AA stays exact. Selections: a mirrored marquee is a nice-to-have,
  not v1.
- **Shell.** A row-1 chip on the drawing tools (or one global chip like AA); the axis drawn as a
  dashed overlay; drag-to-move the axis in a small "adjust" mode.
- **Replay.** One additive verb; the journal stays byte-deterministic. Goldens: new pins only.
- **Risk.** Interaction with Precision mode (the reticle mirrors too), with Move (does the draft
  mirror? — no, by analogy with Aseprite), with Bucket in "all layers".

### A2 — Dither patterns

**IMPLEMENTED 2026-09-04** as designed in `docs/patterns/DESIGN.md` + ADR 0025 (a paint *gate*
with `SetPattern(w,h,hex)`, not the `SetDither(pattern, ox, oy)` sketch below; no offset control).
The notes below are the original brainstorm.

- **Engine.** `SetDither(pattern, ox, oy)` with pattern ∈ {Off, Checker, Bayer2, Bayer4, Bayer8,
  custom 8×8 bitmask}. Applied as a **coverage mask on the coat** for Pencil/Brush/Eraser/Bucket
  (only pattern-on pixels are touched, PMNG style), and as **ordered dithering between adjacent
  stops** for Gradient (Aseprite style: threshold the stop blend against the Bayer matrix instead of
  interpolating — this yields the classic two-color dither ramps pixel artists actually want).
- **Shell.** A pattern chip with a small popup of pattern tiles; the offset toggles by tapping the
  chip again or via two arrows.
- **Determinism.** Pure integer thresholds; nothing to worry about.
- **Doctrine note.** With dither on, the coat-overlay preview must apply the same mask so preview
  == commit, as ADR 0007 requires.

### A3 — Alpha lock

- **Engine.** A per-tool or per-layer flag `SetAlphaLock(bool)`; at coat apply, multiply coverage by
  `dst.a > 0` (or by `dst.a / 255` for a soft variant — pick the hard one, it is what artists expect).
  Half a day including tests. Consider making it a **layer property** persisted in `.mkpx` (Pixaki,
  Pixquare) rather than a tool toggle — that is a small `D` addition but matches the mental model.
- **Shell.** A lock-alpha chip near AA on the drawing tools, or a padlock on the layer tile.

### A4 — Replace color

- **Engine.** `ReplaceColor(rgba_from, rgba_to, scope)` with scope ∈ {Layer, Frame, AllFrames};
  optional tolerance reusing the Bucket threshold. One undo record per frame touched (or one
  compound record — history already supports multi-tile patches). Also the natural home for
  "**palette edit recolors the artwork**": when a palette entry is edited, offer "Also replace in
  artwork" (the slot-bound palette already knows the old value).
- **Shell.** From the row-2 swatch sheet ("Replace in artwork…") and from Select-by-color's row-1
  ("Replace with primary").

### A5 — Outline

- **Engine.** `Outline(color, side ∈ {Outside, Inside}, connectivity ∈ {4, 8}, scope)` over the
  active layer or the selection: a one-pass morphological dilation/erosion of the alpha mask then a
  fill of the ring. Deterministic, tile-local, S. A "drop shadow" is the same op with an offset —
  a free variant.
- **Shell.** A tool tile (Outline) with color chip + side/connectivity toggles, or an entry in the
  layer sheet.

### A6 — Touch undo/redo gestures + long-press eyedropper

- **Shell only.** Two-finger *tap* (down/up within ~200 ms, < 8 px travel, no pinch delta) = Undo;
  three-finger tap = Redo; hold = repeat at ~6/s after 400 ms. Must respect ADR 0010 gesture
  atomicity: a two-finger tap arriving *during* a one-finger stroke either cancels the stroke or is
  ignored — never splits it (see `docs/ui-gaps/REPORT.md` G-01..G-12). Today a second finger begins a
  pinch immediately; the fix is a short pinch-arm delay that distinguishes tap from pinch.
- Long-press eyedropper: one-finger press without movement for ~500 ms enters a transient pick
  (journaled as the same `SelectTool` round-trip the desktop right-click uses), with an adjustable
  delay in Preferences (0 = off, Pixaki/Pixquare convention).

### A7 — Reference image underlay

- **Shell only, never the document.** A `ReferenceLayer` sidecar in the drawing store (path +
  opacity + transform + above/below flag) drawn by the canvas painter in the same canvas space, so
  it pans/zooms with the art. Not journaled, not exported, not in `.mkpx`. Pick from the photo
  picker, the file picker, or **the remix source** (§4 N4).
- **Value split.** The hobbyist traces a photo; the artist keeps a mood board or the previous frame
  of a different drawing. Both are the same widget.

### A8 — Onion skin range / opacity / tint

- **Engine/FFI.** `display()` today takes a boolean; extend to `(prev_n, next_n, prev_alpha,
  next_alpha, prev_tint, next_tint)` and composite N ghosts with falling alpha. S in Rust; the
  loop-wrap stays. A Preferences/onion sheet on the shell side.

### A9 — Loop mode UI

- **Shell.** A Loop / Once / Ping-pong chip in the frame-duration dialog and on the PlayPause row;
  `SetLoopMode` is already journaled. **Export**: GIF/WebP honor ping-pong by emitting the frame list
  forward + reverse-minus-ends; Once sets the container loop count to 1. C is a few lines each.

### A10 — Trim to content

- **Engine.** `TrimCanvas()` computes the union bounding box of non-transparent pixels over **all
  frames and layers** (tile-sparse scan is cheap), then reuses `ResizeCanvas` machinery with an
  explicit offset. One undo record; canvas size travels with the edit as today.

### A11 — Grid options + checker settings

- **Shell.** Draw the coarse grid (every N px, custom color) as a Dart overlay above the engine's
  1-px grid; checker colors/cell size become painter parameters. Persist in Preferences. Both are
  view state, never journaled.

### A12 — Canvas presets

- **Shell.** Named chips in the New dialog beside the square sizes; each preset may carry a palette
  (PICO-8 → the bundled pico-8 preset, Game Boy → a 4-tone palette). Add Club-conformant sizes.

### B1 / B2 — Sprite sheet out / in

- **Out.** Dialog: layout (rows/cols/horizontal/vertical), padding, scale, "JSON frame data"
  (Aseprite-compatible `frames[]` with durations). Wire `encode_sprite_sheet`. Shell M, codec S.
- **In.** Extend the import crop page with a "Slice as sprite sheet" switch: cell W×H or rows×cols,
  margin/spacing; every cell becomes a frame (or a layer). The Place step still applies.

### B3 — APNG export

- Codec-only. Reuse the PNG encoder for IDAT of frame 0, then emit `acTL` + per-frame `fcTL`/`fdAT`
  from the same zlib stream the WebP path already produces per changed rect. Pure Rust, no new deps.
  The reason it slipped: the Club uses WebP, so APNG only matters for Discord/iMessage/web sharing.

### B4 — Frame tags / clips

- **Document.** A `tags[]` list (name, from, to, direction, color) in a new `.mkpx` chunk (additive,
  old readers ignore it). Verbs `AddTag/EditTag/RemoveTag`. The film strip shows tag bands; playback
  can loop the active tag; export gets a "tag" selector; sprite-sheet JSON emits them. L because the
  strip UI is the bulk.

### B5 — Frame range ops

- **Engine.** `ReverseFrames(a, b)`, `InsertFrames(at, n)`, `DuplicateFrameN(i, n)`. **Shell.** A
  multi-select mode on the film strip (long-press, then tap to extend) whose sheet offers
  delete/duplicate/reverse/duration for the range. The ADR 0022 two-tap confirm covers delete.

### B6 — Shading ink

- **Engine.** The engine already holds palettes. `SetShading(ramp_id | AutoByPaletteOrder)`; a
  Shade tool (or an ink chip on Brush) looks up each covered pixel's nearest palette index and
  writes the next/previous ramp entry. Deterministic. Palette order is the ramp unless the palette
  page gains explicit ramps (B8).

### B7 — Palettize

- **Engine.** `ApplyPalette(scope, dither)`: nearest palette color per pixel (integer RGB distance),
  optional ordered dither (A2's matrices). Batch across frames; one undo record per frame. This is
  the 80 % of indexed mode with none of the model change.

### B8 — Palette ramps + formats

- **Shell.** Ramp generator in the palette page: pick two swatches, N steps, HSV or OKLab (Dart
  math is fine — palettes live outside the engine's determinism boundary). Formats: `.hex` (Lospec
  one-hex-per-line), JASC `.pal`, PNG strip in; `.hex` + JSON + PNG strip out. All S.

### B9 — Live 1× preview panel

- **Shell.** A small floating widget that plays the composited frames (it can reuse the film-strip
  thumbnail cache or `mkpx_composite_frame`) at 1×/2×, dockable to a corner, hidden by default on
  phones. Landscape/tablet layouts benefit most.

### B10 — Stylus

- **(a) Roles, S.** A Preferences setting: "Finger draws / Finger only pans / Finger erases"; pointer
  kind is already distinguished for mouse in `editor_page.canvas.dart`.
- **(b) Pressure, M.** Extend `PointerMove(x, y)` with an optional pressure (0–255) argument; the
  engine maps it to size and/or opacity per a `SetDynamics` verb. The journal records the pressure
  so replays stay exact; old journals parse (missing arg = 255). Flag: per-dab size changes vary the
  coverage inside one coat but do not break the single-coat max-coverage rule.

### B11 — Custom brushes

- **Engine.** `SetBrushFromSelection()` snapshots the selected pixels (or their alpha) as the stamp;
  `SetBrushFlip/Rotate`. The stamp is derived from document content, so the journal replays it
  without external bytes. L because the coat/raster path assumes round/square footprints today.

### B12 — Clipping mask

- **Engine + document.** Per-layer `clip_below` flag in the layer table (`.mkpx` additive); the
  compositor multiplies the layer by the alpha of the nearest non-clipped layer below. Merge-down
  bakes it. M; the UI is a chip on the layer sheet plus an indent on the tile.

### B13 — Text tool

- **Shell-side rasterization** with two or three bundled bitmap pixel fonts (public-domain
  5×7 / 3×5 / 8×8), placed through the existing **Paste draft** (drag, Slow, commit). The text bytes
  come from outside the document, so the journal needs the same treatment as Import (a chapter cut)
  — or a `PasteGlyphs(font, text)` verb that re-rasterizes from a font bundled *in the engine*
  deterministically, which keeps the journal self-contained. Prefer the verb.

### B14 — Preferences screen

- **Shell.** Consolidate the existing ad-hoc `shared_preferences` keys under ☰ → Preferences:
  default canvas size, grid/checker/onion defaults (A8/A11), theme, haptics, confirm-destructive,
  autosave interval, left-handed (B22), stylus roles (B10a), long-press pick delay (A6). It is the
  landing place for half of this list, which is why it ranks above its own standalone value.

### B15 — Line angle snap

- **Shell.** A "Snap" chip on Line (and Shape's rectangle): the shell rounds the dragged endpoint to
  the nearest allowed angle before `ShapeSet`. Isometric = ±26.57° (2:1), plus 30°/45°/90°. No
  engine change; the journal records the snapped coordinates.

### B16 — Tiled mode

- **Engine.** `SetTiled(bool)`: strokes, figures, and fills wrap modulo the canvas (the Move tool
  already has a `SetWrap` concept). **Shell.** Render the display RGBA 3×3 around the canvas with
  the neighbors dimmed. Onion skin and selection stay on the center tile.

### B17 — OS clipboard interop

- **Shell.** Copy → also write a PNG to the system clipboard (`super_clipboard` or platform
  channels; Windows/Android/iOS differ). Paste from the system clipboard → route through Import
  (crop/place) so the journal chapter cut is reused. M mostly for platform plumbing.

### B18 – B24

- **B18 loupe:** a Dart overlay above the finger while Eyedropper drags — magnified 9×9 window +
  hex chip; S.
- **B19 selection ops:** `ExpandSelection(n)`, `ContractSelection(n)`, `BorderSelection(n)`,
  `StrokeSelection(color, width)`, "Layer via cut/copy"; each S in the selection module.
- **B20 polygonal lasso:** a fourth Select mode driving `SelectPoly` — tap vertices, double-tap or
  ✓ to close.
- **B21 gradient stops:** a horizontal bar with draggable stop handles feeding `SetGradientStops`.
- **B22 left-handed:** mirror row-3 order and the sheet anchor sides; a Preferences switch.
- **B23 view rotation:** a view-space rotation in the canvas transform (90° steps first; free
  rotation later). Every screen→canvas mapping goes through one matrix already; the gesture side is
  the work (opt-in, since accidental rotation is a recurring complaint in competitor reviews).
- **B24 flatten / move layer:** `MergeVisible()`, `FlattenFrame()`, `MoveLayerToFrame(i, f)`; S each.

---

## 4. Novel / differentiating ideas

Things no surveyed competitor offers, built on what is unique here: the deterministic engine, the
append-only journal, the checkpoint FFI, and the Club lineage.

| # | Idea | 📱 | 🎨 | Effort | Sketch |
|---|------|----|----|--------|--------|
| N1 | **Macros** — record a verb sequence from the journal ("last 12 actions") and replay it on other frames, layers, or the selection | M | H | M | Repeat-redo (ADR 0017) generalizes: capture a journal slice, re-target the active frame/layer, run it as one compound undo record. Pure engine + journal; no external bytes. Aseprite only has this on its 1.4 roadmap |
| N2 | **Rewind & branch** — open a replay at any checkpoint and fork a *new* drawing from that state | M | M | M | `mkpx_checkpoint_*` already materializes a session at a chapter boundary; "Fork from here" saves it as a new drawing whose journal starts with a chapter anchored on those bytes (ADR 0003). Keeps the making-of history of the original intact (ADR 0015's reasoning) |
| N3 | **Annotated step-through replay** — the Watch-replay viewer shows the tool, size, color, and layer at each step, with a step/scrub control | M | M | M | The journal carries every `SelectTool/SetBrushSize/SetPrimaryColor`; overlaying them is shell work. Makes every Club post a tutorial ("how was this made?") |
| N4 | **Remix source as reference** — when a Club post is opened for remix, offer the original as an A7 reference underlay and a **compare swipe** (before/after) | M | M | S (over A7) | The bytes are already downloaded (`ClubEditRequest`); zero server work |
| N5 | **Re-roll** — for Airbrush/noise strokes, a chip that repeats the last stroke with a new seed | L | L | S | `SetSeed` + Repeat; a fun, deterministic party trick |
| N6 | **Session stats card** — time drawn, strokes, undos, top tools, colors used; optional trailer frame on the timelapse | L | L | S | All derivable from the journal; shareable alongside the timelapse |
| N7 | **Journal-based "what changed"** — when using *Replace original* on a remix, show a diff of frames touched since the source | L | L | S–M | Frame hashes exist (`mkpx_frame_hash`); compare against the source's |

---

## 5. Suggested reading of the list

If the next release wants **one** editor headline: **A1 Symmetry** (asked for by every persona and
absent everywhere in the code) or **A2 Dither** (the single most "pixel art" feature missing).
If it wants a **touch-quality** release: A6 + A7 + A11 + B15 + B18 are all shell-only and together
close most of the mobile table-stakes column. If it wants an **animation** release: A8 + A9 + B5 +
B9 (+ B4 later). **B14 Preferences** should land before or with A8/A11/B10/B22, since each of those
needs a settings home.

---

## 6. Standing exclusions (decided earlier, not re-ranked)

| Item | Decision | Where |
|---|---|---|
| Aseprite `.aseprite` layered import | Designed 2026-08-12, not implemented, do not start unprompted | `docs/aseprite-import/DESIGN.md`, ADR 0005 |
| HDR | Analyzed, not implemented, do not start unprompted | `docs/hdr/ANALYSIS.md` |
| Localization | Deferred by decision | `docs/i18n/DESIGN.md` |
| Eraser "keep RGB" + un-erase | Analyzed, not committed | `docs/eraser-unerase/` |
| Keyboard rebinding UI (6.B) | Open, do not implement unprompted | `docs/keyboard-shortcuts/DESIGN.md` |
| Browser / WebAssembly build | Analyzed only | `docs/web-build/ANALYSIS.md` |
| Battery phases 3–4 + Gate B | Parked | `docs/battery/RECOMMENDATIONS.md` |
| In-RAM compression of inactive frames | Deferred by decision | `STATUS.md` |
| Animator pillar (scenes, tweens, camera) | Lives on the `animator` branch | `docs/animator/` |
| Playlists, cloud sync of drawings, anything server-side | Out of scope for this list | `SPEC-CLUB.md` |

---

## Sources (survey of 2026-09-03)

Desktop: aseprite.org release notes / roadmap / docs (ink, symmetry, tiled-mode, tags, onion
skinning, CLI) · github.com/aseprite/docs (tilemap) · cosmigo.com Pro Motion NG docs + Steam page ·
pyxeledit.com/features · graphicsgale.com/us/spec · lospec.com/pixel-editor · piskelapp.com +
github.com/piskelapp/piskel · github.com/LibreSprite/LibreSprite · pixelorama.org (1.1, 1.2 posts) +
github.com/Orama-Interactive/Pixelorama CHANGELOG · rx.cloudhead.io/guide · docs.pixel-composer.com.

Mobile: pixaki.com user guide (drawing, settings) · resprite.fengeon.com docs (quick start,
gestures) · pixquare.art + docs.pixquare.art (drawing settings, gestures, palette, exporting) ·
Dotpict App Store listing · Pixel Studio App Store / Play / Steam listings · Pixilart mobile page ·
8bit Painter App Store listing · help.procreate.com (gestures, transform interpolation) · Pixelorama
Android devlog · community.aseprite.org (mobile status thread).
