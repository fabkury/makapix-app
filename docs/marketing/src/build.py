#!/usr/bin/env python3
"""Compose and render the marketing assets.

Builds one HTML page per (slide x format), renders each with headless Chrome at
exact pixel dimensions, and verifies the output with Pillow. Run from the repo
root:

    python docs/marketing/src/build.py [--lang xx ...] [--all-formats] [slide ...]

`--lang` picks languages (default: all in src/copy/). English renders to out/<format>/ as
before; every other language to out/<lang>/<format>/, store formats only (play, appstore,
ipad, and the Play feature graphic) unless --all-formats. All text comes from
src/copy/<lang>.json; the phone crops come from shots/<lang>/ where a language has its own
(the timeline row and the selection canvas carry no text and stay English's). Japanese and
Chinese set their text in Noto Sans JP / SC: subsets of the slide text are committed in
src/fonts/; the full fonts live in the git-ignored src/fonts/cache/ (see README) and are
only needed when the copy changes.

Slides: hero replay animation paint color select palette club files.
Outputs land in docs/marketing/out/<format>/. Play takes 01..08 (its listing
caps at 8 screenshots); the App Store additionally takes 09_files.

2026-08-31 redesign: denser three-zone layouts (primary demo, secondary proof
panel, chip ticker), community art from the public recommended feed with
on-slide @handle credits, and new slides for replay/timelapse and the brush
stack. The Play feature graphic is rebuilt too (hero slide, banner format).
"""

import html as htmllib
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

from PIL import Image

ROOT = Path.cwd()
SRC = Path("docs/marketing/src")
ART = Path("docs/marketing/art")
CLUB = ART / "club"
SHOTS = Path("docs/marketing/shots")
CROPS = ART / "crops"
COPY = SRC / "copy"
FONTS = SRC / "fonts"
LANGS = ["en", "es", "pt", "fr", "de", "ru", "ja", "zh"]
HTML_LANG = {"pt": "pt-BR", "zh": "zh-Hans"}
CJK = {"ja": ("NotoSansJP", "Noto Sans JP"), "zh": ("NotoSansSC", "Noto Sans SC")}
STORE_FORMATS = {"play", "appstore", "ipad"}
BUILD = SRC / "_build"
OUT = Path("docs/marketing/out")
CHROME = Path("C:/Program Files/Google/Chrome/Application/chrome.exe")

# name -> (width, height, orientation)
FORMATS = {
    "play": (1080, 1920, "portrait"),
    "appstore": (1320, 2868, "portrait"),
    "ipad": (2064, 2752, "square"),  # 13" iPad Pro portrait; square layouts + extra height
    "social": (1200, 630, "landscape"),
    "square": (1080, 1080, "square"),
}
BANNER = (1024, 500)  # Play feature graphic, hero slide only

CREDITS = json.loads((CLUB / "credits.json").read_text(encoding="utf-8"))


# ---------------------------------------------------------------- crop pre-pass

def crops_lang(lang):
    """The crops that carry text, from shots/<lang>/, into art/crops/<lang>/ (git-ignored for
    every language but English, whose crops stay in art/crops/ as before)."""
    src_dir = SHOTS / lang
    out_dir = CROPS if lang == "en" else CROPS / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    app_box = (0, 130, 1344, 2870)
    row_box = (0, 2098, 1344, 2245)
    for src, box, out in [
        ("hero_senna.png", app_box, "hero_senna_app.png"),
        ("patterns_page.png", app_box, "patterns_page_app.png"),
        ("row1_aa.png", row_box, "row1_aa.png"),
        ("row1_pattern.png", row_box, "row1_pattern.png"),
        ("select_union.png", (0, 2110, 1344, 2265), "select_row.png"),
        # stored already cropped above a row we could not vouch for (README)
        ("club_profile.png", (0, 130, 1344, 2040), "club_profile_app.png"),
    ]:
        if (src_dir / src).exists():
            Image.open(src_dir / src).crop(box).save(out_dir / out)


def crops():
    CROPS.mkdir(parents=True, exist_ok=True)

    def crop(src, box, out, scale=None):
        if not (SHOTS / src).exists():
            return
        im = Image.open(SHOTS / src).crop(box)
        if scale:
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        im.save(CROPS / out)

    app_box = (0, 130, 1344, 2870)  # app content minus status/gesture bars
    for shot in ["select_union", "palette_page", "editor_hero", "frames_timeline",
                 "hero_senna", "replay_viewer", "my_drawings"]:
        crop(f"{shot}.png", app_box, f"{shot}_app.png")
    # the fresh Recommended-feed shot cuts ABOVE its fourth row: that row held a
    # fan-art piece, and the IP exclusion applies to feed shots too
    crop("club_feed_new.png", (0, 130, 1344, 2040), "club_feed_new_app.png")
    crop("levels_tool.png", (0, 2098, 1344, 2245), "levels_row.png")
    crop("select_union.png", (0, 2110, 1344, 2265), "select_row.png")
    crop("select_union.png", (0, 340, 1344, 1500), "select_canvas.png")
    crop("palette_page.png", (0, 130, 1344, 1620), "palette_top.png")
    crop("frames_timeline.png", (0, 170, 1344, 420), "timeline_row.png")
    # fresh-capture crops (present only after the device pass)
    crop("timeline_cozy.png", (0, 170, 1344, 420), "timeline_cozy_row.png")
    crop("row1_aa.png", (0, 2098, 1344, 2245), "row1_aa.png")
    crop("row1_airbrush.png", (0, 2098, 1344, 2245), "row1_airbrush.png")
    crop("row1_gradient.png", (0, 2098, 1344, 2245), "row1_gradient.png")
    # the Patterns pass (2026-09-04): the page as a phone panel, the Pencil's row-1 strip with
    # the Pattern swatch On at its end
    crop("patterns_page.png", app_box, "patterns_page_app.png")
    crop("row1_pattern.png", (0, 2098, 1344, 2245), "row1_pattern.png")
    # zoomed insets for the cleanEdge comparison (the key's ring bow, 2x)
    for n in ["rot_orig", "rot_nearest", "rot_cleanedge"]:
        im = Image.open(ART / f"{n}.png").crop((104, 40, 296, 232))
        im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        im.save(CROPS / f"{n}_zoom.png")


