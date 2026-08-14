#!/usr/bin/env python3
"""Compose and render the marketing assets.

Builds one HTML page per (slide x format), renders each with headless Chrome at
exact pixel dimensions, and verifies the output with Pillow. Run from the repo
root:

    python docs/marketing/src/build.py [slide ...]   (default: all slides)

Slides: frames rgba blend select levels ruler palette cleanedge hero.
Outputs land in docs/marketing/out/<format>/.
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path.cwd()
SRC = Path("docs/marketing/src")
ART = Path("docs/marketing/art")
SHOTS = Path("docs/marketing/shots")
CROPS = ART / "crops"
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


# ---------------------------------------------------------------- crop pre-pass

def crops():
    CROPS.mkdir(parents=True, exist_ok=True)

    def crop(src, box, out, scale=None):
        dst = CROPS / out
        im = Image.open(SHOTS / src).crop(box)
        if scale:
            im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        im.save(dst)

    app_box = (0, 130, 1344, 2870)  # app content minus status/gesture bars
    for shot in ["ruler_tool", "select_union", "levels_tool", "palette_page",
                 "frames_timeline", "editor_hero"]:
        if (SHOTS / f"{shot}.png").exists():
            crop(f"{shot}.png", app_box, f"{shot}_app.png")
    crop("levels_tool.png", (0, 2098, 1344, 2245), "levels_row.png")
    crop("select_union.png", (0, 2110, 1344, 2265), "select_row.png")
    crop("select_union.png", (0, 340, 1344, 1500), "select_canvas.png")
    crop("ruler_tool.png", (0, 500, 1344, 1900), "ruler_canvas.png")
    crop("ruler_tool.png", (0, 2098, 1344, 2245), "ruler_row.png")
    crop("palette_page.png", (0, 130, 1344, 1620), "palette_top.png")
    crop("frames_timeline.png", (0, 170, 1344, 420), "timeline_row.png")
    crop("blend_picker.png", (0, 1330, 1344, 2880), "blend_sheet.png")
    # zoomed insets for the cleanEdge comparison (the key's ring bow, 2x)
    for n in ["rot_orig", "rot_nearest", "rot_cleanedge"]:
        im = Image.open(ART / f"{n}.png").crop((104, 40, 296, 232))
        im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        im.save(CROPS / f"{n}_zoom.png")


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
  padding: calc(var(--u) * 6);
}
body.landscape { flex-direction: row; align-items: center; gap: calc(var(--u) * 4); }
.landscape h1 { font-size: calc(var(--u) * 3.9); }
.head { flex: none; }
.landscape .head { flex: 0 0 44%; }
.kicker {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.5);
  color: #4080C0; letter-spacing: calc(var(--u) * 0.2);
  margin-bottom: calc(var(--u) * 2.4);
}
h1 {
  font-family: 'PS2P'; font-weight: 400;
  font-size: calc(var(--u) * 4.6); line-height: 1.45;
  margin-bottom: calc(var(--u) * 2.2);
}
h1 .a { color: #4080C0; }
.sub {
  font-size: calc(var(--u) * 2.6); line-height: 1.45; color: #AEBCCC;
  max-width: 34em;
}
.visual {
  flex: 1 1 auto; min-height: 0;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  gap: calc(var(--u) * 3);
}
.footer {
  flex: none; display: flex; align-items: center; gap: calc(var(--u) * 1.6);
  margin-top: calc(var(--u) * 3);
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
.portrait .phone, .square .phone { width: calc(var(--u) * 62); }
.landscape .phone { width: auto; }
.landscape .phone img { width: auto; height: calc(var(--u) * 44); }
.canvascard {
  border-radius: calc(var(--u) * 1.6); border: 2px solid #2A3442; display: block;
}
.uistrip {
  border-radius: calc(var(--u) * 1.2); border: 2px solid #232B38; display: block;
}

.pix { image-rendering: pixelated; }
.caption {
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.3);
  color: #7A8AA0; text-align: center; margin-top: calc(var(--u) * 1);
}
.row { display: flex; gap: calc(var(--u) * 2.5); align-items: center; justify-content: center; }
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

/* store screenshots are viewed as small thumbnails — larger supporting text there */
.portrait .kicker { font-size: calc(var(--u) * 2.0); }
.portrait .sub { font-size: calc(var(--u) * 3.4); }
.portrait .caption { font-size: calc(var(--u) * 1.9); }
.portrait .tag { font-size: calc(var(--u) * 2.0); }
.portrait .footer span { font-size: calc(var(--u) * 1.8); }
"""

