# Text tool font pipeline

The Text tool (ADR 0039, `docs/text-tool/DESIGN.md`) draws with bundled **bitmap** fonts, each
at its one native pixel size. `build_fonts.py` converts the source fonts into the app's assets:

```
python tools/fonts/build_fonts.py --vexed <VEXED pack folder> --fusion <Fusion Pixel BDF folder>
```

- **Output:** `app/assets/pixel_fonts/` — one `.mkf` per font or font layer, `fonts.json` (the
  manifest the app reads), and `licenses/`. The conversion is deterministic; rerunning it on the
  same sources changes nothing.
- **The sources are not in this repository.** Only the converted data is committed.
  - VEXED pixel fonts: https://v3x3d.itch.io/ (CC BY 4.0). One `<Family>-All` folder per family;
    only each family's regular font is converted. `Enter Input` is left out; `Party Pack` is
    represented by `Party_Pack_Normal`.
  - Fusion Pixel Font: https://github.com/TakWolf/fusion-pixel-font (SIL OFL 1.1). Unpack the
    `proportional-bdf` release zips for 8, 10 and 12 px as `<folder>/8px`, `/10px`, `/12px`.
- **Needs** Python 3 and `fonttools` (TTF reading). The BDF reader uses the standard library.

The `.mkf` format is documented at the top of `build_fonts.py`; the Dart reader is
`app/lib/editor/text/pixel_font.dart`. Each CJK size is one shared base layer plus a small
delta layer per language form (日本語, 简体中文, 繁體中文, 한국어).

Adding a font: put it where the script looks, rerun, commit the new assets. Fonts are data the
shell reads, never part of the engine, so adding or correcting one cannot change how an old
Journal replays (the Journal stores the stamped mask, not the font).