# ---------------------------------------------------------------- copy

LANG = "en"
_COPY = {}


def set_lang(lang):
    global LANG, _COPY
    LANG = lang
    en = json.loads((COPY / "en.json").read_text(encoding="utf-8"))
    own = json.loads((COPY / f"{lang}.json").read_text(encoding="utf-8"))
    missing = sorted(k for k in en if not k.startswith("_") and k not in own)
    if missing:
        raise SystemExit(f"{lang}.json lacks {missing}")
    _COPY = own
    global _HAS_ACC
    _HAS_ACC = any('data-m=' in json.dumps(T(k), ensure_ascii=False) for k in own
                   if not k.startswith("_"))


_HAS_ACC = False


# Press Start 2P draws an accented capital (Ó, Ü, Ё, Й...) as a shrunken letter under its mark, so
# headlines read as lowercase ("CóDIGO"). Pixel-font text gets the full-size capital instead, with
# the font's own spacing mark lifted one font pixel above it (the .acc rule in page()). The lift is
# in em: capitals span 125..1000 font units, so a mark's bottom goes to 1125.
_MARK = {"́": ("´", 0.375), "̀": ("`", 0.375), "̂": ("^", 0.375),
         "̃": ("~", 0.75), "̈": ("¨", 0.25), "̊": ("˚", 0.5),
         "̆": ("˘", 0.375)}


def _lift_accents(s):
    def one(m):
        base, *marks = unicodedata.normalize("NFD", m.group())
        if len(marks) != 1 or marks[0] not in _MARK:
            return m.group()
        glyph, dy = _MARK[marks[0]]
        return f'<span class="acc" data-m="{glyph}" style="--dy:-{dy}em">{base}</span>'
    return re.sub(r"[^\W\d_a-z]", lambda m: one(m) if m.group().isupper() and m.group() != unicodedata.normalize("NFD", m.group()) else m.group(), s)


def T(key):
    v = _COPY[key]
    if key.endswith(".sub"):
        return v
    if isinstance(v, str):
        return _lift_accents(v)
    if isinstance(v, list):
        return [_lift_accents(x) for x in v]
    return {k: _lift_accents(x) for k, x in v.items()}


def slide_text(lang):
    """Every character a language's slides draw (for the CJK font subsets)."""
    own = json.loads((COPY / f"{lang}.json").read_text(encoding="utf-8"))
    parts = []
    for k, v in own.items():
        if k.startswith("_"):
            continue
        vals = v if isinstance(v, list) else list(v.values()) if isinstance(v, dict) else [v]
        parts += [htmllib.unescape(re.sub(r"<[^>]+>", "", x)) for x in vals]
    return "".join(parts) + "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ.,:/+-&×°@"


def cjk_font(lang):
    """The committed subset of the language's CJK font, regenerated from the full font in the
    cache when it exists; checked to cover every character of the copy."""
    base, family = CJK[lang]
    subset = FONTS / f"{base}-slides.woff2"
    full = FONTS / "cache" / f"{base}.ttf"
    text = slide_text(lang)
    if full.exists():
        from fontTools import subset as ftsubset
        opts = ftsubset.Options()
        opts.flavor = "woff2"
        opts.layout_features = ["*"]
        font = ftsubset.load_font(str(full), opts)
        sub = ftsubset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        ftsubset.save_font(font, str(subset), opts)
    from fontTools.ttLib import TTFont
    cmap = TTFont(str(subset)).getBestCmap()
    gaps = sorted({c for c in text if not c.isspace() and ord(c) not in cmap
                   and ord(c) not in PS2P_CMAP})
    if gaps:
        raise SystemExit(f"{subset} lacks {''.join(gaps)}: put the full font in "
                         f"{FONTS / 'cache'} (README) and rebuild")
    return subset.name, family


def _ps2p_cmap():
    from fontTools.ttLib import TTFont
    return TTFont(str(FONTS / "PressStart2P-Regular.ttf")).getBestCmap()


PS2P_CMAP = _ps2p_cmap()


# ---------------------------------------------------------------- HTML pieces

