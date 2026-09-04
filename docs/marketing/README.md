# Marketing assets

Advertising image assets for the Makapix Editor (App Store / Play Store listings, Discord/Reddit
shares). One asset per highlighted feature, plus a hero banner. Style: near-black background,
`#4080C0` blue accent, white pixel-style headline + small subline.

## Format matrix

Every feature composition is rendered to four canvases:

| Target                | Size (px)   | Notes                                          |
|-----------------------|-------------|------------------------------------------------|
| Play Store screenshot | 1080×1920   | 9:16 (Play caps aspect at 2:1), 24-bit, ≤8 MB |
| App Store screenshot  | 1320×2868   | iPhone 6.9" portrait, scales down              |
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
4. **Animation** — "1,024 frames. 64 layers." (ball fan + the timeline holding
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
- `src/fonts/` — Press Start 2P (headlines), bundled with its OFL license.
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
