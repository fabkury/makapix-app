#!/usr/bin/env python3
"""Compose and render the marketing assets.

Builds one HTML page per (slide x format), renders each with headless Chrome at
exact pixel dimensions, and verifies the output with Pillow. Run from the repo
root:

    python docs/marketing/src/build.py [slide ...]   (default: all slides)

Slides: hero replay animation paint color select palette club files.
Outputs land in docs/marketing/out/<format>/. Play takes 01..08 (its listing
caps at 8 screenshots); the App Store additionally takes 09_files.

2026-08-31 redesign: denser three-zone layouts (primary demo, secondary proof
panel, chip ticker), community art from the public recommended feed with
on-slide @handle credits, and new slides for replay/timelapse and the brush
stack. The Play feature graphic is rebuilt too (hero slide, banner format).
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path.cwd()
SRC = Path("docs/marketing/src")
ART = Path("docs/marketing/art")
CLUB = ART / "club"
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

CREDITS = json.loads((CLUB / "credits.json").read_text(encoding="utf-8"))


# ---------------------------------------------------------------- crop pre-pass

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
  font-family: 'PS2P'; font-size: calc(var(--u) * 1.3);
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
  text-align: right; overflow: hidden;
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
.portrait .credit { font-size: calc(var(--u) * 1.5); }
.portrait .plabel { font-size: calc(var(--u) * 1.7); }
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


def chips(items):
    spans = "".join(
        f'<span class="chip{" hot" if hot else ""}">{t}</span>'
        for t, hot in items)
    return f'<div class="chips">{spans}</div>'


def tile(name, size_u, drawn_here=False):
    """A credited community-art tile. `name` is a key into credits.json."""
    c = CREDITS[name]
    handle = c["handle"]
    badge = ('<div class="credit">DRAWN IN MAKAPIX<br>' if drawn_here
             else '<div class="credit">')
    return (f'<div class="tile" style="width: calc(var(--u)*{size_u});">'
            f'<img class="pix" src="{art(f"club/{name}.png")}">'
            f'{badge}@{handle}</div></div>')


def shot_crop(crop_name, fallback):
    """Use a fresh device crop when it exists; otherwise the fallback crop."""
    return crop_name if (CROPS / f"{crop_name}.png").exists() else fallback


# ---------------------------------------------------------------- slides

def slide_hero(orient):
    phone_crop = shot_crop("hero_senna_app", "editor_hero_app")
    wall = "".join(tile(n, {"portrait": 17.8, "square": 11.2, "landscape": 12}[orient])
                   for n in ["daydream", "mr_tritium", "seaside_city", "cozy_blizzard"])
    tick = chips([("512&times;512", False), ("1,024 FRAMES", True), ("64 LAYERS", True),
                  ("10 BLEND MODES", False), ("TIMELAPSE EXPORT", False)])
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
             '<div class="caption">THE SAME DRAWING, FIVE MOMENTS OF ITS REPLAY</div></div>')
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
      <div class="plabel">SCRUB. EXPORT. SHARE.</div>
    </div>"""
    tick = chips([("EVERY STROKE RECORDED", True), ("MP4", True), ("GIF", True),
                  ("WEBP", True), ("SHARE YOUR PROCESS", False)])
    viewer = ""
    vc = shot_crop("replay_viewer_app", "")
    if vc and orient == "portrait":
        viewer = (f'<div class="phone" style="width: calc(var(--u)*42);">'
                  f'<img src="{art(f"crops/{vc}.png")}"></div>')
    if orient == "landscape":
        return strip + tick
    return strip + (viewer or player) + tick


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
          '<div class="caption">THE TIMELINE, ON A PHONE</div>')
    tick = chips([("1,024 FRAMES", True), ("64 LAYERS", True),
                  ("PER-FRAME TIMING", False), ("ONION SKIN", False),
                  ("LIVE LOOP PREVIEW", False)])
    body = extra + f'<div class="fan">{cards}</div>'
    if orient != "landscape":
        body += f"<div>{tl}</div>"
    return body + tick


