# Patterns (dither and texture masks) — design

**Status: designed 2026-09-03/04, NOT implemented.** Every decision below was taken with the user
in a four-round question pass on 2026-09-03; this document records them so implementation can start
without re-deciding anything. Companion ADR: [ADR 0023](../adr/0023-patterns-are-a-paint-gate.md).
Code references are to `21a09080`. Inventory entry: `docs/editor-gaps/INVENTORY.md` A2.

## What it is

A **pattern** is a small repeating bitmask (up to 8×8) that gates painting: where the pattern bit
is ON the tool paints as usual; where it is OFF the pixel is left untouched. Anchored to the canvas
grid, so overlapping strokes always tile seamlessly. Pencil, Brush, Eraser, and Bucket get a
**Pattern** swatch at the end of row-1; the Gradient gets a different, related thing — **ordered
dithering** between adjacent stops using a Bayer matrix. A full-screen **Patterns page** holds the
catalog (~110 built-in tiles) and a recently-used strip.

## Decisions (2026-09-03)

| Question | Decision |
|---|---|
| New tool or a mode? | **A mode on existing tools**, no new tile. Pencil · Brush · Eraser · Bucket get the mask; Gradient gets Bayer ordered dithering. Line/Shape, Airbrush, Dodge/Burn: **not in v1** |
| Meaning of an OFF bit | **Always untouched.** No second color. Two-color dithers are two strokes with complementary patterns (the catalog carries every inverse) |
| Anchoring | **Canvas grid, origin (0,0) of the canvas**, no offset/phase control, no scale control. A size-1 tap on an OFF pixel paints nothing — accepted (Aseprite/PMNG behavior) |
| Catalog | **Built-in, ~110 tiles up to 8×8**; custom patterns (from selection, or a mini editor) are a documented follow-up, needing no new verb |
| Bayer ladders | **Flat entries at coarse steps**: 2×2 all 5 levels · 4×4 all 17 · 8×8 at 17 steps (every 4th level). No density slider |
| Other families | Lines H/V at 2/3/4-px pitch · diagonals + crosshatch at 2/3/4-px pitch · dots, grids, bricks, checker cells 2×2/3×3/4×4. Inverses generated automatically. Stipple/noise and waves/scales: **not in v1** |
| Gradient | **Own state**: Bayer 2×2 / 4×4 / 8×8 as *families* (not density entries) + Off, remembered separately from the global pattern. Dither applies **pairwise between adjacent stops**, Linear and Radial, with Smoothstep still shaping the blend factor before thresholding |
| Scope of the selection | **One global pattern; On/Off per tool.** Pick Bayer 4×4 once; Pencil can be On while Bucket is Off |
| On/Off UX | The page lists **Off** first; **long-press** (right-click on desktop) on the swatch toggles Off ↔ last pattern without opening the page. Swatch: dimmed with a slash when Off; the tile in the primary color when On |
| Placement and name | **End of row-1**, called **"Pattern"**; page title **"Patterns"** |
| Recents | **10, editor-wide, persisted** across sessions and pillar switches (like the gradient roster). Off is never a recent |
| AA | **Forced off while the pattern is On**; the AA chip greys out; AA returns when the pattern goes Off |
| Pixel-perfect | **Runs first, then the mask** (the thinning tail stays geometric; OFF bits are dropped at write time) |
| Bucket | "All layers" and Threshold **unaffected**: the region is computed as today, the mask only decides which pixels inside it get painted |
| Precision / Slow / selection | **As today.** A reticle DRAW is one masked dab; the selection clips as for any stroke |
| Journal | **Record the bits**: `SetPattern(w,h,hexbits)` carries the tile itself; catalog names are UI-only |
| Next step | Design note + ADR now (this document); **implement later, on request** |

## The model

```
Pattern { w: u8 (1..=8), h: u8 (1..=8), bits: u64 }   // row-major, bit (y*w + x), LSB first
on(x, y) = (bits >> ((y mod h) * w + (x mod w))) & 1   // x, y in CANVAS coordinates
```

- **Canvas coordinates, not storage coordinates.** The engine paints in storage space (the overscan
  gutter offsets the canvas by `canvas_rect.x/y`); the gate subtracts that origin so the phase is
  tied to the artwork, not to the gutter.
- **Consequences of canvas anchoring**, all accepted: `ResizeCanvas` with a non-top-left anchor
  shifts existing pixels relative to the origin, so an old dither may sit out of phase with new
  strokes; Move carries the phase along with the pixels; nothing re-aligns automatically. Aseprite
  behaves the same.
