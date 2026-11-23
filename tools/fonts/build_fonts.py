#!/usr/bin/env python3
"""Convert the Text tool's source fonts into the app's bitmap font assets (ADR 0039).

Usage:
    python tools/fonts/build_fonts.py --vexed <dir> --fusion <dir> [--out app/assets/pixel_fonts]

Sources (NOT in this repository; only the converted data is committed):
  --vexed   the VEXED pixel-font pack: one "<Family>-All" folder per family, each holding the
            family's TTFs. Only each family's regular font is converted.
  --fusion  Fusion Pixel Font BDF releases, unpacked as <dir>/8px, <dir>/10px, <dir>/12px
            (the "proportional-bdf" zips of github.com/TakWolf/fusion-pixel-font).

Output: one .mkf file per font (or font layer), fonts.json (the manifest the app reads), and
the license texts under licenses/. Everything is deterministic: the same sources always give
byte-identical files.

Why a conversion at all: every VEXED outline sits exactly on a 128-unit pixel grid with no
curves, and the Fusion sources are bitmaps to begin with, so 1-bit glyphs lose nothing. The
app then draws text with no outline rasterizer, at each font's one native size.

The .mkf format (little-endian), version 1:
    0   "MKPF"
    4   u8  version (1)
    5   u8  flags (bit 0: a delta layer over a shared base, see below)
    6   u16 native pixel size
    8   i16 ascent    px above the baseline that a line reserves
    10  i16 descent   px below the baseline that a line reserves
    12  i16 line gap  extra px between lines
    14  u16 reserved (0)
    16  u32 glyph count N
    20  u32 kerning pair count K
    24  u32 bitmap byte count
    28  u32[N] code points, ascending
        u8[N]  advance      i8[N] x offset     i8[N] top (rows above the baseline)
        u8[N]  width        u8[N] height
        u32[K] kern left    u32[K] kern right (pairs ascending by left, then right)
        i8[K]  kern adjustment in px
        bitmaps: per glyph ceil(w*h/8) bytes, bit i = y*w + x at byte[i/8] >> (i%8)

The CJK faces come in four language forms that mostly share glyphs, so each size is stored as
one base layer (the glyph most forms agree on, per code point) plus one small delta layer per
form holding only the glyphs that differ. A font lists its layers in lookup order.

Needs fontTools (pip install fonttools) for the TTFs; the BDF reader is standard library only.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from collections import Counter
from pathlib import Path

UNITS_PER_PIXEL = 128  # VEXED exports at 128 font units per pixel

# Families whose regular font is not "<Family_Name>.ttf", and the one family left out.
VEXED_REGULAR = {
    "Party-Pack-All": "Party_Pack_Normal.ttf",
    "Space-Contract-All": "Space Contract.ttf",
}
VEXED_SKIP = {
    "Enter-Input-All",  # keycap pictures typed through a key map, not a writing font
}

FUSION_SIZES = (8, 10, 12)
# (manifest lang tag, BDF file suffix, the name the picker shows, in its own script)
FUSION_FORMS = (
    ("ja", "ja", "日本語"),
    ("zh-Hans", "zh_hans", "简体中文"),
    ("zh-Hant", "zh_hant", "繁體中文"),
    ("ko", "ko", "한국어"),
)

VEXED_CREDIT = "VEXED (v3x3d.itch.io), CC BY 4.0, converted to bitmap data"
FUSION_CREDIT = "TakWolf and contributors (github.com/TakWolf/fusion-pixel-font), SIL OFL 1.1, converted to bitmap data"


class Glyph:
    __slots__ = ("advance", "xoff", "top", "w", "h", "rows")

    def __init__(self, advance: int, xoff: int, top: int, w: int, h: int, rows: list[int]):
        # rows: one int per row, bit (w-1-x) set = pixel x on (the natural "binary picture" order)
        self.advance, self.xoff, self.top, self.w, self.h, self.rows = advance, xoff, top, w, h, rows

    def key(self):
        return (self.advance, self.xoff, self.top, self.w, self.h, tuple(self.rows))

    def trimmed(self) -> "Glyph":
        """The same glyph with empty border rows and columns removed (a tight bounding box)."""
        rows, top, h = list(self.rows), self.top, self.h
        while rows and rows[0] == 0:
            rows.pop(0)
            top -= 1
        while rows and rows[-1] == 0:
            rows.pop()
        if not rows:
            return Glyph(self.advance, 0, 0, 0, 0, [])
        union = 0
        for r in rows:
            union |= r
        w = self.w
        right_pad = (union & -union).bit_length() - 1  # empty columns on the right
        left_pad = w - union.bit_length()  # empty columns on the left
        rows = [r >> right_pad for r in rows]
        return Glyph(self.advance, self.xoff + left_pad, top, w - left_pad - right_pad, len(rows), rows)

    def packed(self) -> bytes:
        n = self.w * self.h
        out = bytearray((n + 7) // 8)
        for y, row in enumerate(self.rows):
            for x in range(self.w):
                if row >> (self.w - 1 - x) & 1:
                    i = y * self.w + x
                    out[i // 8] |= 1 << (i % 8)
        return bytes(out)


def write_mkf(path: Path, px: int, ascent: int, descent: int, gap: int, glyphs: dict[int, Glyph],
              kerns: dict[tuple[int, int], int], delta: bool) -> int:
    cps = sorted(glyphs)
    for cp in cps:
        g = glyphs[cp]
        if not (0 <= g.advance <= 255 and -128 <= g.xoff <= 127 and -128 <= g.top <= 127 and g.w <= 255 and g.h <= 255):
            raise SystemExit(f"{path.name}: glyph U+{cp:04X} does not fit the format ({g.key()[:5]})")
    pairs = sorted(kerns)
    bitmaps = b"".join(glyphs[cp].packed() for cp in cps)
    out = bytearray()
    out += b"MKPF"
    out += struct.pack("<BBHhhhHIII", 1, 1 if delta else 0, px, ascent, descent, gap, 0, len(cps), len(pairs), len(bitmaps))
    out += struct.pack(f"<{len(cps)}I", *cps)
    out += struct.pack(f"<{len(cps)}B", *(glyphs[cp].advance for cp in cps))
    out += struct.pack(f"<{len(cps)}b", *(glyphs[cp].xoff for cp in cps))
    out += struct.pack(f"<{len(cps)}b", *(glyphs[cp].top for cp in cps))
    out += struct.pack(f"<{len(cps)}B", *(glyphs[cp].w for cp in cps))
    out += struct.pack(f"<{len(cps)}B", *(glyphs[cp].h for cp in cps))
    out += struct.pack(f"<{len(pairs)}I", *(l for l, _ in pairs))
    out += struct.pack(f"<{len(pairs)}I", *(r for _, r in pairs))
    out += struct.pack(f"<{len(pairs)}b", *(kerns[p] for p in pairs))
    out += bitmaps
    path.write_bytes(out)
    return len(out)


# ---- VEXED (TTF outlines on a pixel grid) ----------------------------------------------------

def px_exact(units: float, what: str, name: str) -> int:
    v = round(units / UNITS_PER_PIXEL)
    if abs(units - v * UNITS_PER_PIXEL) > 4:  # a stray unit or two is export noise; more is a real off-grid value
        raise SystemExit(f"{name}: {what} = {units} units is not on the {UNITS_PER_PIXEL}-unit pixel grid")
    return v


def rasterize(font, glyph_set, glyf, name: str, font_name: str) -> tuple[int, int, int, int, list[int]]:
    """A glyph's (xoff, top, w, h, rows): nonzero-winding coverage sampled at pixel centers."""
    from fontTools.pens.recordingPen import DecomposingRecordingPen

    g = glyf[name]
    if g.numberOfContours == 0:
        return (0, 0, 0, 0, [])
    pen = DecomposingRecordingPen(glyph_set)
    glyph_set[name].draw(pen)
    vertical = []  # (x, y0, y1, direction) for every vertical edge
    cur = start = None
    for op, args in pen.value:
        if op == "moveTo":
            cur = start = args[0]
        elif op == "lineTo":
            nxt = args[0]
            if cur[0] == nxt[0] and cur[1] != nxt[1]:
                vertical.append((cur[0], min(cur[1], nxt[1]), max(cur[1], nxt[1]), 1 if nxt[1] > cur[1] else -1))
            elif cur[0] != nxt[0] and cur[1] != nxt[1]:
                raise SystemExit(f"{font_name}: glyph {name} has a diagonal edge")
            cur = nxt
        elif op in ("closePath", "endPath"):
            if cur != start:
                if cur[0] == start[0] and cur[1] != start[1]:
                    vertical.append((cur[0], min(cur[1], start[1]), max(cur[1], start[1]), 1 if start[1] > cur[1] else -1))
                elif cur[0] != start[0] and cur[1] != start[1]:
                    raise SystemExit(f"{font_name}: glyph {name} has a diagonal closing edge")
        else:
            raise SystemExit(f"{font_name}: glyph {name} has a curve ({op})")
    x0 = px_exact(g.xMin, f"{name}.xMin", font_name)
    x1 = px_exact(g.xMax, f"{name}.xMax", font_name)
    y0 = px_exact(g.yMin, f"{name}.yMin", font_name)
    y1 = px_exact(g.yMax, f"{name}.yMax", font_name)
    w, h = x1 - x0, y1 - y0
    rows = []
    for py in range(h):  # top row first
        yc = (y1 - py) * UNITS_PER_PIXEL - UNITS_PER_PIXEL // 2
        crossings = sorted((x, d) for x, a, b, d in vertical if a < yc < b)
        row, wind, k = 0, 0, 0
        for pxl in range(w):
            xc = (x0 + pxl) * UNITS_PER_PIXEL + UNITS_PER_PIXEL // 2
            while k < len(crossings) and crossings[k][0] < xc:
                wind += crossings[k][1]
                k += 1
            row = (row << 1) | (1 if wind != 0 else 0)
        rows.append(row)
    return (x0, y1, w, h, rows)