def slide_paint(orient):
    aa_w = {"portrait": 17, "square": 11, "landscape": 10}[orient]
    air_w = {"portrait": 24, "square": 15, "landscape": 14}[orient]
    p_aa = f"""
    <div class="panel"><div class="plabel">AA <span class="a">OFF</span> / <span class="a">ON</span></div>
      <div class="row" style="gap: calc(var(--u)*1.2);">
        <img class="pix" src="{art('aa_off.png')}" style="width: calc(var(--u)*{aa_w});">
        <img class="pix" src="{art('aa_on.png')}" style="width: calc(var(--u)*{aa_w});">
      </div></div>"""
    p_air = f"""
    <div class="panel"><div class="plabel">AIRBRUSH &times;3</div>
      <div style="display:flex; flex-direction:column; gap: calc(var(--u)*0.8);">
        <img class="pix" src="{art('air_dots.png')}" style="width: calc(var(--u)*{air_w});">
        <img class="pix" src="{art('air_soft.png')}" style="width: calc(var(--u)*{air_w});">
        <img class="pix" src="{art('air_mist.png')}" style="width: calc(var(--u)*{air_w});">
      </div></div>"""
    p_grad = f"""
    <div class="panel"><div class="plabel"><span class="a">8-STOP</span> GRADIENTS</div>
      <img class="pix" src="{art('gradient8.png')}" style="width: calc(var(--u)*{air_w + 10});">
    </div>"""
    p_coat = f"""
    <div class="panel"><div class="plabel">ONE STROKE, ONE COAT</div>
      <div class="checker" style="padding: calc(var(--u)*0.8);">
      <img class="pix" src="{art('coat_one.png')}" style="width: calc(var(--u)*{aa_w}); display:block;">
      </div></div>"""
    tick = chips([("AA TOGGLE", True), ("DOTS / SOFT / MIST", False),
                  ("PIXEL-PERFECT PENCIL", False), ("RADIAL + LINEAR", False)])
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
    sph_w = {"portrait": 16, "square": 9, "landscape": 11}[orient]
    stroke_w = {"portrait": 22, "square": 12, "landscape": 15}[orient]
    grad_w = {"portrait": 30, "square": 16, "landscape": 22}[orient]
    land = orient == "landscape"
    p_sphere = f"""
    <div class="panel"><div class="plabel">{"BUCKET" if land else 'BUCKET + <span class="a">BAYER</span>'}</div>
      <img class="pix" src="{art('pat_sphere.png')}" style="width: calc(var(--u)*{sph_w});">
    </div>"""
    p_stroke = f"""
    <div class="panel"><div class="plabel">{"BRUSH" if land else "ONE BRUSH STROKE"}</div>
      <img class="pix" src="{art('pat_stroke.png')}" style="width: calc(var(--u)*{stroke_w});">
    </div>"""
    ramps = "".join(
        f'<img class="pix" src="{art(n)}" style="width: calc(var(--u)*{grad_w}); display:block;">'
        for n in ["pat_grad_off.png", "pat_grad_b2.png", "pat_grad_b8.png"])
    p_grad = f"""
    <div class="panel"><div class="plabel">GRADIENT: SMOOTH / <span class="a">2&times;2</span> / <span class="a">8&times;8</span></div>
      <div style="display:flex; flex-direction:column; gap: calc(var(--u)*0.6);">{ramps}</div>
    </div>"""
    tiles_w = {"portrait": 62, "square": 40, "landscape": 40}[orient]
    p_tiles = f"""
    <div class="panel"><div class="plabel"><span class="a">116</span> TILES, EVERY ONE WITH ITS INVERSE</div>
      <img class="pix" src="{art('pat_tiles.png')}" style="width: calc(var(--u)*{tiles_w});">
    </div>"""
    tick = chips([("PENCIL / BRUSH / ERASER / BUCKET", True), ("ONE TAP: ON / OFF", False),
                  ("MESHES ACROSS STROKES", False), ("DITHERED GRADIENTS", True)])
    page_crop = shot_crop("patterns_page_app", "")
    if orient == "landscape":
        phone = (f'<div class="phone" style="width: calc(var(--u)*17);">'
                 f'<img src="{art(f"crops/{page_crop}.png")}"></div>' if page_crop else "")
        return f'<div class="row">{phone}{p_sphere}{p_stroke}</div>' + tick
    ph = {"portrait": 29, "square": 16}[orient]
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
        f'<div class="caption">{m.upper()}</div></div>' for m in modes)
    grid = (f'<div style="display:grid; grid-template-columns: repeat(3, auto); '
            f'gap: calc(var(--u)*1.8);">{cells}</div>')
    gsize = {"portrait": 22, "square": 16, "landscape": 12}[orient]
    ghost = f"""
    <div><div class="checker" style="padding: calc(var(--u)*1.6);">
      <img class="pix" src="{art('ghost.png')}" style="width: calc(var(--u)*{gsize}); display:block;">
    </div><div class="caption">PAINTED ALPHA</div></div>"""
    lsize = {"portrait": 15.5, "square": 12, "landscape": 10}[orient]
    levels = f"""
    <div class="panel"><div class="plabel"><span class="a">LEVELS</span></div>
      <div class="row" style="gap: calc(var(--u)*1.2);">
        <div><img class="pix" src="{art('levels_before.png')}"
             style="width:calc(var(--u)*{lsize}); border-radius:calc(var(--u)*1);">
             <div class="caption">BEFORE</div></div>
        <div><img class="pix" src="{art('levels_after.png')}"
             style="width:calc(var(--u)*{lsize}); border-radius:calc(var(--u)*1);">
             <div class="caption">AFTER</div></div>
      </div></div>"""
    tick = chips([("8-BIT ALPHA", True), ("10 BLEND MODES", True),
                  ("LEVELS: BLACK POINT / GAMMA / HIGHLIGHTS", False),
                  (".GPL PALETTES IN / OUT", False)])
    if orient == "landscape":
        return f'<div class="row">{ghost}{grid}</div>' + tick
    return f'<div class="row">{ghost}{levels}</div>{grid}' + tick