- **The gate is a second mask alongside the selection.** Both are pure per-pixel predicates
  evaluated at write time; their order is irrelevant.
- A pattern of all-ON bits is equivalent to Off; the catalog never contains one.

## Engine

**`crates/engine/src/tool.rs`**

- `pub struct Pattern { w, h, bits }` with `Pattern::parse(w, h, hex) -> Option<Pattern>` (rejects
  w/h outside 1..=8 and bits beyond `w*h`), `Pattern::on(x, y)`, `Pattern::to_dsl()`.
- `Settings.pattern: Option<Pattern>` (global; `None` = Off).
- `GradientSpec.dither: u8` ∈ {0, 2, 4, 8} (0 = Off).
- Bayer matrices as `const` tables (2×2, 4×4, 8×8) in `tool.rs`, integer thresholds
  `bayer_n[y][x] ∈ 0..n²`. One helper `bayer_threshold(n, x, y) -> u16`.

**Verbs (`crates/engine/src/session/parse.rs`)**

| Verb | Effect |
|---|---|
| `SetPattern(w, h, hexbits)` | `settings.pattern = Some(..)`. Hex is up to 16 digits, no `0x`. Malformed → parse error (the line is dropped under the replay line-skip rule) |
| `SetPattern(off)` | `settings.pattern = None` |
| `SetGradientDither(n)` | `settings.gradient.dither = n`, n ∈ {0, 2, 4, 8}; anything else → parse error |

Both are settings verbs: applied immediately, **frozen at stroke start** for the coat tools
(ADR 0007 — `PaintCtx` gains `pattern: Option<Pattern>` and `origin: Point`), read at tap time for
Pencil and Bucket, read at commit time for Gradient. Add both to the fuzz `actions` target's verb
list and to the shell's `replay/visible_index.dart` settings allowlist.

**Where the gate applies**

| Path | File / fn | Change |
|---|---|---|
| Pencil (plain and pixel-perfect) | `tool::plot` (`tool.rs:270`), called from `stamp_active` and `pencil_perfect_segment` | `plot` gains a `gate: Option<(&Pattern, Point)>` argument (pattern + canvas origin) checked after the selection. The pixel-perfect tail (`pp`) keeps recording geometry with the pre-stroke color; a masked-off pixel was never written, so its "restore" is a no-op — thinning stays exactly geometric |
| Brush, Eraser | `StrokeCoat::raise` (`coat.rs`) | Skip the raise when the gate is OFF at (x, y). Because the gate lives at raise time, the display-time coat overlay (preview) and `commit_into` agree by construction — the ADR 0007 invariant holds without extra work |
| Bucket (tap and reticle Fill) | `tool::flood_fill` via `flood_fill_at` (`session.rs:2320`) | Region computed exactly as today (threshold, contiguous, "All layers" reference); the write loop consults the gate. The flood's visited set is unaffected, so a masked-off pixel still propagates the fill |
| Gradient | `tool::apply_gradient` / `gradient_color_at_sorted` (`tool.rs:403`) | With `dither = n`: find the bounding stops `i, i+1` and the local fraction `t` (eased by smoothstep when enabled, as today); output stop `i+1` if `t * n² > bayer_n[y mod n][x mod n] + ½` else stop `i` — **exactly one of the two stop colors, alpha included**, never an interpolation. Integer compare after scaling; the existing f32 fraction is IEEE-deterministic and already on the wire. `last_gradient` (the Repeat snapshot) gains the dither value |
| Airbrush ×3, Dodge, Burn, Line/Shape, Move, Paste | — | Untouched in v1. `open_coat` sets `ctx.pattern = None` for the non-participating coat tools so a stray global pattern can never leak |

**AA.** `Session::open_coat` already limits `aa` to a round Brush/Eraser of size > 1; add
`&& settings.pattern.is_none()`. The shell greys the chip, the engine ignores it — belt and braces,
and a journal that toggles them in an odd order still replays deterministically.

**Determinism and memory.** Pure integer predicates over existing loops; no allocation, no new
transcendental, no new dependency. Nothing in `.mkpx` changes (patterns are tool settings, not
document state).