LOGO = "../../../media/logo.png"  # relative to src/_build/


def page(fmt_name, w, h, orient, body_html, kicker, title, sub, footer=True):
    u = w / 100 if orient != "landscape" else h / 62
    foot = (f'<div class="footer"><img src="{LOGO}"><span>makapix.club</span></div>'
            if footer else "")
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
:root {{ --u: {u:.2f}px; }}
{CSS}
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


# ---------------------------------------------------------------- slides

def slide_frames(orient):
    cards = ""
    picks = [0, 2, 4, 6, 8, 10]
    n = len(picks)
    for i, k in enumerate(picks):
        d = i - (n - 1) / 2
        rot = d * 4.0
        ty = 0.55 * d * d  # gentle upward arc, in --u units
        cards += (f'<img class="pix card" src="{art(f"ball_{k:02d}.png")}" '
                  f'style="transform: rotate({rot:.1f}deg) '
                  f'translateY(calc(var(--u) * {ty:.2f}));">')
    size = {"portrait": 22, "square": 18, "landscape": 15}[orient]
    overlap = {"portrait": -2.5, "square": -2.0, "landscape": -1.6}[orient]
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
    tl = (f'<img class="pix uistrip" src="{art("crops/timeline_row.png")}" '
          f'style="width:92%;">'
          '<div class="caption">THE TIMELINE, ON A PHONE</div>')
    return extra + f'<div class="fan">{cards}</div>' + (tl if orient != "landscape" else "")


def slide_rgba(orient):
    gsize = "52" if orient == "portrait" else "30"
    return f"""
    <div class="checker" style="padding: calc(var(--u)*3);">
      <img class="pix" src="{art('ghost.png')}" style="width: calc(var(--u)*{gsize}); display:block;">
    </div>
    <div class="row">
      <span class="tag">R 8</span><span class="tag">G 8</span>
      <span class="tag">B 8</span><span class="tag" style="color:#4080C0;">A 8</span>
    </div>
    <div class="caption">SOFT ALPHA, PAINTED, NOT KEYED</div>"""


def slide_blend(orient):
    modes = ["multiply", "screen", "overlay", "difference",
             "addition", "darken", "lighten", "exclusion"]
    if orient == "landscape":
        modes = modes[:4]
    elif orient == "portrait":
        modes = ["multiply", "screen", "overlay", "difference", "addition", "exclusion"]
    cells = "".join(
        f'<div class="cell"><img class="pix" src="{art(f"blend_{m}.png")}">'
        f'<div class="caption">{m.upper()}</div></div>' for m in modes)
    cols = 3 if orient == "portrait" else 4
    size = {"portrait": 26, "square": 19, "landscape": 15}[orient]
    return f"""
    <style>
    .grid {{ display:grid; grid-template-columns: repeat({cols}, auto); gap: calc(var(--u)*2.6); }}
    .cell img {{ width: calc(var(--u)*{size}); border-radius: calc(var(--u)*1); display:block; }}
    </style>
    <div class="grid">{cells}</div>"""