CSS = """
@font-face {
  font-family: 'PS2P';
  src: url('../fonts/PressStart2P-Regular.ttf');
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 100%; height: 100%; overflow: hidden; }
body {
  background: #0E1116;
  color: #F2F6FA;
  font-family: 'Segoe UI', Roboto, sans-serif;
  display: flex;
  flex-direction: column;
  padding: calc(var(--u) * 5) calc(var(--u) * 6) calc(var(--u) * 4);
}
body.landscape { flex-direction: row; align-items: center; gap: calc(var(--u) * 4); }
.landscape h1 { font-size: calc(var(--u) * 3.9); }
.head { flex: none; }
.landscape .head { flex: 0 0 44%; }
.kicker {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.5);
  color: #4080C0; letter-spacing: calc(var(--u) * 0.2);
  margin-bottom: calc(var(--u) * 2.2);
}
h1 {
  font-family: 'PS2P'; font-weight: 400;
  font-size: calc(var(--u) * 4.4); line-height: 1.42;
  margin-bottom: calc(var(--u) * 2.0);
}
h1 .a { color: #4080C0; }
/* a full-size capital with its accent lifted above it (_lift_accents); line-height normal makes
   the box the content area, so the mark shares the letter's baseline */
.acc { position: relative; }
.acc::after {
  content: attr(data-m); position: absolute; left: 0; top: 0; line-height: normal;
  transform: translateY(var(--dy));
}
.sub {
  font-size: calc(var(--u) * 2.6); line-height: 1.42; color: #AEBCCC;
  max-width: 36em;
}
.visual {
  flex: 1 1 auto; min-height: 0;
  display: flex; flex-direction: column;
  align-items: center; justify-content: space-evenly;
  gap: calc(var(--u) * 2.2);
  padding-top: calc(var(--u) * 1.5);
}
.footer {
  flex: none; display: flex; align-items: center; gap: calc(var(--u) * 1.6);
  margin-top: calc(var(--u) * 2.4);
}
.landscape .footer { position: absolute; left: calc(var(--u) * 6); bottom: calc(var(--u) * 4); }
.footer img { width: calc(var(--u) * 5); height: calc(var(--u) * 5); border-radius: 22%; }
.footer span { font-family: 'PS2P'; font-size: calc(var(--u) * 1.4); color: #5A6A7E; }

.phone {
  background: #1A202A; border-radius: calc(var(--u) * 4.5);
  padding: calc(var(--u) * 1.1);
  box-shadow: 0 calc(var(--u)*2) calc(var(--u)*8) #00000090, 0 0 0 2px #2A3442;
}
.phone img { display: block; width: 100%; border-radius: calc(var(--u) * 3.6); }
.canvascard {
  border-radius: calc(var(--u) * 1.6); border: 2px solid #2A3442; display: block;
}
.uistrip {
  border-radius: calc(var(--u) * 1.2); border: 2px solid #232B38; display: block;
  width: 92%;
}

.pix { image-rendering: pixelated; }
.caption {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.3); line-height: 1.6;
  color: #7A8AA0; text-align: center; margin-top: calc(var(--u) * 1);
}
.row { display: flex; gap: calc(var(--u) * 2.2); align-items: center; justify-content: center; }
.checker {
  background:
    repeating-conic-gradient(#232A34 0% 25%, #171C24 0% 50%);
  background-size: calc(var(--u) * 3) calc(var(--u) * 3);
  border-radius: calc(var(--u) * 1.5);
}
.tag {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.5); color: #F2F6FA;
  background: #1A2230; border: 2px solid #2A3A50;
  padding: calc(var(--u)*1) calc(var(--u)*1.5); border-radius: calc(var(--u)*1);
}

/* chip ticker: the density layer */
.chips {
  display: flex; flex-wrap: wrap; justify-content: center;
  gap: calc(var(--u) * 1.4);
}
.chip {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.35); color: #C8D6E6;
  background: #141B26; border: 2px solid #24486C;
  padding: calc(var(--u)*0.9) calc(var(--u)*1.4); border-radius: calc(var(--u)*2.2);
  white-space: nowrap;
}
.chip.hot { color: #FFFFFF; background: #1B3452; border-color: #4080C0; }

/* credited art tiles */
.tile { position: relative; }
.tile img {
  display: block; width: 100%; aspect-ratio: 1; object-fit: cover;
  border-radius: calc(var(--u)*1.2); border: 2px solid #232B38; background: #141A22;
}
.credit {
  position: absolute; left: 0; right: 0; bottom: 0;
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.05); color: #E8F0FA;
  background: linear-gradient(transparent, #000000C8);
  padding: calc(var(--u)*2.2) calc(var(--u)*0.9) calc(var(--u)*0.7);
  border-radius: 0 0 calc(var(--u)*1.2) calc(var(--u)*1.2);
  text-align: right; overflow: hidden; white-space: nowrap;
  font-size: min(calc(var(--u) * 1.05), var(--fit, 999px));
}

/* bordered demo panel with a top label */
.panel {
  background: #131820; border: 2px solid #232B38; border-radius: calc(var(--u)*1.6);
  padding: calc(var(--u)*1.6);
  display: flex; flex-direction: column; align-items: center;
  gap: calc(var(--u)*1.0);
}
.panel .plabel {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.2); color: #7A8AA0;
  line-height: 1.6; text-align: center;
}
.panel .plabel .a { color: #4080C0; }

/* replay filmstrip */
.filmstrip { display: flex; align-items: center; gap: calc(var(--u)*1.1); }
.filmstrip img {
  border-radius: calc(var(--u)*1); border: 2px solid #2A3442; display: block;
}
.filmstrip .arrow {
  font-family: 'PS2P'; color: #4080C0; font-size: calc(var(--u)*2.2);
}
.playbar {
  width: 92%; height: calc(var(--u)*1.1); border-radius: calc(var(--u)*0.6);
  background: #1A2230; position: relative;
}
.playbar .done { position: absolute; left: 0; top: 0; bottom: 0; width: 78%;
  background: #4080C0; border-radius: calc(var(--u)*0.6); }
.playbar .knob { position: absolute; left: 78%; top: 50%;
  width: calc(var(--u)*2.6); height: calc(var(--u)*2.6);
  transform: translate(-50%, -50%); border-radius: 50%;
  background: #E8F0FA; box-shadow: 0 0 calc(var(--u)*1.5) #4080C0; }

/* store screenshots are viewed as small thumbnails: larger supporting text there */
.portrait .kicker { font-size: calc(var(--u) * 2.0); }
.portrait .sub { font-size: calc(var(--u) * 3.2); }
.portrait .caption { font-size: calc(var(--u) * 1.9); }
.portrait .tag { font-size: calc(var(--u) * 2.0); }
.portrait .chip { font-size: calc(var(--u) * 1.8); }
.portrait .credit { font-size: min(calc(var(--u) * 1.5), var(--fit, 999px)); }
.portrait .plabel { font-size: calc(var(--u) * 1.7); }
.portrait .footer span { font-size: calc(var(--u) * 1.8); }
"""