def slide_select(orient):
    csize = {"portrait": 36, "square": 28, "landscape": 26}[orient]
    canvas = f"""
    <div>
      <img class="canvascard" src="{art('crops/select_canvas.png')}"
           style="width: calc(var(--u)*{csize});">
      <img class="uistrip" src="{art('crops/select_row.png')}"
           style="width: calc(var(--u)*{csize}); margin: calc(var(--u)*1.2) auto 0;">
    </div>"""
    zsize = {"portrait": 19, "square": 15, "landscape": 11}[orient]
    ce = f"""
    <div class="row">
      <div><img class="pix" src="{art('crops/rot_orig_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">ORIGINAL</div></div>
      <div><img class="pix" src="{art('crops/rot_nearest_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #2A3442;">
        <div class="caption">NEAREST</div></div>
      <div><img class="pix" src="{art('crops/rot_cleanedge_zoom.png')}"
        style="width:calc(var(--u)*{zsize}); border-radius:calc(var(--u)*1); border:2px solid #4080C0;">
        <div class="caption" style="color:#4080C0;">CLEANEDGE</div></div>
    </div>
    <div class="caption">THE SAME 30&deg; ROTATION, ZOOMED IN</div>"""
    tick = chips([("RECT / OVAL / LASSO", False), ("ADD", True), ("SUBTRACT", True),
                  ("INTERSECT", True), ("MEASURE PX + DEGREES", False)])
    if orient == "landscape":
        return f"<div>{ce}</div>" + tick
    return canvas + f"<div>{ce}</div>" + tick


