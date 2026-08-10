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

## The features (one asset each)

1. **Frames & layers** — "1,024 frames. 64 layers." (designed graphic: receding frame stack)
2. **True RGBA** — real 8-bit alpha, not chroma-key (designed graphic: alpha demo on checker)
3. **Blend modes** — Multiply/Overlay/Screen/Difference… (engine-rendered mode grid + phone shot)
4. **Selection algebra** — add/subtract/intersect + select layer pixels (diagram + phone shot)
5. **Levels tool** — before/after + the Levels sheet (phone shot + engine render)
6. **Ruler** — distances and angles (phone shot)
7. **Palette** — import/export/sort by similarity (phone shot + palette strips)
8. **cleanEdge rotate/scale** — cleanEdge vs nearest-neighbor comparison (engine renders)

## Pipeline (reproducible)

- `src/engine/*.txt` — mkpx DSL scripts; rendered via `cargo run -p makapix-cli` `render` probes
  into `art/` (run from the repo root; the render probe wants relative paths).
- `shots/` — real phone screenshots (adb screencap), raw.
- `art/` — engine renders + downloaded artworks used in compositions.
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
