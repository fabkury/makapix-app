# Marketing assets

Advertising image assets for the Makapix Editor (App Store / Play Store listings, Discord/Reddit
shares). One asset per highlighted feature, plus a hero banner. Style: near-black background,
`#4080C0` blue accent, white pixel-style headline + small subline.

## Format matrix

Every feature composition is rendered to five canvases:

| Target                | Size (px)   | Notes                                          |
|-----------------------|-------------|------------------------------------------------|
| Play Store screenshot | 1080×1920   | 9:16 (Play caps aspect at 2:1), 24-bit, ≤8 MB |
| App Store screenshot  | 1320×2868   | iPhone 6.9" portrait, scales down              |
| App Store iPad        | 2064×2752   | 13" iPad Pro portrait (square layouts)         |
| Social landscape      | 1200×630    | Discord/Reddit/OpenGraph                       |
| Social square         | 1080×1080   | feeds                                          |

Plus one **Play feature graphic** 1024×500 (hero only). All outputs are flattened to
24-bit RGB — both stores reject PNGs with an alpha channel.

## The slides (2026-08-31 redesign)

Play takes 01..08 (its listing caps at 8 screenshots); the App Store additionally
takes `09_select` and `10_files` (it allows 10). Layout language: three zones per
slide (primary demo, secondary proof panel, chip ticker), community art credited
`@handle` on-slide.

1. **Hero** — "A pixel art studio in your pocket" (community-art wall + the editor
   with @birds' "senna fixed" open; that piece carries a `.mkpx`, hence its
   DRAWN IN MAKAPIX tag)
2. **Free** — "Free. Ad-free. Open-source." (three statement panels + the GitHub
   repo line; replaced the palette slide 2026-08-31 by user decision — palette
   coverage lives on as a chip on the color slide; moved up to slot 2 same day)
3. **Replay** — "Your art draws itself" (engine-rendered progress filmstrip of the
   staged lakeside scene + the real replay viewer; MP4/GIF/WebP timelapse chips)
4. **Animation** — "1,024 frames. 128 layers." (64 until 2026-09-14, ADR 0032) (ball fan + the timeline holding
   @Badguy's 16-frame "cozy blizzard")
5. **Paint** — AA off/on, the airbrush trio, 8-stop gradient, single-coat stroke
   (all engine renders) + the real AA-chip tool row
6. **Patterns** — "Dither with one tap" (added 2026-09-04, ADR 0025): a Bucket-shaded
   dithered sphere, one Brush stroke through a crosshatch, the Gradient's smooth /
   2×2 / 8×8 dither ramps, a catalog tile strip (all engine renders) + the real
   Patterns page in a phone frame and the Pencil's row-1 with the Pattern swatch On
7. **Color** — RGBA ghost on checker + blend-mode grid + Levels before/after
8. **Club** — credited community grid + the Recommended feed (finale)
9. **Select** (App Store only since 2026-09-04) — selection canvas + mode row +
   cleanEdge vs nearest zoom
10. **Files** (App Store only) — import/export format flow

## Community art rules

`art/club/` holds pieces downloaded from the public recommended feed
(`credits.json` maps file -> title/handle/sqid). Only original art may appear:
**no third-party game IP, no brand/licensed characters, no photo-import
likenesses** — that rule extends to any screenshot's visible viewport (feed
shots are cropped above rows containing fan-art; the My Drawings gallery is not
shown at all). On-slide credit `@handle` is mandatory for community pieces.

## Per-language phone shots (2026-10-02)

`shots/<lang>/` (en, es, pt, fr, de, ru, ja, zh) hold the phone shots for the translated
slides, taken on the Pixel 10 Pro XL with the language-preview build (`L10N_PREVIEW=true`):

| file | state | crop it feeds |
|---|---|---|
| `hero_senna.png` | editor, @birds' "senna fixed", Pencil, pattern Off | `hero_senna_app` |
| `row1_pattern.png` | Pencil options row scrolled to its end, pattern On | `row1_pattern` |
| `patterns_page.png` | Patterns page, first Recent pattern selected | `patterns_page_app` |
| `select_union.png` | Select tool, Oval + Add (row only; the canvas is senna) | `select_row` |
| `row1_aa.png` | Shape options row scrolled to its end, AA on | `row1_aa` |
| `club_profile.png` | @Badguy's profile, Gallery tab | replaces `club_feed_new_app` |

Language-free crops stay English-only: `timeline_cozy_row` (frame numbers) and `select_canvas`
(the selection on the sunset). Decisions: the Club slide shows @Badguy's profile instead of the
Recommended feed, because the live feed and its trending bar now carry game names and art whose
origin cannot be verified; `club_profile.png` is stored already cropped to y < 2040, above a
third row that holds a piece we could not vouch for. The replay slide drops its phone panel in
every language (user decision): senna has no real recording, and the slide's engine-rendered
filmstrip carries the point. Shot tooling (adb, per-language scripts) is described in
`docs/i18n/PLAN.md`, L4.