**Tests (Rust).** Unit: `Pattern::parse` bounds and round-trip; `on()` for every catalog family
shape; Bayer tables match the canonical matrices. Session: Pencil size-1 tap on an OFF pixel writes
nothing; Brush size-5 dab writes exactly the ON subset; pixel-perfect elbow removal under a
checker; Eraser erases ON bits only; Bucket contiguous region unchanged with a gate; Gradient 2-stop
linear under Bayer 4×4 pins to a literal hash (`aa_off_pins.rs` style — a moved pin IS the bug);
smoothstep + dither; radial + dither; alpha stops produce exactly two alphas; `SetPattern` while a
coat is open applies from the next stroke; AA ignored while gated; `assert.roundtrip` through the
CLI with the new verbs. Perf: a 512² Bucket fill with an 8×8 gate stays within the existing
`perf.rs` bounds.

## Shell

**State (`editor_page.dart`)**

```dart
PatternTile? _pattern;                      // the global pattern (last picked; null until first pick)
final Map<String, bool> _patternOn = {};    // per tool: 'Pencil' | 'Brush' | 'Eraser' | 'Bucket'
int _gradDither = 0;                        // 0 | 2 | 4 | 8, Gradient only
final List<PatternTile> _patternRecents = []; // ≤ 10, most recent first
```

`PatternTile` (pure Dart, `app/lib/editor/patterns/pattern_tile.dart`): `w, h, bits (BigInt or two
ints)`, `on(x, y)`, `dsl` → `SetPattern(w,h,hex)`, `inverse`, equality by value.

**Resolution on tool switch.** `_pushToolSettings()` (`editor_page.engine.dart`) — the one block
shared by `_selectTool` and the replay baseline — appends, on its own line (so an old app's replay
line-skip drops only this verb):

```
SetPattern(4,4,5a5a)     // when _patternOn[_tool] == true && _pattern != null
SetPattern(off)          // otherwise
SetGradientDither(4)     // always; 0 when off
```

Toggling the chip or picking on the page sends the same line immediately for the current tool.
The engine therefore holds only "the pattern in force right now"; per-tool memory is a shell
concept, exactly like per-tool Size (`_sizeByTool`) and Precision.

**Row-1 swatch (`editor_page.controls.dart`).** A `PatternSwatch` widget at the **end** of row-1
for Pencil, Brush, Eraser, Bucket, and Gradient:

- Renders the tile repeated to fill the chip (≈ 3×3 repeats of an 8×8 tile at 2 logical px per
  bit), ON bits in the **primary color** over the row background; Off = the last pattern dimmed
  with a diagonal slash, or a generic checker glyph if none was ever picked.
- Tap → push `PatternsPage` (for Gradient: filtered to Bayer families + Off).
- Long-press / right-click → quick toggle Off ↔ last pattern (no-op with a toast if no pattern was
  ever picked). Uses the existing long-press/right-click affordance the other chips share.
- While On, the AA chip on Brush/Eraser renders disabled (tooltip "Off while a pattern is on"), and
  `_send('SetAA(false)')` is **not** sent — the engine ignores AA under a gate, and the user's AA
  preference survives untouched for when the pattern goes Off.
- Pencil's Perfect chip is unaffected. Slow, Precision, Threshold, Contiguous, All layers as today.

Keyboard: no new Command in v1 (a `pattern.toggle` Command is a natural later addition through the
Command catalog, ADR 0009).

**Patterns page (`app/lib/editor/patterns/patterns_page.dart`).** A full-screen page in the style
of `palette_page.dart` / `artwork_colors_page.dart`, talking to the editor only through a small
host interface so widget tests run without the engine:

1. **Off** — a first, full-width entry; selected state shown when the current tool is Off.
2. **Recent** — a horizontal strip of ≤ 10 tiles, most recent first; hidden when empty.
3. **Sections**, each a wrap of square tiles with the family name as header:
   Bayer 2×2 (5) · Bayer 4×4 (17) · Bayer 8×8 (17) · Lines (12) · Diagonals & crosshatch (14) ·
   Dots, grids, bricks & checkers (16). Every non-Bayer family lists each tile next to its inverse;
   the Bayer ladders already contain their inverses (level k ↔ n² − k), so nothing is duplicated.
4. Tiles render in the **current primary color** over the page background at an integer scale
   (4 logical px per bit on phones); a long-press shows the tile's name and size.
5. Tapping a tile: sets `_pattern`, sets `_patternOn[tool] = true`, pushes it to the front of the
   recents, sends the verb, pops the page. Tapping Off: `_patternOn[tool] = false`, sends
   `SetPattern(off)`, pops.
6. Gradient variant: the same page with three family entries (Bayer 2×2 / 4×4 / 8×8, previewed as
   the 50 % level) plus Off; picking sends `SetGradientDither(n)`.