def slide_free(orient):
    """Free, ad-free, open-source: three statement panels + the repo line."""
    pw = {"portrait": 27, "square": 19, "landscape": 14}[orient]
    tick = chips([("TRULY FREE", True), ("NO ADS", False), ("NO SUBSCRIPTIONS", False),
                  ("NO IN-APP PURCHASES", False), ("DRAW WITHOUT AN ACCOUNT", False),
                  ("APACHE-2.0", True)])
    repo = f"""
    <div>
      <div class="tag" style="border-color:#4080C0; text-align:center;">
        github.com/fabkury/makapix-app</div>
      <div class="caption">THE APP AND THE SERVER, BUILT IN THE OPEN</div>
    </div>"""
    panels = f"""
    <style>
    .freepanel {{
      width: calc(var(--u)*{pw}); aspect-ratio: 1 / 1.05;
      justify-content: center; gap: calc(var(--u)*2.2);
    }}
    .bignum {{ font-family:'PS2P'; font-size: calc(var(--u)*{pw * 0.26:.1f}); color:#F2F6FA; }}
    .strike {{ position:relative; font-family:'PS2P';
              font-size: calc(var(--u)*{pw * 0.17:.1f}); color:#7A8AA0; }}
    .strike::after {{ content:''; position:absolute; left:-10%; right:-10%; top:46%;
              height: calc(var(--u)*0.9); background:#E05050;
              transform: rotate(-12deg); border-radius: calc(var(--u)*0.5); }}
    .oss {{ font-family:'PS2P'; font-size: calc(var(--u)*{pw * 0.2:.1f}); color:#4080C0; }}
    </style>
    <div class="row" style="align-items: stretch;">
      <div class="panel freepanel"><span class="bignum">$0</span>
        <div class="plabel">FOREVER</div></div>
      <div class="panel freepanel"><span class="strike">ADS</span>
        <div class="plabel">ZERO. EVER.</div></div>
      <div class="panel freepanel"><span class="oss">&lt;/&gt;</span>
        <div class="plabel"><span class="a">OPEN</span> SOURCE</div></div>
    </div>"""
    if orient == "landscape":
        return panels + tick
    return panels + repo + tick


def slide_club(orient):
    grid_names = ["brave_bear", "night_island", "chess3d",
                  "yellow_tang", "fairy_flower", "mr_tritium"]
    tsize = {"portrait": 19.5, "square": 15, "landscape": 11}[orient]
    wall = "".join(tile(n, tsize) for n in grid_names)
    grid = (f'<div style="display:grid; grid-template-columns: repeat(3, auto); '
            f'gap: calc(var(--u)*1.8);">{wall}</div>')
    tick = chips([("PUBLISH FREE", True), ("REACTIONS + COMMENTS", False),
                  ("REMIX WITH LINEAGE", True), ("LIVE NOTIFICATIONS", False)])
    if orient == "landscape":
        return grid + tick
    # the pre-redesign shots/club_feed.png is NOT an acceptable fallback here: it
    # shows fan-art and a photo-import portrait (IP + likeness exclusions)
    feed = shot_crop("club_feed_new_app", "")
    phone = ""
    if feed and orient == "portrait":
        phone = (f'<div class="phone" style="width: calc(var(--u)*40);">'
                 f'<img src="{art(f"crops/{feed}.png")}"></div>')
    if phone:
        return (f'<div class="row" style="align-items:center;">{grid}{phone}</div>'
                + tick)
    return grid + tick


def slide_files(orient):
    fin = ["GIF", "PNG", "APNG", "WEBP", "JPEG", "BMP"]
    fout = ["PNG", "GIF", "ANIMATED WEBP", ".MKPX LAYERS"]
    fl_in = "".join(f'<span class="tag">{t}</span>' for t in fin)
    fl_out = "".join(f'<span class="tag" style="border-color:#4080C0;">{t}</span>'
                     for t in fout)
    flow = f"""
    <div class="panel" style="width: 88%;">
      <div class="plabel">IMPORT</div>
      <div class="row" style="flex-wrap:wrap; gap: calc(var(--u)*1.2);">{fl_in}</div>
      <div class="plabel" style="margin-top: calc(var(--u)*1.6);">EXPORT</div>
      <div class="row" style="flex-wrap:wrap; gap: calc(var(--u)*1.2);">{fl_out}</div>
    </div>"""
    tick = chips([("LOSSLESS WEBP ANIMATION", True), ("LAYERED .MKPX PROJECTS", False),
                  ("SHARE ANYWHERE", False)])
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
    tick = chips([("DRAW", True), ("ANIMATE", True), ("REPLAY", True), ("PUBLISH", True)])
    return f"""
    <div style="display:flex; flex-direction:column; gap: calc(var(--u)*2.4);
                align-items:center;">
      <div class="row" style="gap: calc(var(--u)*1.6);">{strip}</div>
      {tick}
    </div>"""