def convert_vexed(root: Path, out: Path) -> list[dict]:
    from fontTools.ttLib import TTFont

    entries = []
    for fam in sorted(p for p in root.iterdir() if p.is_dir() and p.name.endswith("-All")):
        if fam.name in VEXED_SKIP:
            continue
        base = fam.name[: -len("-All")]
        ttf = fam / VEXED_REGULAR.get(fam.name, base.replace("-", "_") + ".ttf")
        if not ttf.exists():
            raise SystemExit(f"{fam.name}: regular font {ttf.name} not found")
        font = TTFont(str(ttf))
        px = px_exact(font["head"].unitsPerEm, "unitsPerEm", ttf.name)
        hhea = font["hhea"]
        ascent = round(hhea.ascent / UNITS_PER_PIXEL)
        descent = round(-hhea.descent / UNITS_PER_PIXEL)
        gap = round(hhea.lineGap / UNITS_PER_PIXEL)
        cmap = font.getBestCmap()
        glyph_set, glyf, hmtx = font.getGlyphSet(), font["glyf"], font["hmtx"]
        glyphs: dict[int, Glyph] = {}
        cache: dict[str, Glyph] = {}
        for cp, name in cmap.items():
            if cp < 0x20 or 0x7F <= cp < 0xA0:
                continue  # control characters carry no picture
            if name not in cache:
                xoff, top, w, h, rows = rasterize(font, glyph_set, glyf, name, ttf.name)
                adv = px_exact(hmtx[name][0], f"{name}.advance", ttf.name)
                cache[name] = Glyph(adv, xoff, top, w, h, rows).trimmed()
            glyphs[cp] = cache[name]
        by_glyph: dict[str, list[int]] = {}
        for cp, name in cmap.items():
            if cp in glyphs:
                by_glyph.setdefault(name, []).append(cp)
        kerns: dict[tuple[int, int], int] = {}
        if "kern" in font:
            for table in font["kern"].kernTables:
                for (left, right), value in sorted(table.kernTable.items()):
                    adj = round(value / UNITS_PER_PIXEL)
                    if adj == 0:
                        continue
                    for lcp in by_glyph.get(left, ()):
                        for rcp in by_glyph.get(right, ()):
                            kerns[(lcp, rcp)] = max(-128, min(127, adj))
        slug = base.lower().replace("-", "_").replace("'", "")
        file = f"vexed_{slug}.mkf"
        size = write_mkf(out / file, px, ascent, descent, gap, glyphs, kerns, delta=False)
        scripts = ["latin"]
        if sum(1 for cp in glyphs if 0x400 <= cp <= 0x4FF) >= 60:
            scripts.append("cyrillic")
        entries.append({
            "id": f"vexed.{slug}",
            "name": base.replace("-", " "),
            "px": px,
            "scripts": scripts,
            "files": [file],
            "source": "vexed",
        })
        print(f"  {file:42s} {px:3d} px  {len(glyphs):5d} glyphs  {len(kerns):5d} kern pairs  {size:8d} bytes")
    return entries