## Languages (2026-10-02)

The slides exist in all eight app languages. Copy lives in `src/copy/<lang>.json`, one file per
language with the same keys as `en.json` (the build refuses a file with a key missing). Keys ending
in `.sub` are sentence-case sublines in the system sans; every other string is drawn in Press
Start 2P and is written in capitals. A leading `+` marks a highlighted chip. Terms follow the
app's own ARB strings (tool names, blend modes) and `docs/i18n/GLOSSARY.md`; each language's copy
was checked by an independent native-level review.

| | outputs |
|---|---|
| `en` | every format: `out/<format>/`, `out/play_feature_graphic.png` |
| es, pt, fr, de, ru, ja, zh | store formats only: `out/<lang>/{play,appstore,ipad}/`, `out/<lang>/play_feature_graphic.png` (`--all-formats` adds social/square) |

Decisions and mechanics:

- **Store formats must fit; social/square only warn.** After each render the page reports any
  text that wraps a word, overflows its box, or pushes the slide past its height; a store-format
  misfit fails the build.
- **Accented capitals.** Press Start 2P draws Ó, Ü, Ё, Й... as a shrunken letter under its mark,
  which reads as lowercase in a headline. The build (`_lift_accents`) draws the full-size capital
  and lifts the font's own spacing mark one font pixel above it; Ç and Œ use the font's glyphs.
  Sublines (`.sub`) are untouched. Languages with lifted accents get a quarter em more chip
  padding, top and bottom, so a mark never touches a chip border.
- **Numbers** are written as the store listings write them: 1024 without a separator outside
  English.
- **CJK.** Japanese and Chinese headlines and labels use Noto Sans JP / SC (bold, regular style,
  user decision) after Press Start 2P, which still draws their Latin letters and digits. The build
  subsets the full fonts to the characters the copy uses into `src/fonts/Noto*-slides.woff2`
  (committed, ~100-160 KB) and checks coverage. The full fonts are not committed: to change ja/zh
  copy, put `NotoSansJP.ttf` / `NotoSansSC.ttf` (the variable fonts from github.com/google/fonts,
  `ofl/notosansjp`, `ofl/notosanssc`) in `src/fonts/cache/` first.
- **Prices** use each store's currency (R$ 0, 0 €, 0 ₽, ¥0), with a 0.35 em `.gap` span in place
  of the space, which the monospace font would draw a full cell wide; Spanish says GRATIS
  because one Spanish set serves both es-419 and es-ES.
- **Phone crops** come from `shots/<lang>/` (above); `art/crops/<lang>/` is generated and ignored.
- Chrome renders with `--disable-lcd-text`, so pixel-font edges are grayscale, not color-fringed.

Build one language or slide: `python docs/marketing/src/build.py --lang de [--all-formats] [hero free ...]`
(from the repo root). Store mapping: Play takes `out/<lang>/play/` + the feature graphic (es
for both es-419 and es-ES); the App Store takes `appstore/` (6.9" iPhone) and `ipad/` (13" iPad).

## Pipeline (reproducible)

- `src/engine/*.txt` — mkpx DSL scripts; rendered via `cargo run -p makapix-cli` `render` probes
  into `art/` (run from the repo root; the render probe wants relative paths).
- `shots/` — real phone screenshots (adb screencap), raw.
- `art/` — engine renders + downloaded artworks used in compositions.
- `art/club/` — community art from the public recommended feed (see the rules above);
  `credits.json` carries the attribution data the layouts read.
- `src/build.py` — holds the slide specs (copy + per-orientation layout builders), writes one
  HTML page per (slide × format) into `src/_build/`, renders each with headless Chrome
  (`--screenshot --window-size=W,H --force-device-scale-factor=1`) into `out/<target>/`,
  then verifies exact pixel dimensions with Pillow and flattens to RGB.
- `src/copy/` — the slide text, one JSON file per language (see Languages).
- `src/fonts/` — Press Start 2P (headlines) and the Noto Sans JP/SC slide subsets, bundled with
  their OFL licenses (`OFL.txt`, `OFL-NotoSans.txt`); `cache/` (ignored) holds the full CJK fonts.
- `art/fab/` — Fab's own original published artworks (the generative #cgen pieces), pulled
  from the public API for the hero strip. Fan-art posts are deliberately excluded: no
  third-party game IP may appear in store marketing.

Full rebuild:

```powershell
cargo build -p makapix-cli --release
python docs/marketing/src/engine/gen_art.py   # engine-rendered demo art -> art/
python docs/marketing/src/build.py            # compositions -> out/
```

`out/_sheet_*.png` are review contact sheets, not deliverables.