def slide_select(orient):
    if orient == "portrait":
        return f'<div class="phone"><img src="{art("crops/select_union_app.png")}"></div>'
    cw = "50" if orient == "square" else "48"
    sw = "62" if orient == "square" else "52"
    return f"""
    <img class="canvascard" src="{art('crops/select_canvas.png')}"
         style="width: calc(var(--u)*{cw});">
    <div>
      <img class="uistrip" src="{art('crops/select_row.png')}"
           style="width: calc(var(--u)*{sw});">
      <div class="caption">RECT &middot; OVAL &middot; LASSO &nbsp;&times;&nbsp;
        REPLACE &middot; ADD &middot; SUBTRACT &middot; INTERSECT</div>
    </div>"""


def slide_levels(orient):
    imsize = "42" if orient == "portrait" else ("30" if orient == "square" else "24")
    ba = f"""
    <div class="row">
      <div><img class="pix" src="{art('levels_before.png')}"
           style="width:calc(var(--u)*{imsize}); border-radius:calc(var(--u)*1);">
           <div class="caption">BEFORE</div></div>
      <div><img class="pix" src="{art('levels_after.png')}"
           style="width:calc(var(--u)*{imsize}); border-radius:calc(var(--u)*1);">
           <div class="caption">AFTER</div></div>
    </div>"""
    strip = (f'<img src="{art("crops/levels_row.png")}" '
             f'style="width:88%; border-radius:calc(var(--u)*1.2); '
             f'border:2px solid #232B38;">')
    return ba + (strip if orient != "landscape" else "")


def slide_ruler(orient):
    if orient == "portrait":
        return f'<div class="phone"><img src="{art("crops/ruler_tool_app.png")}"></div>'
    cw = "46" if orient == "square" else "44"
    sw = "58" if orient == "square" else "48"
    return f"""
    <img class="canvascard" src="{art('crops/ruler_canvas.png')}"
         style="width: calc(var(--u)*{cw});">
    <img class="uistrip" src="{art('crops/ruler_row.png')}"
         style="width: calc(var(--u)*{sw});">"""


def slide_palette(orient):
    data = json.loads((ART / "palette_sort.json").read_text())

    def strip(colors, label):
        cells = "".join(
            f'<div style="background:{c[:7]}"></div>' for c in colors)
        return (f'<div><div class="pstrip">{cells}</div>'
                f'<div class="caption">{label}</div></div>')

    cols = len(data["shuffled"])
    return f"""
    <style>
    .pstrip {{
      display: grid; grid-template-columns: repeat({cols // 2}, 1fr);
      width: calc(var(--u) * 74); border-radius: calc(var(--u)*0.8); overflow: hidden;
    }}
    .pstrip div {{ aspect-ratio: 1; }}
    </style>
    {strip(data['shuffled'], 'IMPORTED: ANY ORDER')}
    {strip(data['sorted'], 'ONE TAP: SORTED BY SIMILARITY')}
    {'<div class="phone" style="width: calc(var(--u)*52);"><img src="'
     + art('crops/palette_top.png') + '"></div>' if orient == 'portrait' else ''}"""


def slide_cleanedge(orient):
    size = {"portrait": 27, "square": 22, "landscape": 17}[orient]
    return f"""
    <div class="row">
      <div><img class="pix" src="{art('crops/rot_orig_zoom.png')}"
        style="width:calc(var(--u)*{size}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">ORIGINAL</div></div>
      <div><img class="pix" src="{art('crops/rot_nearest_zoom.png')}"
        style="width:calc(var(--u)*{size}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">NEAREST</div></div>
      <div><img class="pix" src="{art('crops/rot_cleanedge_zoom.png')}"
        style="width:calc(var(--u)*{size}); border-radius:calc(var(--u)*1); border:2px solid #4080C0;">
        <div class="caption" style="color:#4080C0;">CLEANEDGE</div></div>
    </div>
    <div class="caption">THE SAME 30&deg; ROTATION &mdash; ZOOMED IN</div>"""