LOGO = "../../../media/logo.png"  # relative to src/_build/


def page(fmt_name, w, h, orient, body_html, kicker, title, sub, footer=True):
    u = w / 100 if orient != "landscape" else h / 62
    foot = (f'<div class="footer"><img src="{LOGO}"><span>{T("footer")}</span></div>'
            if footer else "")
    cjk = ""
    if LANG in CJK:
        fname, family = cjk_font(LANG)
        # Press Start 2P draws the Latin letters and digits; the CJK face everything else, at
        # a size that matches the pixel font's visual weight
        cjk = f"""
@font-face {{ font-family: 'CJK'; src: url('../fonts/{fname}'); size-adjust: 118%; }}
.kicker, h1, .chip, .tag, .caption, .plabel, .credit, .footer span, .bignum, .strike, .oss {{
  font-family: 'PS2P', 'CJK'; font-weight: 700; font-synthesis: none; }}
body {{ font-family: 'Segoe UI', Roboto, 'CJK', sans-serif; }}
h1 {{ line-height: 1.32; }}"""
    if _HAS_ACC:
        # lifted accents rise up to half an em above a capital: room above the text in every
        # chip of the language (all of them, so a chip row keeps one height); mostly on top,
        # where the marks are, so the tight Patterns slide still fits
        cjk += """
.chip { padding-top: calc(var(--u)*0.9 + 0.22em); padding-bottom: calc(var(--u)*0.9 + 0.04em); }
.gap { display: inline-block; width: 0.35em; }"""
    else:
        cjk += "\n.gap { display: inline-block; width: 0.35em; }"
    return f"""<!doctype html><html lang="{HTML_LANG.get(LANG, LANG)}"><head><meta charset="utf-8"><style>
:root {{ --u: {u:.2f}px; }}
{CSS}{cjk}
</style></head><body class="{orient}">
<div class="head">
  <div class="kicker">{kicker}</div>
  <h1>{title}</h1>
  <div class="sub">{sub}</div>
</div>
<div class="visual">{body_html}</div>
{foot}
</body></html>"""


def art(rel):  # path from _build/ to art/
    return f"../../art/{rel}"


def chips(items):
    """`items` is a copy key (a list where a leading "+" marks a highlighted chip) or a list
    of (text, hot) pairs."""
    if isinstance(items, str):
        items = [(t[1:], True) if t.startswith("+") else (t, False) for t in T(items)]
    spans = "".join(
        f'<span class="chip{" hot" if hot else ""}">{t}</span>'
        for t, hot in items)
    return f'<div class="chips">{spans}</div>'


def tile(name, size_u, drawn_here=False):
    """A credited community-art tile. `name` is a key into credits.json."""
    c = CREDITS[name]
    handle = c["handle"]
    lines = ([T("drawn_here")] if drawn_here else []) + [f"@{handle}"]
    # one line each, never wrapped (a handle may contain spaces: "m o n s t e r"); a long
    # line shrinks the credit to the tile's width (Press Start 2P is one em per character)
    longest = max(len(htmllib.unescape(re.sub(r"<[^>]+>", "", t))) for t in lines)
    fit = (size_u - 2.4) / max(longest, 1)  # the credit's side padding is 0.9 units each
    text = "<br>".join(t.replace(" ", "&nbsp;") for t in lines)
    return (f'<div class="tile" style="width: calc(var(--u)*{size_u});">'
            f'<img class="pix" src="{art(f"club/{name}.png")}">'
            f'<div class="credit" style="--fit: calc(var(--u)*{fit:.3f});">{text}</div></div>')


def shot_crop(crop_name, fallback):
    """The language's own device crop when it has one, else English's, else the fallback.
    Returns a path under art/crops/ without the extension."""
    if LANG != "en" and (CROPS / LANG / f"{crop_name}.png").exists():
        return f"{LANG}/{crop_name}"
    return crop_name if (CROPS / f"{crop_name}.png").exists() else fallback


# ---------------------------------------------------------------- slides

def slide_hero(orient):
    phone_crop = shot_crop("hero_senna_app", "editor_hero_app")
    wall = "".join(tile(n, {"portrait": 17.8, "square": 11.2, "landscape": 12}[orient])
                   for n in ["daydream", "mr_tritium", "seaside_city", "cozy_blizzard"])
    tick = chips("hero.chips")
    if orient == "landscape":
        return f"""
        <div class="row">{tile('senna_fixed', 20, drawn_here=True)}
          <div style="display:flex; flex-direction:column; gap: calc(var(--u)*2);">
            <div class="row">{wall}</div>{tick}</div></div>"""
    ph = {"portrait": 40, "square": 27}[orient]
    feat = {"portrait": 38, "square": 24}[orient]
    return f"""
    <div class="row" style="align-items: stretch;">
      <div style="display:flex; flex-direction:column; justify-content:space-between;
                  gap: calc(var(--u)*2);">
        {tile('senna_fixed', feat, drawn_here=True)}
        <div style="display:grid; grid-template-columns: repeat(2, auto);
             gap: calc(var(--u)*1.6);">{wall}</div>
      </div>
      <div class="phone" style="width: calc(var(--u)*{ph});">
        <img src="{art(f'crops/{phone_crop}.png')}"></div>
    </div>
    {tick}"""


def slide_hero_wall_only(orient):  # small-format helper (unused placeholder)
    return slide_hero(orient)


