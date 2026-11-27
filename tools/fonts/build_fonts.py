#!/usr/bin/env python3
"""Convert the Text tool's source fonts into the app's bitmap font assets (ADR 0039).

Usage:
    python tools/fonts/build_fonts.py --vexed <dir> --fusion <dir> --cjk <dir> [--out app/assets/pixel_fonts]

Sources (NOT in this repository; only the converted data is committed):
  --vexed   the VEXED pixel-font pack: one "<Family>-All" folder per family, each holding the
            family's TTFs. Only each family's regular font is converted.
  --fusion  Fusion Pixel Font BDF releases, unpacked as <dir>/8px, <dir>/10px, <dir>/12px
            (the "proportional-bdf" zips of github.com/TakWolf/fusion-pixel-font).
  --cjk     the CJK pixel font library: the folder holding ja/, zh/ and ko/, each font as its
            author distributes it (CJK_FONTS below lists the files; tools/fonts/README.md says
            where each comes from).

Output: one .mkf file per font (or font layer), fonts.json (the manifest the app reads), and
the license texts under licenses/. Everything is deterministic: the same sources always give
byte-identical files.

Why a conversion at all: every VEXED outline sits exactly on a 128-unit pixel grid with no
curves, and the Fusion sources are bitmaps to begin with, so 1-bit glyphs lose nothing. The
app then draws text with no outline rasterizer, at each font's one native size. The CJK
library fonts are read from the most exact form each one ships: a BDF, else the bitmap strike
embedded in its TrueType file, else outlines that sit on the pixel grid.

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
import math
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

# ---- the CJK library (--cjk) ------------------------------------------------------------------
# One row per picker entry: id, name, native px, language form (None = no single form), source
# group, reader, file(s). Readers: "bdf", "strike" (the TrueType file's embedded bitmaps at the
# native size) and "outline" (TrueType outlines on the pixel grid). A row with several files
# is a set of language forms stored as one base layer plus a delta layer per form.
# Names: a font whose license reserves its name is listed under a name of our own (SIL OFL 1.1
# forbids showing converted data under a Reserved Font Name); the credit names the original.
JF = "ja/jf-dot/JF-Dot-"
KH = "ja/kh-dot/KH-Dot-"
MARUMINYA = "ko/x12y12pxMaruMinyaHangul/fonts/x12y12pxMaruMinyaHangul.bdf"
CJK_FONTS = (
    # Japanese
    ("k8x12", "k8x12", 12, "ja", "k8x12", "bdf", "ja/k8x12/k8x12_bdf_2021-05-05/k8x12.bdf"),
    ("shinonome.min12", "Shinonome Mincho 12", 12, "ja", "jfdot", "strike", JF + "ShinonomeMin12.ttf"),
    ("shinonome.maru12", "Shinonome Marumoji 12", 12, "ja", "jfdot", "strike", JF + "ShinonomeMaru12.ttf"),
    ("maruminya.12.ja", "MaruMinya 12 \u00b7 \u65e5\u672c\u8a9e", 12, "ja", "maruminya", "bdf", MARUMINYA),
    ("shinonome.min14", "Shinonome Mincho 14", 14, "ja", "jfdot", "strike", JF + "ShinonomeMin14.ttf"),
    ("shinonome.gothic16", "Shinonome Gothic 16", 16, "ja", "jfdot", "strike", JF + "Shinonome16.ttf"),
    ("khdot.dougenzaka16", "KH Dougenzaka 16", 16, "ja", "khdot", "strike", KH + "Dougenzaka-16.ttf"),
    ("khdot.akihabara16", "KH Akihabara 16", 16, "ja", "khdot", "strike", KH + "Akihabara-16.ttf"),
    ("khdot.kabutochou16", "KH Kabutochou 16", 16, "ja", "khdot", "strike", KH + "Kabutochou-16.ttf"),
    ("ayu.min18", "Ayu Mincho 18", 18, "ja", "jfdot", "strike", JF + "AyuMin18.ttf"),
    ("kappa.20", "Kappa 20", 20, "ja", "jfdot", "strike", JF + "Kappa20.ttf"),
    ("khdot.hibiya24", "KH Hibiya 24", 24, "ja", "khdot", "strike", KH + "Hibiya-24.ttf"),
    # Chinese
    ("boutique.9x9bold", "BoutiqueBitmap 9x9 Bold", 10, "zh", "boutique", "outline",
     "zh/BoutiqueBitmap9x9/BoutiqueBitmap9x9_Bold_1.93.ttf"),
    ("changban.12", "ChangBanDianSong 12", 12, "zh", "yzdnn", "bdf",
     "zh/ChangBanDianSong-12/Sources/ChangBanDianSong-12.bdf"),
    ("roundpix.12", "RoundPix 12", 12, "zh-Hans", "zlabs", "outline",
     "zh/ZLabs-RoundPix-12px/release/ZLabsRoundPix_12px_M_CN.ttf"),
    ("changban.16", "ChangBanDianSong 16", 16, None, "yzdnn", "bdf", (
        ("zh-Hans", "\u7b80\u4f53\u4e2d\u6587", "zh/ChangBanDianSong-16/Sources/ChangBanDianSong-SC-16.bdf"),
        ("zh-Hant", "\u7e41\u9ad4\u4e2d\u6587", "zh/ChangBanDianSong-16/Sources/ChangBanDianSong-TC-16.bdf"),
    )),
    ("renou.16", "RenOuFangSong 16", 16, "zh", "yzdnn", "bdf", "zh/RenOuFangSong-16/Sources/RenOuFangSong-16.bdf"),
    ("qiuye.16", "QiuYeYuanTi 16", 16, "zh", "yzdnn", "bdf", "zh/QiuYeYuanTi-16/Sources/QiuYeYuanTi-16.bdf"),
    ("shanwei.16", "ShanWeiZhouHei 16", 16, "zh-Hans", "yzdnn", "bdf",
     "zh/ShanWeiZhouHei-16/Sources/ShanWeiZhouHei-16.bdf"),
    ("fashion.16", "FashionBitmap 16", 16, "zh-Hant", "boutique", "outline",  # its embedded strike is blank
     "zh/FashionBitmap16/FashionBitmap16_0.092.ttf"),
    # Korean
    ("galmuri.11bold", "Galmuri11 Bold", 12, "ko", "galmuri", "bdf", "ko/galmuri/dist/Galmuri11-Bold.bdf"),
    ("galmuri.11condensed", "Galmuri11 Condensed", 12, "ko", "galmuri", "bdf",
     "ko/galmuri/dist/Galmuri11-Condensed.bdf"),
    ("maruminya.12.ko", "MaruMinya 12 \u00b7 \ud55c\uad6d\uc5b4", 12, "ko", "maruminya", "bdf", MARUMINYA),
    ("galmuri.14", "Galmuri14", 15, "ko", "galmuri", "bdf", "ko/galmuri/dist/Galmuri14.bdf"),
    ("dunggeun.16", "Dunggeun 16", 16, "ko", "neodgm", "outline", "ko/neodgm/release/neodgm.ttf"),
)

CJK_CREDITS = {
    "jfdot": "Shinonome, Ayu and Kappa bitmap fonts (public domain), TrueType builds by Jikasei Font Kobo "
             "(jikasei.me), converted to bitmap data",
    "khdot": "KH Dot fonts by Keitarou Hiraki, TrueType builds by Jikasei Font Kobo (jikasei.me), SIL OFL 1.1, "
             "converted to bitmap data",
    "k8x12": "k8x12 by Num Kadoma (littlelimit.net), converted to bitmap data",
    "maruminya": "x12y12pxMaruMinya by hicc and its Hangul edition by Lee Minseo "
                 "(github.com/quiple/x12y12pxMaruMinyaHangul), SIL OFL 1.1, converted to bitmap data",
    "yzdnn": "ChangBanDianSong, RenOuFangSong, QiuYeYuanTi and ShanWeiZhouHei by yzdnn (github.com/yzdnn), after "
             "the KH Dot fonts, SIL OFL 1.1, converted to bitmap data",
    "zlabs": "RoundPix 12 is converted from ZLabs RoundPix 12px by Astro_2539 (github.com/Astro-2539), SIL OFL 1.1",
    "boutique": "BoutiqueBitmap9x9 and FashionBitmap16 by Luke Liu (github.com/scott0107000), SIL OFL 1.1, "
                "converted to bitmap data",
    "galmuri": "Galmuri by Lee Minseo (github.com/quiple/galmuri), SIL OFL 1.1, converted to bitmap data",
    "neodgm": "Dunggeun 16 is converted from NeoDunggeunmo by Eunbin Jeong (github.com/neodgm/neodgm), SIL OFL 1.1",
}

# License assets: file name -> (heading, note, the texts to append, each (title, path in the library)).
CJK_LICENSES = {
    "jfdot.txt": (
        "Shinonome, Ayu and Kappa bitmap fonts",
        "Shinonome Mincho 12 and 14, Shinonome Marumoji 12, Shinonome Gothic 16, Ayu Mincho 18 and Kappa 20\n"
        "are public-domain Japanese bitmap fonts. The app's data was converted from the TrueType builds\n"
        "published as JF Dot fonts by Jikasei Font Kobo (http://jikasei.me/font/jf-dotfont/), read from\n"
        "the bitmaps embedded at each font's native size. The glyphs are unchanged.\n", ()),
    "khdot.txt": (
        "KH Dot fonts",
        "KH Dougenzaka 16, KH Akihabara 16, KH Kabutochou 16 and KH Hibiya 24: typefaces designed by\n"
        "Keitarou Hiraki, made into TrueType fonts by Jikasei Font Kobo (http://jikasei.me/font/kh-dotfont/).\n"
        "Changes: converted from the bitmaps embedded at each font's native size to the Makapix Club\n"
        "app's glyph data. The glyphs are unchanged.\n",
        (("KH Dot fonts", "ja/kh-dot/README_KHDotFont.txt"), ("License", "ja/kh-dot/SIL_Open_Font_License_1.1.txt"))),
    "k8x12.txt": (
        "k8x12",
        "k8x12 by Num Kadoma (https://littlelimit.net/k8x12.htm). Changes: the BDF bitmaps were\n"
        "converted to the Makapix Club app's glyph data. The glyphs are unchanged.\n",
        (("k8x12", "ja/k8x12/k8x12_bdf_2021-05-05/k8x12.txt"),)),
    "maruminya.txt": (
        "x12y12pxMaruMinya and x12y12pxMaruMinyaHangul",
        "MaruMinya 12 (Japanese and Korean entries). Changes: the BDF bitmaps of x12y12pxMaruMinyaHangul\n"
        "were converted to the Makapix Club app's glyph data. The glyphs are unchanged.\n",
        (("x12y12pxMaruMinyaHangul", "ko/x12y12pxMaruMinyaHangul/OFL.txt"),
         ("x12y12pxMaruMinya", "ja/x12y12pxMaruMinya/OFL.txt"))),
    "yzdnn.txt": (
        "ChangBanDianSong, RenOuFangSong, QiuYeYuanTi and ShanWeiZhouHei",
        "Chinese pixel fonts by yzdnn (https://github.com/yzdnn), built on the KH Dot fonts. Changes: the\n"
        "BDF bitmaps were converted to the Makapix Club app's glyph data; the two forms of\n"
        "ChangBanDianSong 16 share one base layer. The glyphs are unchanged.\n",
        (("ChangBanDianSong 12", "zh/ChangBanDianSong-12/OFL.txt"),
         ("ChangBanDianSong 16", "zh/ChangBanDianSong-16/OFL.txt"),
         ("RenOuFangSong 16", "zh/RenOuFangSong-16/OFL.txt"),
         ("QiuYeYuanTi 16", "zh/QiuYeYuanTi-16/OFL.txt"),
         ("ShanWeiZhouHei 16", "zh/ShanWeiZhouHei-16/OFL.txt"))),
    "zlabs.txt": (
        "RoundPix 12 (from ZLabs RoundPix 12px)",
        "\"RoundPix 12\" is a Modified Version of ZLabs RoundPix 12px by Astro_2539\n"
        "(https://github.com/Astro-2539/ZLabs-RoundPix-12px), listed under a different name because the\n"
        "original names are reserved. Changes: the outlines, which sit on the pixel grid, were converted\n"
        "to 1-bit bitmap glyph data for the Makapix Club app. The designs are unchanged.\n",
        (("License", "zh/ZLabs-RoundPix-12px/LICENSE-OFL"),)),
    "boutique.txt": (
        "BoutiqueBitmap9x9 and FashionBitmap16",
        "BoutiqueBitmap 9x9 Bold and FashionBitmap 16, by Luke Liu (https://github.com/scott0107000).\n"
        "Changes: converted to 1-bit bitmap glyph data for the Makapix Club app from their outlines,\n"
        "which sit on the pixel grid. The designs are unchanged.\n",
        (("BoutiqueBitmap9x9", "zh/BoutiqueBitmap9x9/OFL.txt"), ("FashionBitmap16", "zh/FashionBitmap16/OFL.txt"))),
    "galmuri.txt": (
        "Galmuri",
        "Galmuri11 Bold, Galmuri11 Condensed and Galmuri14 by Lee Minseo (https://github.com/quiple/galmuri).\n"
        "Changes: the BDF bitmaps were converted to the Makapix Club app's glyph data. The glyphs are\n"
        "unchanged.\n",
        (("License", "ko/galmuri/ofl.md"),)),
    "neodgm.txt": (
        "Dunggeun 16 (from NeoDunggeunmo)",
        "\"Dunggeun 16\" is a Modified Version of NeoDunggeunmo by Eunbin Jeong\n"
        "(https://github.com/neodgm/neodgm), listed under a different name because the original name is\n"
        "reserved. Changes: the outlines, which sit on the pixel grid, were converted to 1-bit bitmap\n"
        "glyph data for the Makapix Club app. The designs are unchanged.\n",
        (("License", "ko/neodgm/LICENSE.txt"),)),
}

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

def read_bdf(path: Path, native_px: int | None = None) -> tuple[int, int, int, dict[int, Glyph]]:
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
    if native_px is not None:
        px = native_px  # the design size; several BDFs give only a line height, or nothing
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


# ---- the CJK library: embedded bitmap strikes and on-grid outlines ---------------------------

def _keep(cp: int) -> bool:
    return 0x20 <= cp < 0x110000 and not (0x7F <= cp < 0xA0) and not (0xD800 <= cp < 0xE000)


def read_strike(path: Path, px: int) -> tuple[int, int, int, dict[int, Glyph]]:
    """Glyphs from the bitmap strike a TrueType file embeds at [px] (EBLC/EBDT formats 5 and 7)."""
    from fontTools.ttLib import TTFont

    font = TTFont(str(path))
    cmap = font.getBestCmap()
    strike_no = next((i for i, s in enumerate(font["EBLC"].strikes) if s.bitmapSizeTable.ppemY == px), None)
    if strike_no is None:
        raise SystemExit(f"{path.name}: no embedded bitmaps at {px} px")
    strike = font["EBLC"].strikes[strike_no]
    line = strike.bitmapSizeTable.hori
    data = font["EBDT"].strikeData[strike_no]
    shared = {}  # glyph name -> the metrics its index subtable gives every glyph (format 5)
    for sub in strike.indexSubTables:
        for name in sub.names:
            shared[name] = getattr(sub, "metrics", None)
    upm, hmtx = font["head"].unitsPerEm, font["hmtx"]
    glyphs: dict[int, Glyph] = {}
    cache: dict[str, Glyph] = {}
    for cp, name in cmap.items():
        if not _keep(cp):
            continue
        if name not in cache:
            bitmap = data.get(name)
            if bitmap is None:  # no picture (a space): the outline font's advance, no ink
                cache[name] = Glyph(round(hmtx[name][0] * px / upm), 0, 0, 0, 0, [])
            else:
                bitmap.ensureDecompiled()
                m = getattr(bitmap, "metrics", None) or shared[name]
                rows = []
                for y in range(m.height):
                    packed = bitmap.getRow(y, bitDepth=1, metrics=m)
                    rows.append(int.from_bytes(packed, "big") >> (len(packed) * 8 - m.width))
                adv = m.horiAdvance if hasattr(m, "horiAdvance") else m.Advance
                bx = m.horiBearingX if hasattr(m, "horiBearingX") else m.BearingX
                by = m.horiBearingY if hasattr(m, "horiBearingY") else m.BearingY
                cache[name] = Glyph(adv, bx, by, m.width, m.height, rows).trimmed()
        glyphs[cp] = cache[name]
    return px, line.ascender, -line.descender, glyphs


def read_outline(path: Path, px: int) -> tuple[int, int, int, dict[int, Glyph]]:
    """Glyphs from TrueType outlines drawn on the pixel grid: nonzero-winding coverage sampled at
    pixel centers. Every edge must be straight; a stray unit off the grid cannot move a sample."""
    from fontTools.pens.recordingPen import DecomposingRecordingPen
    from fontTools.ttLib import TTFont

    font = TTFont(str(path))
    upp = font["head"].unitsPerEm / px  # font units per pixel
    if upp != int(upp):
        raise SystemExit(f"{path.name}: {font['head'].unitsPerEm} units per em is not a whole number of units per pixel")
    upp = int(upp)
    cmap, glyph_set, hmtx, hhea = font.getBestCmap(), font.getGlyphSet(), font["hmtx"], font["hhea"]

    off_grid: list[str] = []

    def snap(units: float, what: str) -> int:
        v = round(units / upp)
        if abs(units - v * upp) * 4 > upp:
            raise SystemExit(f"{path.name}: {what} = {units} units is not on the {upp}-unit pixel grid")
        return v

    def draw(name: str) -> Glyph:
        pen = DecomposingRecordingPen(glyph_set)
        glyph_set[name].draw(pen)
        edges, cur, start = [], None, None  # (x0, y0, x1, y1) for every non-horizontal edge
        for op, args in pen.value:
            if op == "moveTo":
                cur = start = args[0]
                continue
            if op == "lineTo":
                nxt = args[0]
            elif op in ("closePath", "endPath"):
                nxt = start
            else:
                raise SystemExit(f"{path.name}: glyph {name} has a curve ({op})")
            if cur is not None and nxt is not None and cur[1] != nxt[1]:
                edges.append((cur[0], cur[1], nxt[0], nxt[1]))
            cur = nxt
        adv = snap(hmtx[name][0], f"{name}.advance")
        if not edges:
            return Glyph(adv, 0, 0, 0, 0, [])
        xs = [e[0] for e in edges] + [e[2] for e in edges]
        ys = [e[1] for e in edges] + [e[3] for e in edges]
        # A few glyphs in some fonts sit off the grid: they are sampled at pixel centers like the
        # rest, inside the whole-pixel box that holds them, and counted for the build log.
        if any(abs(v - round(v / upp) * upp) > 2 for v in xs + ys):
            off_grid.append(name)
        x0, x1 = math.floor(min(xs) / upp), math.ceil(max(xs) / upp)
        y0, y1 = math.floor(min(ys) / upp), math.ceil(max(ys) / upp)
        w, h = x1 - x0, y1 - y0
        rows = []
        for py in range(h):  # top row first
            yc2 = (y1 - py) * upp * 2 - upp  # twice the sample's y: stays an integer for odd upp
            crossings = []
            for ax, ay, bx, by in edges:
                lo, hi = min(ay, by) * 2, max(ay, by) * 2
                if lo < yc2 < hi:
                    # twice the x where the edge crosses the sample row, as an exact fraction
                    crossings.append(((ax * 2 * (by - ay) + (bx - ax) * (yc2 - ay * 2)) / (by - ay), 1 if by > ay else -1))
            crossings.sort()
            row, wind, k = 0, 0, 0
            for pxl in range(w):
                xc2 = (x0 + pxl) * upp * 2 + upp
                while k < len(crossings) and crossings[k][0] < xc2:
                    wind += crossings[k][1]
                    k += 1
                row = (row << 1) | (1 if wind != 0 else 0)
            rows.append(row)
        return Glyph(adv, x0, y1, w, h, rows).trimmed()

    glyphs: dict[int, Glyph] = {}
    cache: dict[str, Glyph] = {}
    for cp, name in cmap.items():
        if not _keep(cp):
            continue
        if name not in cache:
            cache[name] = draw(name)
        glyphs[cp] = cache[name]
    if off_grid:
        print(f"  ({path.name}: {len(off_grid)} of {len(cache)} glyphs are off the pixel grid and were sampled)")
    return px, round(hhea.ascent / upp), round(-hhea.descent / upp), glyphs


CJK_READERS = {"bdf": read_bdf, "strike": read_strike, "outline": read_outline}


def _scripts(glyphs: dict[int, Glyph]) -> list[str]:
    scripts = []
    if all(cp in glyphs for cp in range(0x41, 0x5B)) and all(cp in glyphs for cp in range(0x61, 0x7B)):
        scripts.append("latin")
    if sum(1 for cp in glyphs if 0x400 <= cp <= 0x4FF) >= 60:
        scripts.append("cyrillic")
    scripts.append("cjk")
    return scripts


def convert_cjk(root: Path, out: Path) -> list[dict]:
    entries = []
    written: dict[str, tuple[str, int, list[str]]] = {}  # source path -> (file, px, scripts)
    for fid, name, px, lang, group, reader, src in CJK_FONTS:
        if isinstance(src, str):
            if src not in written:
                path = root / src
                if not path.exists():
                    raise SystemExit(f"missing {path}")
                _, ascent, descent, glyphs = CJK_READERS[reader](path, px)
                glyphs.pop(65534, None)
                file = f"cjk_{fid.replace('.', '_')}.mkf"
                size = write_mkf(out / file, px, ascent, descent, 0, glyphs, {}, delta=False)
                written[src] = (file, px, _scripts(glyphs))
                print(f"  {file:42s} {px:3d} px  {len(glyphs):5d} glyphs  {'':>16s}  {size:8d} bytes")
                missing = [c for c in name if c != " " and ord(c) not in glyphs]
                if missing:
                    raise SystemExit(f"{fid}: the font cannot draw its own name ({missing})")
            file, _, scripts = written[src]
            entry = {"id": f"cjk.{fid}", "name": name, "px": px, "scripts": scripts}
            if lang is not None:
                entry["lang"] = lang
            entry.update({"files": [file], "source": group})
            entries.append(entry)
            continue
        # Language forms: one base layer (the glyph most forms agree on) plus a delta per form.
        forms, metrics = {}, None
        for form_lang, _, form_src in src:
            path = root / form_src
            if not path.exists():
                raise SystemExit(f"missing {path}")
            _, ascent, descent, glyphs = CJK_READERS[reader](path, px)
            glyphs.pop(65534, None)
            if metrics is None:
                metrics = (ascent, descent)
            elif metrics != (ascent, descent):
                raise SystemExit(f"{path.name}: metrics differ between language forms")
            forms[form_lang] = glyphs
        ascent, descent = metrics
        base: dict[int, Glyph] = {}
        for cp in sorted(set().union(*forms.values())):
            votes, first = Counter(), {}
            for form_lang, _, _ in src:
                g = forms[form_lang].get(cp)
                if g is not None:
                    votes[g.key()] += 1
                    first.setdefault(g.key(), g)
            best = max(votes.items(), key=lambda kv: (kv[1], -list(first).index(kv[0])))[0]
            base[cp] = first[best]
        stem = f"cjk_{fid.replace('.', '_')}"
        base_file = f"{stem}_base.mkf"
        size = write_mkf(out / base_file, px, ascent, descent, 0, base, {}, delta=False)
        print(f"  {base_file:42s} {px:3d} px  {len(base):5d} glyphs  {'':>16s}  {size:8d} bytes")
        for form_lang, label, _ in src:
            delta = {cp: g for cp, g in forms[form_lang].items() if base[cp].key() != g.key()}
            file = f"{stem}_{form_lang.lower().replace('-', '_')}.mkf"
            dsize = write_mkf(out / file, px, ascent, descent, 0, delta, {}, delta=True)
            print(f"  {file:42s} {px:3d} px  {len(delta):5d} glyphs  {'(delta layer)':>16s}  {dsize:8d} bytes")
            entries.append({
                "id": f"cjk.{fid}.{form_lang}",
                "name": f"{name} \u00b7 {label}",
                "px": px,
                "scripts": _scripts(forms[form_lang]),
                "lang": form_lang,
                "files": [file, base_file],
                "source": group,
            })
    return entries


def write_cjk_licenses(root: Path, out: Path) -> None:
    lic = out / "licenses"
    lic.mkdir(exist_ok=True)
    for file, (heading, note, texts) in CJK_LICENSES.items():
        parts = [f"{heading}\n\n{note}"]
        for title, rel in texts:
            raw = (root / rel).read_bytes()
            text = raw.decode("utf-8-sig", errors="replace").replace("\r\n", "\n").strip() + "\n"
            parts.append(f"\n==== {title} ====\n\n{text}")
        (lic / file).write_text("".join(parts), encoding="utf-8", newline="\n")


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
    ap.add_argument("--cjk", type=Path, help="the CJK pixel font library (the folder holding ja/, zh/, ko/)")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "app" / "assets" / "pixel_fonts")
    args = ap.parse_args()
    if not args.vexed and not args.fusion and not args.cjk:
        ap.error("give --vexed, --fusion and/or --cjk")
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
    if args.cjk:
        print("CJK library:")
        for stale in [k for k, e in fonts.items() if e["source"] in CJK_CREDITS]:
            del fonts[stale]
        for stale in args.out.glob("cjk_*.mkf"):
            stale.unlink()
        for e in convert_cjk(args.cjk, args.out):
            fonts[e["id"]] = e
        write_cjk_licenses(args.cjk, args.out)
    write_licenses(args.fusion, args.out)
    ordered = sorted(fonts.values(), key=lambda e: (e["px"], e["source"] != "vexed", e["name"]))
    manifest = {
        "version": 1,
        "credits": {"vexed": VEXED_CREDIT, "fusion": FUSION_CREDIT, **CJK_CREDITS},
        "fonts": ordered,
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    total = sum(p.stat().st_size for p in args.out.glob("*.mkf"))
    print(f"{len(ordered)} fonts, {total} bytes of glyph data in {args.out}")


if __name__ == "__main__":
    sys.exit(main())