# ---- Fusion Pixel (BDF bitmaps) --------------------------------------------------------------

def read_bdf(path: Path) -> tuple[int, int, int, dict[int, Glyph]]:
    px = ascent = descent = None
    glyphs: dict[int, Glyph] = {}
    cp = adv = bbx = None
    rows: list[int] | None = None
    with path.open("r", encoding="ascii", errors="replace") as f:
        for line in f:
            if rows is not None:
                if line.startswith("ENDCHAR"):
                    w, h, xo, yo = bbx
                    if cp is not None and 0x20 <= cp < 0x110000 and not (0x7F <= cp < 0xA0) and not (0xD800 <= cp < 0xE000):
                        pad = (-w) % 8
                        glyphs[cp] = Glyph(adv, xo, yo + h, w, h, [r >> pad for r in rows]).trimmed()
                    rows = None
                else:
                    rows.append(int(line.strip(), 16))
                continue
            if line.startswith("ENCODING "):
                cp = int(line.split()[1])
            elif line.startswith("DWIDTH "):
                adv = int(line.split()[1])
            elif line.startswith("BBX "):
                bbx = tuple(int(v) for v in line.split()[1:5])
            elif line.startswith("BITMAP"):
                rows = []
            elif line.startswith("PIXEL_SIZE "):
                px = int(line.split()[1])
            elif line.startswith("FONT_ASCENT "):
                ascent = int(line.split()[1])
            elif line.startswith("FONT_DESCENT "):
                descent = int(line.split()[1])
    if px is None or ascent is None or descent is None:
        raise SystemExit(f"{path.name}: missing PIXEL_SIZE / FONT_ASCENT / FONT_DESCENT")
    glyphs.pop(65534, None)  # the .notdef box: the app draws its own missing-glyph marker
    return px, ascent, descent, glyphs