def slide_replay(orient):
    size = {"portrait": 14.4, "square": 9.5, "landscape": 10}[orient]
    frames = f'<span class="arrow">&#9654;</span>'.join(
        f'<img class="pix" src="{art(f"replay_s{k}.png")}" '
        f'style="width: calc(var(--u)*{size});">' for k in range(1, 6))
    strip = (f'<div><div class="filmstrip">{frames}</div>'
             f'<div class="caption">{T("replay.strip_caption")}</div></div>')
    player_w = {"portrait": 46, "square": 24, "landscape": 24}[orient]
    player = f"""
    <div class="panel" style="width: calc(var(--u)*{player_w + 6});">
      <div style="position: relative; width: calc(var(--u)*{player_w});">
        <img class="pix" src="{art('replay_s5.png')}"
             style="display:block; width: 100%; border-radius: calc(var(--u)*1);">
        <div style="position:absolute; left:50%; top:50%; transform:translate(-50%,-50%);
             width: calc(var(--u)*7); height: calc(var(--u)*7); border-radius:50%;
             background:#0E1116CC; border: 2px solid #E8F0FA;
             display:flex; align-items:center; justify-content:center;">
          <span style="font-family:'PS2P'; color:#E8F0FA;
                font-size: calc(var(--u)*2.6); padding-left: calc(var(--u)*0.6);">&#9654;</span>
        </div>
      </div>
      <div class="playbar"><div class="done"></div><div class="knob"></div></div>
      <div class="plabel">{T("replay.player_label")}</div>
    </div>"""
    tick = chips("replay.chips")
    if orient == "landscape":
        return strip + tick
    # no phone panel (user decision 2026-10-02): the replayable drawing has no recording, and
    # the engine-rendered player carries the point in every language
    return strip + player + tick


def slide_animation(orient):
    cards = ""
    picks = [0, 2, 4, 6, 8, 10]
    n = len(picks)
    for i, k in enumerate(picks):
        d = i - (n - 1) / 2
        rot = d * 4.0
        ty = 0.55 * d * d
        cards += (f'<img class="pix card" src="{art(f"ball_{k:02d}.png")}" '
                  f'style="transform: rotate({rot:.1f}deg) '
                  f'translateY(calc(var(--u) * {ty:.2f}));">')
    size = {"portrait": 20, "square": 16, "landscape": 14}[orient]
    overlap = {"portrait": -2.3, "square": -1.9, "landscape": -1.6}[orient]
    extra = f"""
    <style>
    .fan {{ display:flex; justify-content:center; align-items:center;
           padding: 0 calc(var(--u)*3); }}
    .card {{
      width: calc(var(--u) * {size}); border-radius: calc(var(--u)*1.2);
      border: 2px solid #2A3442; background:#141A22;
      margin: 0 calc(var(--u) * {overlap});
      box-shadow: 0 calc(var(--u)*1.5) calc(var(--u)*5) #000000A0;
    }}
    </style>"""
    tl_crop = shot_crop("timeline_cozy_row", "timeline_row")
    tl = (f'<img class="pix uistrip" src="{art(f"crops/{tl_crop}.png")}">'
          f'<div class="caption">{T("animation.timeline_caption")}</div>')
    tick = chips("animation.chips")
    body = extra + f'<div class="fan">{cards}</div>'
    if orient != "landscape":
        body += f"<div>{tl}</div>"
    return body + tick


def slide_paint(orient):
    aa_w = {"portrait": 17, "square": 11, "landscape": 10}[orient]
    air_w = {"portrait": 24, "square": 15, "landscape": 14}[orient]
    p_aa = f"""
    <div class="panel"><div class="plabel">{T("paint.aa")}</div>
      <div class="row" style="gap: calc(var(--u)*1.2);">
        <img class="pix" src="{art('aa_off.png')}" style="width: calc(var(--u)*{aa_w});">
        <img class="pix" src="{art('aa_on.png')}" style="width: calc(var(--u)*{aa_w});">
      </div></div>"""
    p_air = f"""
    <div class="panel"><div class="plabel">{T("paint.airbrush")}</div>
      <div style="display:flex; flex-direction:column; gap: calc(var(--u)*0.8);">
        <img class="pix" src="{art('air_dots.png')}" style="width: calc(var(--u)*{air_w});">
        <img class="pix" src="{art('air_soft.png')}" style="width: calc(var(--u)*{air_w});">
        <img class="pix" src="{art('air_mist.png')}" style="width: calc(var(--u)*{air_w});">
      </div></div>"""
    p_grad = f"""
    <div class="panel"><div class="plabel">{T("paint.gradients")}</div>
      <img class="pix" src="{art('gradient8.png')}" style="width: calc(var(--u)*{air_w + 10});">
    </div>"""
    p_coat = f"""
    <div class="panel"><div class="plabel">{T("paint.coat")}</div>
      <div class="checker" style="padding: calc(var(--u)*0.8);">
      <img class="pix" src="{art('coat_one.png')}" style="width: calc(var(--u)*{aa_w}); display:block;">
      </div></div>"""
    tick = chips("paint.chips")
    if orient == "landscape":
        return f'<div class="row">{p_aa}{p_air}</div>' + tick
    row1 = shot_crop("row1_aa", "")
    strip = (f'<img class="uistrip" src="{art(f"crops/{row1}.png")}">'
             if row1 and orient == "portrait" else "")
    return (f'<div class="row" style="align-items:stretch;">{p_aa}{p_air}</div>'
            f'<div class="row" style="align-items:stretch;">{p_grad}{p_coat}</div>'
            + strip + tick)