SLIDES = {
    # name: (kicker, title html, subline, visual builder)
    "hero": ("MAKAPIX",
             'A PIXEL ART <span class="a">STUDIO</span> IN YOUR POCKET.',
             "Draw, animate, and publish pixel art. Free on Android and iOS.",
             slide_hero),
    "replay": ("MAKAPIX EDITOR",
               'YOUR ART <span class="a">DRAWS ITSELF</span>.',
               "Every stroke is recorded. Scrub the replay and export a timelapse as MP4, GIF, or WebP.",
               slide_replay),
    "animation": ("MAKAPIX EDITOR",
                  '<span class="a">1,024</span> FRAMES.<br><span class="a">64</span> LAYERS.',
                  "A real animation timeline: per-frame durations, frame-by-frame control, live loop preview.",
                  slide_animation),
    "paint": ("MAKAPIX EDITOR",
              'BRUSHES BUILT FOR <span class="a">PIXELS</span>.',
              "Anti-aliased edges when you want them. Three airbrushes. Eight-stop gradients. Single-coat strokes.",
              slide_paint),
    "patterns": ("MAKAPIX EDITOR",
                 'DITHER WITH <span class="a">ONE TAP</span>.',
                 "Pick a pattern and every stroke, fill, and erase paints through it. Bayer ladders, lines, bricks, checkers, plus ordered dithering for gradients.",
                 slide_patterns),
    "color": ("MAKAPIX EDITOR",
              'REAL RGBA. <span class="a">TEN</span> BLEND MODES.',
              "True 8-bit alpha in every pixel. Multiply, Screen, Overlay and more, plus Levels to rescue any import.",
              slide_color),
    "select": ("MAKAPIX EDITOR",
               'SELECT IT. SPIN IT.<br><span class="a">NO JAGGIES</span>.',
               "Rect, oval, and lasso with add, subtract, and intersect. cleanEdge rotation keeps pixel art crisp.",
               slide_select),
    "free": ("MAKAPIX CLUB",
             'FREE. AD-FREE.<br><span class="a">OPEN-SOURCE.</span>',
             "No ads, no subscriptions, no unlocks. The whole platform is open-source: the app and the server.",
             slide_free),
    "club": ("MAKAPIX CLUB",
             'DRAW IT.<br>ANIMATE IT.<br><span class="a">SHARE IT.</span>',
             "Publish to the Makapix Club, react and comment, remix with public lineage. Free on Android and iOS.",
             slide_club),
    "files": ("MAKAPIX EDITOR",
              'OPENS EVERYTHING <span class="a">YOU HAVE</span>.',
              "Import GIF, PNG, APNG, WebP, JPEG, BMP. Export PNG, GIF, and animated lossless WebP, plus layered .mkpx projects.",
              slide_files),
}

ORDER = ["hero", "free", "replay", "animation", "paint", "patterns",
         "color", "club", "select", "files"]
PLAY_MAX = 8  # the Play listing caps at 8 screenshots; 09_select and 10_files are App Store only


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
        for fmt, (w, h, orient) in FORMATS.items():
            if fmt == "play" and idx > PLAY_MAX:
                continue
            body = builder(orient)
            html = page(fmt, w, h, orient, body, kicker, title, sub)
            hp = BUILD / f"{name}_{fmt}.html"
            hp.write_text(html, encoding="utf-8")
            render(hp, OUT / fmt / f"{idx:02d}_{name}.png", w, h)
        if name == "hero":
            w, h = BANNER
            body = banner_hero()
            html = page("banner", w, h, "landscape", body, "MAKAPIX",
                        'PIXEL ART <span class="a">STUDIO</span> + COMMUNITY.',
                        "Draw, animate, replay, publish. Free.")
            hp = BUILD / "hero_banner.html"
            hp.write_text(html, encoding="utf-8")
            render(hp, OUT / "play_feature_graphic.png", w, h)
        print(f"ok {name}")


if __name__ == "__main__":
    build(sys.argv[1:] or ORDER)