def convert_fusion(root: Path, out: Path) -> list[dict]:
    entries = []
    for size in FUSION_SIZES:
        forms = {}
        metrics = None
        for lang, suffix, _ in FUSION_FORMS:
            path = root / f"{size}px" / f"fusion-pixel-{size}px-proportional-{suffix}.bdf"
            if not path.exists():
                raise SystemExit(f"missing {path}")
            px, ascent, descent, glyphs = read_bdf(path)
            if metrics is None:
                metrics = (px, ascent, descent)
            elif metrics != (px, ascent, descent):
                raise SystemExit(f"{path.name}: metrics differ between language forms")
            forms[lang] = glyphs
        px, ascent, descent = metrics
        # The base layer: per code point, the glyph most forms agree on (ties go to the first form).
        base: dict[int, Glyph] = {}
        for cp in sorted(set().union(*forms.values())):
            votes = Counter()
            first = {}
            for lang, _, _ in FUSION_FORMS:
                g = forms[lang].get(cp)
                if g is not None:
                    votes[g.key()] += 1
                    first.setdefault(g.key(), g)
            best = max(votes.items(), key=lambda kv: (kv[1], -list(first).index(kv[0])))[0]
            base[cp] = first[best]
        base_file = f"fusion_{size}_base.mkf"
        base_size = write_mkf(out / base_file, px, ascent, descent, 0, base, {}, delta=False)
        print(f"  {base_file:42s} {px:3d} px  {len(base):5d} glyphs  {'':>16s}  {base_size:8d} bytes")
        for lang, _, label in FUSION_FORMS:
            delta = {cp: g for cp, g in forms[lang].items() if base[cp].key() != g.key()}
            file = f"fusion_{size}_{lang.lower().replace('-', '_')}.mkf"
            dsize = write_mkf(out / file, px, ascent, descent, 0, delta, {}, delta=True)
            print(f"  {file:42s} {px:3d} px  {len(delta):5d} glyphs  {'(delta layer)':>16s}  {dsize:8d} bytes")
            entries.append({
                "id": f"fusion.{size}.{lang}",
                "name": f"Fusion Pixel {size} · {label}",
                "px": px,
                "scripts": ["latin", "cyrillic", "cjk"],
                "lang": lang,
                "files": [file, base_file],
                "source": "fusion",
            })
    return entries