def slide_patterns(orient):
    """Patterns (ADR 0025): a Bucket-shaded sphere, a Brush stroke through a crosshatch, the
    Gradient's ordered dither next to the smooth ramp, a strip of catalog tiles, and the real
    Patterns page in a phone frame."""
    sph_w = {"portrait": 14, "square": 9, "landscape": 11}[orient]
    stroke_w = {"portrait": 20, "square": 12, "landscape": 15}[orient]
    grad_w = {"portrait": 27, "square": 16, "landscape": 22}[orient]
    land = orient == "landscape"
    p_sphere = f"""
    <div class="panel"><div class="plabel">{T("patterns.bucket_short") if land else T("patterns.bucket")}</div>
      <img class="pix" src="{art('pat_sphere.png')}" style="width: calc(var(--u)*{sph_w});">
    </div>"""
    p_stroke = f"""
    <div class="panel"><div class="plabel">{T("patterns.brush_short") if land else T("patterns.brush")}</div>
      <img class="pix" src="{art('pat_stroke.png')}" style="width: calc(var(--u)*{stroke_w});">
    </div>"""
    ramps = "".join(
        f'<img class="pix" src="{art(n)}" style="width: calc(var(--u)*{grad_w}); display:block;">'
        for n in ["pat_grad_off.png", "pat_grad_b2.png", "pat_grad_b8.png"])
    p_grad = f"""
    <div class="panel"><div class="plabel">{T("patterns.gradient")}</div>
      <div style="display:flex; flex-direction:column; gap: calc(var(--u)*0.6);">{ramps}</div>
    </div>"""
    tiles_w = {"portrait": 62, "square": 40, "landscape": 40}[orient]
    p_tiles = f"""
    <div class="panel"><div class="plabel">{T("patterns.tiles")}</div>
      <img class="pix" src="{art('pat_tiles.png')}" style="width: calc(var(--u)*{tiles_w});">
    </div>"""
    tick = chips("patterns.chips")
    page_crop = shot_crop("patterns_page_app", "")
    if orient == "landscape":
        phone = (f'<div class="phone" style="width: calc(var(--u)*17);">'
                 f'<img src="{art(f"crops/{page_crop}.png")}"></div>' if page_crop else "")
        return f'<div class="row">{phone}{p_sphere}{p_stroke}</div>' + tick
    ph = {"portrait": 22, "square": 16}[orient]
    phone = (f'<div class="phone" style="width: calc(var(--u)*{ph});">'
             f'<img src="{art(f"crops/{page_crop}.png")}"></div>' if page_crop else "")
    row1 = shot_crop("row1_pattern", "")
    strip = (f'<img class="uistrip" src="{art(f"crops/{row1}.png")}">'
             if row1 and orient == "portrait" else "")
    return (f'<div class="row" style="align-items:stretch;">{phone}'
            f'<div style="display:flex; flex-direction:column; gap: calc(var(--u)*2.2); justify-content:space-between;">'
            f'{p_sphere}{p_stroke}</div></div>'
            f'<div class="row" style="align-items:stretch;">{p_grad}</div>'
            # the square canvas has no vertical room for the tile strip (the phone panel
            # shows the catalog anyway); portrait keeps it
            f'{p_tiles if orient == "portrait" else ""}{strip}{tick}')


def slide_color(orient):
    modes = ["multiply", "screen", "overlay", "difference", "addition", "exclusion"]
    if orient == "landscape":
        modes = modes[:4]
    msize = {"portrait": 15.5, "square": 12, "landscape": 10}[orient]
    cells = "".join(
        f'<div class="cell"><img class="pix" src="{art(f"blend_{m}.png")}" '
        f'style="width: calc(var(--u)*{msize});">'
        f'<div class="caption">{T("color.modes")[m]}</div></div>' for m in modes)
    grid = (f'<div style="display:grid; grid-template-columns: repeat(3, auto); '
            f'gap: calc(var(--u)*1.8);">{cells}</div>')
    gsize = {"portrait": 22, "square": 16, "landscape": 12}[orient]
    ghost = f"""
    <div><div class="checker" style="padding: calc(var(--u)*1.6);">
      <img class="pix" src="{art('ghost.png')}" style="width: calc(var(--u)*{gsize}); display:block;">
    </div><div class="caption">{T("color.alpha_caption")}</div></div>"""
    lsize = {"portrait": 15.5, "square": 12, "landscape": 10}[orient]
    levels = f"""
    <div class="panel"><div class="plabel">{T("color.levels")}</div>
      <div class="row" style="gap: calc(var(--u)*1.2);">
        <div><img class="pix" src="{art('levels_before.png')}"
             style="width:calc(var(--u)*{lsize}); border-radius:calc(var(--u)*1);">
             <div class="caption">{T("color.before")}</div></div>
        <div><img class="pix" src="{art('levels_after.png')}"
             style="width:calc(var(--u)*{lsize}); border-radius:calc(var(--u)*1);">
             <div class="caption">{T("color.after")}</div></div>
      </div></div>"""
    tick = chips("color.chips")
    if orient == "landscape":
        return f'<div class="row">{ghost}{grid}</div>' + tick
    return f'<div class="row">{ghost}{levels}</div>{grid}' + tick


def slide_select(orient):
    csize = {"portrait": 36, "square": 28, "landscape": 26}[orient]
    canvas = f"""
    <div>
      <img class="canvascard" src="{art('crops/select_canvas.png')}"
           style="width: calc(var(--u)*{csize});">
      <img class="uistrip" src="{art(f'crops/{shot_crop("select_row", "select_row")}.png')}"
           style="width: calc(var(--u)*{csize}); margin: calc(var(--u)*1.2) auto 0;">
    </div>"""
    zsize = {"portrait": 19, "square": 15, "landscape": 11}[orient]
    ce = f"""
    <div class="row">
      <div><img class="pix" src="{art('crops/rot_orig_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">{T("select.original")}</div></div>
      <div><img class="pix" src="{art('crops/rot_nearest_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">{T("select.nearest")}</div></div>
      <div><img class="pix" src="{art('crops/rot_cleanedge_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #4080C0;">
        <div class="caption" style="color:#4080C0;">{T("select.cleanedge")}</div></div>
    </div>
    <div class="caption">{T("select.zoom_caption")}</div>"""
    tick = chips("select.chips")
    if orient == "landscape":
        return f"<div>{ce}</div>" + tick
    return canvas + f"<div>{ce}</div>" + tick