def slide_hero(orient):
    pieces = ["fab/machines_dont_care.webp", "fab/homologous_cycles.webp",
              "mushroom.png", "fab/line_ricochet.webp",
              "ghost.png", "fab/tile_wave.webp"]
    n = 4 if orient == "landscape" else len(pieces)
    tiles = "".join(
        f'<img class="pix" src="{art(p)}">' for p in pieces[:n])
    size = {"portrait": 26, "square": 22, "landscape": 15, "banner": 13}[orient]
    return f"""
    <style>
    .strip {{ display:grid; grid-template-columns: repeat({3 if orient in ('portrait', 'square') else n}, auto);
             gap: calc(var(--u)*2); }}
    .strip img {{ width: calc(var(--u)*{size}); border-radius: calc(var(--u)*1.2);
                 border: 2px solid #232B38; background:#141A22; object-fit: cover;
                 aspect-ratio: 1; }}
    </style>
    <div class="strip">{tiles}</div>"""


SLIDES = {
    # name: (kicker, title html, subline, visual builder)
    "frames": ("MAKAPIX EDITOR",
               '<span class="a">1,024</span> FRAMES.<br><span class="a">64</span> LAYERS.',
               "A real animation studio in your pocket.",
               slide_frames),
    "rgba": ("MAKAPIX EDITOR",
             'TRUE <span class="a">32-BIT</span> RGBA.',
             "Every pixel carries real 8-bit alpha. No chroma-key tricks.",
             slide_rgba),
    "blend": ("MAKAPIX EDITOR",
              'REAL <span class="a">BLEND</span> MODES.',
              "Multiply, Screen, Overlay, Difference: ten modes of true layer math.",
              slide_blend),
    "select": ("MAKAPIX EDITOR",
               'SELECTION <span class="a">ALGEBRA</span>.',
               "Add, subtract, intersect, or select a layer's pixels in one tap.",
               slide_select),
    "levels": ("MAKAPIX EDITOR",
               '<span class="a">LEVELS</span>, NOT GUESSWORK.',
               "Remap black point, gamma, and highlights. Way beyond Brightness/Contrast.",
               slide_levels),
    "ruler": ("MAKAPIX EDITOR",
              'MEASURE <span class="a">ANYTHING</span>.',
              "Distances in pixels. Angles in degrees. Right on the canvas.",
              slide_ruler),
    "palette": ("MAKAPIX EDITOR",
                'PALETTES THAT <span class="a">TRAVEL</span>.',
                "Import and export .gpl files, and sort any palette by visual similarity.",
                slide_palette),
    "cleanedge": ("MAKAPIX EDITOR",
                  'ROTATE WITHOUT <span class="a">JAGGIES</span>.',
                  "cleanEdge rotation and scaling keep pixel art crisp.",
                  slide_cleanedge),
    "hero": ("MAKAPIX CLUB",
             'DRAW IT.<br>ANIMATE IT.<br><span class="a">SHARE IT.</span>',
             "Animated pixel art, made and shared on your phone. Free on Android and iOS.",
             slide_hero),
}

ORDER = ["frames", "rgba", "blend", "select", "levels",
         "ruler", "palette", "cleanedge", "hero"]


# ---------------------------------------------------------------- render

def render(html_path, out_path, w, h):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(CHROME), "--headless", "--disable-gpu", "--hide-scrollbars",
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


def build(picks):
    crops()
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in picks:
        kicker, title, sub, builder = SLIDES[name]
        idx = ORDER.index(name) + 1
        targets = dict(FORMATS)
        for fmt, (w, h, orient) in targets.items():
            body = builder(orient)
            html = page(fmt, w, h, orient, body, kicker, title, sub)
            hp = BUILD / f"{name}_{fmt}.html"
            hp.write_text(html, encoding="utf-8")
            render(hp, OUT / fmt / f"{idx:02d}_{name}.png", w, h)
        if name == "hero":
            w, h = BANNER
            body = builder("banner")
            html = page("banner", w, h, "landscape", body, kicker, title, sub)
            hp = BUILD / f"{name}_banner.html"
            hp.write_text(html, encoding="utf-8")
            render(hp, OUT / "play_feature_graphic.png", w, h)
        print(f"ok {name}")


if __name__ == "__main__":
    build(sys.argv[1:] or ORDER)