def write_licenses(fusion_root: Path | None, out: Path) -> None:
    lic = out / "licenses"
    lic.mkdir(exist_ok=True)
    (lic / "vexed.txt").write_text(
        "Pixel fonts by VEXED (https://v3x3d.itch.io/).\n"
        "Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0):\n"
        "https://creativecommons.org/licenses/by/4.0/\n\n"
        "Changes: each family's regular font was converted from its TrueType outlines to 1-bit\n"
        "bitmap glyph data for the Makapix Club app. The designs are unchanged.\n",
        encoding="utf-8", newline="\n")
    if fusion_root is None:
        return
    parts = [
        "Fusion Pixel Font (https://github.com/TakWolf/fusion-pixel-font), sizes 8, 10 and 12 px.\n"
        "Changes: the BDF bitmaps were converted to the Makapix Club app's glyph data; the four\n"
        "language forms of each size share one base layer. The glyphs are unchanged.\n\n"
        "Fusion Pixel Font combines the fonts below; each license follows.\n",
    ]
    seen = set()
    for size in FUSION_SIZES:
        files = [fusion_root / f"{size}px" / "OFL.txt"]
        files += sorted((fusion_root / f"{size}px" / "LICENSES").rglob("*.txt"))
        for f in files:
            text = f.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n").strip() + "\n"
            if text in seen:
                continue
            seen.add(text)
            title = "Fusion Pixel Font" if f.name == "OFL.txt" and f.parent.name.endswith("px") else f.parent.name
            parts.append(f"\n==== {title} ====\n\n{text}")
    (lic / "fusion_pixel.txt").write_text("".join(parts), encoding="utf-8", newline="\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--vexed", type=Path, help="the VEXED pack folder")
    ap.add_argument("--fusion", type=Path, help="the folder holding 8px/ 10px/ 12px/ BDF releases")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "app" / "assets" / "pixel_fonts")
    args = ap.parse_args()
    if not args.vexed and not args.fusion:
        ap.error("give --vexed and/or --fusion")
    args.out.mkdir(parents=True, exist_ok=True)
    manifest_path = args.out / "fonts.json"
    old = json.loads(manifest_path.read_text(encoding="utf-8"))["fonts"] if manifest_path.exists() else []
    fonts = {e["id"]: e for e in old}
    if args.vexed:
        print("VEXED:")
        for stale in [k for k, e in fonts.items() if e["source"] == "vexed"]:
            del fonts[stale]
        for stale in args.out.glob("vexed_*.mkf"):
            stale.unlink()
        for e in convert_vexed(args.vexed, args.out):
            fonts[e["id"]] = e
    if args.fusion:
        print("Fusion Pixel:")
        for stale in [k for k, e in fonts.items() if e["source"] == "fusion"]:
            del fonts[stale]
        for stale in args.out.glob("fusion_*.mkf"):
            stale.unlink()
        for e in convert_fusion(args.fusion, args.out):
            fonts[e["id"]] = e
    write_licenses(args.fusion, args.out)
    ordered = sorted(fonts.values(), key=lambda e: (e["px"], e["source"] != "vexed", e["name"]))
    manifest = {
        "version": 1,
        "credits": {"vexed": VEXED_CREDIT, "fusion": FUSION_CREDIT},
        "fonts": ordered,
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    total = sum(p.stat().st_size for p in args.out.glob("*.mkf"))
    print(f"{len(ordered)} fonts, {total} bytes of glyph data in {args.out}")


if __name__ == "__main__":
    sys.exit(main())