def slide_free(orient):
    """Free, ad-free, open-source: three statement panels + the repo line."""
    pw = {"portrait": 27, "square": 19, "landscape": 14}[orient]
    tick = chips("free.chips")
    repo = f"""
    <div>
      <div class="tag" style="border-color:#4080C0; text-align:center;">
        github.com/fabkury/makapix-app</div>
      <div class="caption">{T("free.repo_caption")}</div>
    </div>"""
    # the price and the struck-out word are each language's own ("0 €", "WERBUNG"): sized to fit
    # the panel (Press Start 2P: one em per character; CJK characters count double width)
    def ems(t):  # rendered width in em: tags stripped, a .gap counts its 0.35 em
        t = htmllib.unescape(re.sub(r"<[^>]+>", "", t.replace('<span class="gap"></span>', "\0")))
        return sum(0.35 if c == "\0" else 1 if ord(c) < 0x2E80 else 1.1 for c in t)
    big = min(pw * 0.26, pw * 0.8 / ems(T("free.price")))
    strike = min(pw * 0.17, pw * 0.8 / ems(T("free.ads")))
    panels = f"""
    <style>
    .freepanel {{
      width: calc(var(--u)*{pw}); aspect-ratio: 1 / 1.05;
      justify-content: center; gap: calc(var(--u)*2.2);
    }}
    .bignum {{ font-family:'PS2P'; font-size: calc(var(--u)*{big:.2f}); color:#F2F6FA; }}
    .strike {{ position:relative; font-family:'PS2P';
              font-size: calc(var(--u)*{strike:.2f}); color:#7A8AA0; }}
    .strike::after {{ content:''; position:absolute; left:-10%; right:-10%; top:46%;
              height: calc(var(--u)*0.9); background:#E05050;
              transform: rotate(-12deg); border-radius: calc(var(--u)*0.5); }}
    .oss {{ font-family:'PS2P'; font-size: calc(var(--u)*{pw * 0.2:.1f}); color:#4080C0; }}
    </style>
    <div class="row" style="align-items: stretch;">
      <div class="panel freepanel"><span class="bignum">{T("free.price")}</span>
        <div class="plabel">{T("free.forever")}</div></div>
      <div class="panel freepanel"><span class="strike">{T("free.ads")}</span>
        <div class="plabel">{T("free.zero")}</div></div>
      <div class="panel freepanel"><span class="oss">&lt;/&gt;</span>
        <div class="plabel">{T("free.oss")}</div></div>
    </div>"""
    if orient == "landscape":
        return panels + tick
    return panels + repo + tick


def slide_club(orient):
    grid_names = ["brave_bear", "night_island", "chess3d",
                  "yellow_tang", "fairy_flower", "mr_tritium"]
    # portrait: the grid and the phone share one row inside the 88-unit content width
    tsize = {"portrait": 16, "square": 15, "landscape": 11}[orient]
    wall = "".join(tile(n, tsize) for n in grid_names)
    grid = (f'<div style="display:grid; grid-template-columns: repeat(3, auto); '
            f'gap: calc(var(--u)*1.8);">{wall}</div>')
    tick = chips("club.chips")
    if orient == "landscape":
        return grid + tick
    # an artist's profile, not the live feed (2026-10-02, README): the feed now carries game
    # names and art whose origin cannot be checked. The pre-redesign shots/club_feed.png is
    # NOT an acceptable fallback either (fan-art, a photo-import portrait).
    feed = shot_crop("club_profile_app", "")
    phone = ""
    if feed and orient == "portrait":
        phone = (f'<div class="phone" style="width: calc(var(--u)*34);">'
                 f'<img src="{art(f"crops/{feed}.png")}"></div>')
    if phone:
        return (f'<div class="row" style="align-items:center;">{grid}{phone}</div>'
                + tick)
    return grid + tick


def slide_files(orient):
    fin = ["GIF", "PNG", "APNG", "WEBP", "JPEG", "BMP"]
    fout = T("files.out")
    fl_in = "".join(f'<span class="tag">{t}</span>' for t in fin)
    fl_out = "".join(f'<span class="tag" style="border-color:#4080C0;">{t}</span>'
                     for t in fout)
    flow = f"""
    <div class="panel" style="width: 88%;">
      <div class="plabel">{T("files.import")}</div>
      <div class="row" style="flex-wrap:wrap; gap: calc(var(--u)*1.2);">{fl_in}</div>
      <div class="plabel" style="margin-top: calc(var(--u)*1.6);">{T("files.export")}</div>
      <div class="row" style="flex-wrap:wrap; gap: calc(var(--u)*1.2);">{fl_out}</div>
    </div>"""
    tick = chips("files.chips")
    # no gallery phone shot here: the user's My Drawings viewport carries
    # third-party-IP sprites, which the fan-art exclusion keeps out of marketing
    thumbs = "".join(tile(n, 17.8) for n in ["seaside_city", "cozy_blizzard",
                                             "yellow_tang", "brave_bear"])
    strip = (f'<div style="display:grid; grid-template-columns: repeat(4, auto); '
             f'gap: calc(var(--u)*1.6);">{thumbs}</div>')
    return flow + strip + tick


def banner_hero():
    """The Play feature graphic: brand banner, 1024x500."""
    strip = "".join(tile(n, 13) for n in
                    ["senna_fixed", "daydream", "mr_tritium", "seaside_city"])
    tick = chips("banner.chips")
    return f"""
    <div style="display:flex; flex-direction:column; gap: calc(var(--u)*2.4);
                align-items:center;">
      <div class="row" style="gap: calc(var(--u)*1.6);">{strip}</div>
      {tick}
    </div>"""


