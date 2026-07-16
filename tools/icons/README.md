# Custom icon pipeline

App-unique replacements for stock Material symbols, delivered as **generated
Dart vector data** (no packages, no assets, no font toolchain).

- `gen_icons.py` — the design library. Every icon is authored here as SVG path
  markup (24×24, 2px rounded strokes, `currentColor`): `S` holds the primary
  smooth designs, `V` alternative variants, plus a retired 16×16 pixel-grid
  experiment. Running it builds review contact sheets (`contact_sheet.html`,
  `round2.html`); Material reference glyphs are optional (see comment in
  `build()` for the download URL).
- `build_final.py` — the **approved set** (user-reviewed picks). Emits:
  `svg/*.svg` (design record), `roundtrip.html` (original vs converted, for
  eyeballing), and `app/lib/editor/makapix_icons.g.dart` (const vector data).
- `svg2dart.py` — the converter: parses the SVG subset the designs use,
  turns arcs/rects/circles into cubics, flattens `stroke-dasharray` into
  explicit dash sub-paths, and encodes segments as flat op streams.

Runtime side: `app/lib/editor/makapix_icon.dart` (hand-written) defines
`MpxIcon`/`MpxSeg` + the `MakapixIcon` widget; `makapix_icons.g.dart` is
generated — never edit it by hand.

## Workflow for new icons

1. Design in `gen_icons.py` (add to `S` or `V`), build a contact sheet, get
   the user's visual approval.
2. Add the approved pick to `FINAL` in `build_final.py`.
3. `python tools/icons/build_final.py` and check `roundtrip.html`.
4. Reference it as `MpxIcons.<name>` (via `ToolDef.custom` for editor tools).

Approved so far (2026-07-16): pencil, airbrush, eraser, fill, line, pick,
selColor, selLyr, flip, select, lasso, onion — 12 of the 28 row-3 tool icons;
the rest still use Material.