**Catalog (`app/lib/editor/patterns/patterns_catalog.dart`).** Pure Dart, generated at first use
from small generator functions, each entry `(id, family, name, tile)`. ids are UI-only (recents and
prefs store the *tile*, so a renamed or reordered catalog never breaks a stored recent).
Generators: `bayer(n, level)` (canonical recursive Bayer matrices; level k turns ON the k lowest
thresholds), `lines(axis, pitch)`, `diagonal(dir, pitch)`, `crosshatch(pitch)`, `dots(pitch)`,
`grid(pitch)`, `bricks(w, h)`, `checker(cell)`, plus `inverse` for the non-Bayer families.
Unit tests: no duplicate tiles across the catalog, every non-Bayer tile has its inverse present, the
Bayer 4×4 level 8 tile is the 2×2 checker's 4×4 expansion, sizes ≤ 8×8, and no all-ON/all-OFF tile.

**Persistence (`editor_page.persistence.dart`).** `shared_preferences`, editor-wide, alongside
`_kGradExtraPref`: last pattern (`"w,h,hex"`), per-tool On flags, Gradient dither, recents (a
string list). Loaded in `_initPersistence` before the first `_pushToolSettings`; fail-soft (a
malformed value = Off).

**Replay / timelapse.** Nothing to do beyond the allowlist entry: journals record the verbs
verbatim and the engine replays them. An app older than this feature replays such a journal
without patterns (its line-skip drops the unknown verb) — the documented behavior for any new verb;
no `#mkpxj` version bump (ADR 0015: bump only on a semantics *fork*, and this is additive).

**Tests (Dart).** `pattern_tile_test.dart` (parse/dsl/inverse/equality), `patterns_catalog_test.dart`
(the invariants above), `patterns_page_test.dart` with a fake host (Off first, recents order and cap,
tap selects and pops, Gradient filter), a controls test that the AA chip disables while On and that
`_pushToolSettings` emits `SetPattern(off)` for a tool whose flag is Off.

## Edge-case policy (all decided; listed so nobody re-litigates them mid-implementation)

- A size-1 Pencil tap, a Precision DRAW, or a Bucket tap that lands only on OFF pixels **paints
  nothing and still costs an undo step** (consistent with painting the same color over itself).
- The Eraser under a pattern **erases ON bits only**; OFF bits keep their pixels.
- Bucket's fill *region* ignores the pattern (a masked-off pixel still propagates); only the writes
  are gated. "All layers" keeps deciding the region from the composite.
- Pixel-perfect thinning is computed on the unmasked line; the mask applies at write time. The
  elbow that gets removed is restored to its pre-stroke color whether or not it was ever painted.
- The selection and the pattern are independent gates; both must pass.
- AA is inert under a pattern in the engine and greyed in the shell; the stored AA preference is
  untouched.
- The pattern's phase is the canvas origin, always. Resize-canvas anchors, Move, and Paste can put
  existing dithers out of phase with new strokes; there is no re-align control (declined:
  offset/phase and scale knobs).
- Gradient dithering yields exactly the two adjacent stop colors per pixel (alpha included) and
  respects Smoothstep before thresholding; radial and linear alike; it composes with the selection.
- Repeat (ADR 0017) re-executes the last Gradient with the dither it was committed with.
- Switching tools re-pushes the resolved pattern state; a mid-stroke `SetPattern` (keyboard or
  replay) applies from the next stroke for the coat tools (ADR 0007) and from the next tap for
  Pencil/Bucket.
- Hidden tools (ADR 0018) keep their per-tool flag while hidden.
- Journals store bits, never names; the catalog can be renamed, reordered, or extended freely.

## Out of scope for v1 (each a documented follow-up, none needing a new verb)

- Custom patterns: capture the selection's alpha as a tile (≤ 8×8, or raise the cap with a wider
  `bits`), or a mini grid editor on the page. `SetPattern(w,h,hex)` already carries arbitrary bits.
- Patterns on Line/Shape (mask the figure raster — the draft preview must show it), Airbrush,
  Dodge/Burn.
- Stipple/noise and wave/scale families; a density slider for the Bayer families.
- Offset/phase and scale controls (declined 2026-09-03).
- A second color for OFF bits (declined 2026-09-03).
- A `pattern.toggle` keyboard Command.

## Effort

Engine + tests: S–M (about a day). Shell: M (about two days — page, catalog, swatch, persistence,
tests). Both are additive; no `.mkpx`, FFI, or journal-format change.