# name -> visual builder; the kicker, title, and subline come from the copy ("<name>.kicker" …)
SLIDES = {
    "hero": slide_hero,
    "replay": slide_replay,
    "animation": slide_animation,
    "paint": slide_paint,
    "patterns": slide_patterns,
    "color": slide_color,
    "select": slide_select,
    "free": slide_free,
    "club": slide_club,
    "files": slide_files,
}

ORDER = ["hero", "free", "replay", "animation", "paint", "patterns",
         "color", "club", "select", "files"]
PLAY_MAX = 8  # the Play listing caps at 8 screenshots; 09_select and 10_files are App Store only


# ---------------------------------------------------------------- render

# Measures the laid-out page and writes what overflows into the DOM, which --dump-dom reads:
# text running past the right edge, a visual taller than its box, or a heading wider than the
# page. A slide whose copy does not fit fails the build instead of shipping clipped.
FIT_JS = """<script>
window.addEventListener('load', () => document.fonts.ready.then(() => {
  const W = document.documentElement.clientWidth, H = document.documentElement.clientHeight;
  const bad = [];
  for (const el of document.querySelectorAll('h1, .sub, .kicker, .chip, .tag, .caption, .plabel, .credit, .bignum, .strike')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0) continue;
    if (r.right > W + 1 || r.left < -1 || r.bottom > H + 1) bad.push(el.className || el.tagName);
    if (el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflow === 'hidden') bad.push('clip:' + (el.className || el.tagName));
  }
  const v = document.querySelector('.visual');
  if (v && v.scrollHeight > v.clientHeight + 2) bad.push('visual-height+' + (v.scrollHeight - v.clientHeight) + 'px');
  const m = document.createElement('meta'); m.name = 'fit'; m.content = bad.join(' ') || 'ok';
  document.head.appendChild(m);
}));
</script>"""


def check_fit(html_path, w, h):
    cmd = [str(CHROME), "--headless", "--disable-gpu", "--disable-lcd-text", "--hide-scrollbars",
           f"--window-size={w},{h}", "--force-device-scale-factor=1",
           "--virtual-time-budget=4000", "--dump-dom", html_path.resolve().as_uri()]
    out = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=60).stdout
    m = re.search(r'<meta name="fit" content="([^"]*)"', out)
    return m.group(1) if m else "unmeasured"


def render(html_path, out_path, w, h):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(CHROME), "--headless", "--disable-gpu", "--disable-lcd-text", "--hide-scrollbars",
           f"--screenshot={out_path.resolve()}", f"--window-size={w},{h}",
           "--force-device-scale-factor=1", "--default-background-color=FF0E1116",
           html_path.resolve().as_uri()]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if not out_path.exists():
        sys.stderr.write(r.stderr[-2000:])
        raise SystemExit(f"chrome failed for {out_path}")
    im = Image.open(out_path)
    assert im.size == (w, h), f"{out_path}: got {im.size}, want {(w, h)}"
    # both stores reject PNGs with an alpha channel; flatten to 24-bit
    if im.mode != "RGB":
        im.convert("RGB").save(out_path)


def build(picks, langs, all_formats=False):
    crops()
    BUILD.mkdir(parents=True, exist_ok=True)
    misfits, warnings = [], []
    for lang in langs:
        set_lang(lang)
        crops_lang(lang)
        out_root = OUT if lang == "en" else OUT / lang
        for name in picks:
            builder = SLIDES[name]
            idx = ORDER.index(name) + 1
            for fmt, (w, h, orient) in FORMATS.items():
                if fmt == "play" and idx > PLAY_MAX:
                    continue
                if lang != "en" and not all_formats and fmt not in STORE_FORMATS:
                    continue
                body = builder(orient)
                html = page(fmt, w, h, orient, body, T(f"{name}.kicker"), T(f"{name}.title"),
                            T(f"{name}.sub"))
                hp = BUILD / f"{lang}_{name}_{fmt}.html"
                hp.write_text(html.replace("</body>", FIT_JS + "</body>"), encoding="utf-8")
                fit = check_fit(hp, w, h)
                if fit != "ok":
                    # store formats must fit; the social / square formats only warn (several
                    # English ones never did, 2026-10-02)
                    (misfits if fmt in STORE_FORMATS else warnings).append(
                        f"{lang} {name} {fmt}: {fit}")
                hp.write_text(html, encoding="utf-8")
                render(hp, out_root / fmt / f"{idx:02d}_{name}.png", w, h)
            if name == "hero":
                w, h = BANNER
                body = banner_hero()
                html = page("banner", w, h, "landscape", body, T("banner.kicker"),
                            T("banner.title"), T("banner.sub"))
                hp = BUILD / f"{lang}_hero_banner.html"
                hp.write_text(html.replace("</body>", FIT_JS + "</body>"), encoding="utf-8")
                fit = check_fit(hp, w, h)
                if fit != "ok":
                    misfits.append(f"{lang} banner: {fit}")
                hp.write_text(html, encoding="utf-8")
                render(hp, out_root / "play_feature_graphic.png", w, h)
            print(f"ok {lang} {name}", flush=True)
    if warnings:
        print("does not fit (social / square, not enforced):")
        print("  " + "\n  ".join(warnings))
    if misfits:
        print("DOES NOT FIT:"); print("  " + "\n  ".join(misfits))
        raise SystemExit(1)


if __name__ == "__main__":
    args = sys.argv[1:]
    langs, picks, all_formats = [], [], False
    while args:
        a = args.pop(0)
        if a == "--lang":
            langs.append(args.pop(0))
        elif a == "--all-formats":
            all_formats = True
        else:
            picks.append(a)
    build(picks or ORDER, langs or [l for l in LANGS if (COPY / f"{l}.json").exists()],
          all_formats)
