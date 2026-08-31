#!/usr/bin/env python3
"""Generate the engine-rendered demo art for the marketing assets.

Authors pixel maps in Python, emits mkpx DSL scripts, and runs the release
`mkpx` CLI so every output PNG is a genuine engine render. Run from the repo
root (the render probe wants relative paths):

    python docs/marketing/src/engine/gen_art.py [asset ...]

Assets: mushroom ghost rotate scale blend levels ball palette aa airbrush
gradient8 coat replay (default: all).
"""

import json
import math
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3].parent  # repo root
ENGDIR = Path("docs/marketing/src/engine")
ART = Path("docs/marketing/art")
MKPX = Path("target/release/mkpx.exe")


# ---------------------------------------------------------------- DSL helpers

def emit_pixels(lines, pixels):
    """Emit DSL for a {(x, y): '#RRGGBBAA'} map: Line strokes for runs,
    Pencil taps for single pixels, grouped by color."""
    by_color = {}
    for (x, y), c in pixels.items():
        by_color.setdefault(c, set()).add((x, y))
    lines.append("SetPixelPerfect(false)")
    lines.append("SetBrushSize(1)")
    lines.append("SetLineWidth(1)")
    for color, pts in by_color.items():
        runs, singles = [], []
        rows = {}
        for (x, y) in pts:
            rows.setdefault(y, []).append(x)
        for y, xs in rows.items():
            xs.sort()
            i = 0
            while i < len(xs):
                j = i
                while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1:
                    j += 1
                if j > i:
                    runs.append((xs[i], xs[j], y))
                else:
                    singles.append((xs[i], y))
                i = j + 1
        lines.append(f"SetPrimaryColor({color})")
        if runs:
            lines.append("SelectTool(Line)")
            for x0, x1, y in runs:
                lines.append(f"Stroke([({x0},{y}),({x1},{y})])")
        if singles:
            lines.append("SelectTool(Pencil)")
            for x, y in singles:
                lines.append(f"Tap({x},{y})")


def run_mkpx(script_name, dsl_lines, probes):
    path = ENGDIR / script_name
    path.write_text("\n".join(dsl_lines) + "\n", encoding="utf-8")
    cmd = [str(MKPX), "run", str(path)] + probes
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        raise SystemExit(f"{script_name}: mkpx exit {r.returncode}")
    return r.stdout


# ---------------------------------------------------------------- sprites

def mushroom_pixels():
    """A 28x28 outlined mushroom sprite, procedurally plotted."""
    O = "#241418FF"   # outline
    R = "#C83440FF"   # cap red
    RL = "#E85C50FF"  # cap light
    RH = "#F49C86FF"  # cap sheen
    W = "#F6EEDEFF"   # spots
    G = "#8C5C40FF"   # gills
    S = "#EAD4ACFF"   # stem
    SD = "#C4A47CFF"  # stem shade
    px = {}

    cx, cy, rx, ry = 13.5, 10.5, 10.2, 7.6
    for y in range(28):
        for x in range(28):
            dx, dy = (x - cx) / rx, (y - cy) / ry
            if dx * dx + dy * dy <= 1.0 and y <= 15:
                c = R
                if dy < -0.15 and dx < 0.55:
                    c = RL
                if dy < -0.55 and -0.65 < dx < 0.35:
                    c = RH
                px[(x, y)] = c
    for sx, sy, sr in [(8, 9, 2.3), (17, 12, 2.5), (13, 6, 1.7), (20, 8, 1.3), (6, 13, 1.4)]:
        for y in range(28):
            for x in range(28):
                if (x, y) in px and (x - sx) ** 2 + (y - sy) ** 2 <= sr * sr:
                    px[(x, y)] = W
    for x in range(28):
        if (x, 15) in px:
            px[(x, 15)] = G
            if (x, 14) in px and (x < 7 or x > 20):
                px[(x, 14)] = G
    for y in range(16, 25):
        wob = 1 if y >= 22 else 0
        for x in range(10 - wob, 18 + wob):
            px[(x, y)] = SD if x >= 16 else S
    # outside outline: any empty pixel orthogonally adjacent to a filled one
    outline = set()
    for (x, y) in list(px):
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in px and 0 <= nx < 28 and 0 <= ny < 28:
                outline.add((nx, ny))
    for p in outline:
        px[p] = O
    return px


def key_pixels():
    """A 32x32 skeleton key: ring bow, thin shaft, side teeth.

    The cleanEdge demo sprite (chosen 2026-08-11 over the mushroom, whose
    chunky silhouette survived nearest-neighbor rotation too well): the ring
    goes lumpy, the 2px shaft ragged, and the teeth chip under nearest, while
    cleanEdge holds all three."""
    G, D, W = "#F0C050FF", "#C89030FF", "#F6EEDEFF"
    px = {}
    # bow: gold ring with a real hole
    for y in range(32):
        for x in range(32):
            d2 = (x - 15.5) ** 2 + (y - 7.5) ** 2
            if 3.1 ** 2 <= d2 <= 5.9 ** 2:
                px[(x, y)] = D if (y > 9 and x > 15) else G
    # collar under the bow
    for y in (13, 14):
        for x in range(14, 18):
            px[(x, y)] = D if y == 14 else G
    # shaft: 2px, right column shaded
    for y in range(14, 28):
        px[(15, y)] = G
        px[(16, y)] = D
    # teeth pointing right near the tip
    for x in range(17, 21):
        px[(x, 22)] = G
        px[(x, 23)] = D
    for x in range(17, 22):
        px[(x, 26)] = G
        px[(x, 27)] = D
    # glint on the bow
    px[(13, 4)] = px[(14, 4)] = px[(13, 5)] = W
    # outside outline, same adjacency trick as the mushroom
    outline = set()
    for (x, y) in list(px):
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in px and 0 <= nx < 32 and 0 <= ny < 32:
                outline.add((nx, ny))
    for p in outline:
        px[p] = "#241418FF"
    return px


def ghost_pixels():
    """A 32x32 ghost with a real per-pixel alpha falloff toward the tail."""
    px = {}
    cx, r = 15.5, 9.6
    for y in range(4, 27):
        for x in range(32):
            dx = x - cx
            if y <= 13:
                dy = y - 13
                inside = dx * dx + dy * dy <= r * r
            else:
                scallop = 1.6 * math.sin((x - 6) * math.pi / 6.5)
                inside = abs(dx) <= r and y <= 24 + scallop
            if not inside:
                continue
            a = 216 if y <= 15 else max(56, int(216 - (y - 15) * 16))
            edge = r - abs(dx)
            if edge < 1.6:
                a = int(a * 0.72)
            px[(x, y)] = f"#E8F4FF{a:02X}"
    for ex in (11, 19):
        for y in (12, 13, 14):
            px[(ex, y)] = "#20283CE6"
            px[(ex + 1, y)] = "#20283CE6"
    for bx in (8, 22):
        px[(bx, 16)] = "#FFA0B08C"
        px[(bx + 1, 16)] = "#FFA0B08C"
    for y in (17, 18):
        px[(15, y)] = "#20283CC8"
        px[(16, y)] = "#20283CC8"
    return px


# ---------------------------------------------------------------- assets

def build_mushroom():
    lines = ["NewDocument(28, 28)"]
    emit_pixels(lines, mushroom_pixels())
    run_mkpx("mushroom.txt", lines, [f"render:0:{ART}/mushroom.png:8".replace("\\", "/")])


def build_ghost():
    lines = ["NewDocument(32, 32)"]
    # glow layer behind the ghost
    lines += [
        "SelectTool(Gradient)", "SetGradientType(Radial)",
        "SetGradientStops([#6CB2FF55@0, #6CB2FF2E@0.55, #6CB2FF00@1])",
        "Stroke([(16,15),(16,0)])",
        "AddLayer()",
    ]
    emit_pixels(lines, ghost_pixels())
    run_mkpx("ghost.txt", lines, [f"render:0:{ART}/ghost.png:8".replace("\\", "/")])


def sprite_doc(canvas, offset):
    """DSL that plots the key centered on a larger transparent canvas."""
    ox, oy = offset
    shifted = {(x + ox, y + oy): c for (x, y), c in key_pixels().items()}
    lines = [f"NewDocument({canvas}, {canvas})"]
    emit_pixels(lines, shifted)
    return lines


def build_rotate():
    for name, clean in [("rot_nearest", "false"), ("rot_cleanedge", "true")]:
        lines = sprite_doc(48, (8, 8))
        lines += [
            f"SetCleanEdge({clean})",
            "RotateDraftBegin()",
            "RotateDraftSetAngle(524)",  # 30 degrees clockwise, in milliradians
            "RotateDraftCommit()",
        ]
        run_mkpx(f"{name}.txt", lines, [f"render:0:{ART}/{name}.png:8".replace("\\", "/")])
    run_mkpx("rot_orig.txt", sprite_doc(48, (8, 8)),
             [f"render:0:{ART}/rot_orig.png:8".replace("\\", "/")])


def build_scale():
    for name, clean in [("scale_nearest", "false"), ("scale_cleanedge", "true")]:
        lines = sprite_doc(96, (32, 32))
        lines += [f"SetScaleCleanEdge({clean})", "ScaleLayer(3000, 3000)"]
        run_mkpx(f"{name}.txt", lines, [f"render:0:{ART}/{name}.png:4".replace("\\", "/")])


BLEND_MODES = ["Normal", "Multiply", "Screen", "Overlay", "Darken", "Lighten",
               "Addition", "Subtract", "Difference", "Exclusion", "HardLight"]


def dusk_scene():
    """Base scene DSL (layer 0): dusk sky, sun, mountain silhouettes."""
    lines = [
        "NewDocument(64, 64)",
        "SelectTool(Gradient)", "SetGradientType(Linear)",
        "SetGradientStops([#141C34FF@0, #3A2C50FF@0.42, #B4503CFF@0.72, #F0A050FF@1])",
        "Stroke([(32,0),(32,63)])",
        "SelectTool(Ellipse)", "SetShapeFill(true)",
        "SetPrimaryColor(#F8D890FF)",
        "Stroke([(38,30),(50,42)])",
    ]
    px = {}
    far, near = "#2A2038FF", "#170F20FF"
    for x in range(64):
        h1 = 12 + 6 * math.sin(x * 0.20 + 1.2) + 3 * math.sin(x * 0.53)
        for y in range(int(64 - 24 - h1 + 12), 64):
            px[(x, y)] = far
        h2 = 8 + 7 * math.sin(x * 0.16 + 4.0) + 2.5 * math.sin(x * 0.71 + 1.0)
        for y in range(int(64 - 10 - h2 + 4), 64):
            px[(x, y)] = near
    for sx, sy in [(6, 5), (17, 9), (29, 4), (45, 7), (57, 11), (38, 13), (11, 16)]:
        px[(sx, sy)] = "#F0EAD8C8"
    emit_pixels(lines, px)
    return lines


def build_blend():
    lines = dusk_scene()
    lines += [
        "AddLayer()",
        "SelectTool(Gradient)", "SetGradientType(Radial)",
        "SetGradientStops([#FFD890FF@0, #E86840B4@0.38, #30203800@1])",
        "Stroke([(44,36),(6,2)])",
    ]
    for i in range(1, len(BLEND_MODES)):
        lines.append("DuplicateFrame(0)")
    for i, mode in enumerate(BLEND_MODES):
        lines += [f"SetActiveFrame({i})", f"SetLayerBlend(1, {mode})"]
    probes = [f"render:{i}:{ART}/blend_{m.lower()}.png:4".replace("\\", "/")
              for i, m in enumerate(BLEND_MODES)]
    run_mkpx("blendgrid.txt", lines, probes)


def build_levels():
    lines = [
        "NewDocument(64, 64)",
        "SelectTool(Gradient)", "SetGradientType(Linear)",
        "SetGradientStops([#0A0E1AFF@0, #141B2CFF@0.6, #223048FF@1])",
        "Stroke([(32,0),(32,63)])",
        "SelectTool(Ellipse)", "SetShapeFill(true)",
        "SetPrimaryColor(#3A4458FF)",
        "Stroke([(42,8),(52,18)])",
        "SetPrimaryColor(#0A0E1AFF)",
        "Stroke([(45,7),(53,15)])",
    ]
    px = {}
    for x in range(64):
        h1 = 10 + 6 * math.sin(x * 0.18 + 0.6) + 2.5 * math.sin(x * 0.5 + 2)
        for y in range(int(52 - h1), 64):
            px[(x, y)] = "#101624FF"
        h2 = 5 + 5 * math.sin(x * 0.13 + 3.4) + 2 * math.sin(x * 0.66)
        for y in range(int(62 - h2), 64):
            px[(x, y)] = "#0A0C14FF"
    # a dim cabin with a faint window
    for y in range(42, 48):
        for x in range(16, 25):
            px[(x, y)] = "#1A2030FF"
    for y in range(40, 42):
        for x in range(15, 26):
            px[(x, y)] = "#131826FF"
    for y in range(44, 46):
        for x in range(19, 21):
            px[(x, y)] = "#4A4030FF"
    for sx, sy in [(8, 6), (14, 12), (30, 5), (37, 10), (55, 6), (60, 14), (24, 15)]:
        px[(sx, sy)] = "#38405CFF"
    emit_pixels(lines, px)
    lines += [
        "DuplicateFrame(0)",
        "SetActiveFrame(1)",
        "SetLevelsScope(true)",
        "SetLevels(8, 1450, 90)",
        "ApplyLevels()",
    ]
    run_mkpx("levels.txt", lines, [
        f"render:0:{ART}/levels_before.png:4".replace("\\", "/"),
        f"render:1:{ART}/levels_after.png:4".replace("\\", "/"),
    ])


def build_ball():
    n = 12
    lines = ["NewDocument(48, 48)"]
    probes = []
    for k in range(n):
        if k > 0:
            lines.append("AddFrame()")
            lines.append(f"SetActiveFrame({k})")
        h = abs(math.cos(math.pi * k / n))          # 1 at top, 0 at impact
        squash = max(0.0, 1.0 - h * 6)              # only right at impact
        rx = 7 * (1 + 0.38 * squash)
        ry = 7 * (1 - 0.34 * squash)
        ground = 41
        cyb = ground - ry - h * 24
        cxb = 24
        # ground strip
        lines += ["SelectTool(Line)", "SetLineWidth(1)", "SetPrimaryColor(#2A3448FF)"]
        for gy in (42, 43):
            lines.append(f"Stroke([(4,{gy}),(43,{gy})])")
        # contact shadow
        sw = 4 + (1 - h) * 7
        sa = int(40 + (1 - h) * 80)
        lines += [
            "SelectTool(Ellipse)", "SetShapeFill(true)",
            f"SetPrimaryColor(#000000{sa:02X})",
            f"Stroke([({int(cxb - sw)},{ground + 1}),({int(cxb + sw)},{ground + 3})])",
        ]
        # ball: body, rim shade, highlight, glint
        x0, y0 = int(cxb - rx), int(cyb - ry)
        x1, y1 = int(cxb + rx), int(cyb + ry)
        lines += [
            "SetPrimaryColor(#2A5A90FF)", f"Stroke([({x0},{y0}),({x1},{y1})])",
            "SetPrimaryColor(#4080C0FF)", f"Stroke([({x0},{y0}),({x1 - 2},{y1 - 2})])",
            "SetPrimaryColor(#78B0E8FF)",
            f"Stroke([({x0 + 2},{y0 + 2}),({int(cxb)},{int(cyb)})])",
            "SelectTool(Pencil)", "SetBrushSize(2)", "SetPrimaryColor(#E8F4FFFF)",
            f"Tap({x0 + 4},{y0 + 4})",
        ]
        probes.append(f"render:{k}:{ART}/ball_{k:02d}.png:4".replace("\\", "/"))
    lines.append("SetAllDurations(70)")
    run_mkpx("ball.txt", lines, probes)


def build_palette():
    gpl = Path("app/assets/palettes/endesga-32.gpl").read_text(encoding="utf-8")
    colors = []
    for line in gpl.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0].lstrip("-").isdigit():
            r, g, b = (int(p) for p in parts[:3])
            colors.append(f"#{r:02X}{g:02X}{b:02X}FF")
    rng = random.Random(4080)
    shuffled = colors[:]
    rng.shuffle(shuffled)
    lines = ["NewDocument(16, 16)", "ClearPalette()"]
    lines += [f"AddPaletteColor({c})" for c in shuffled]
    lines.append("SortPalette()")
    out = run_mkpx("palette_sort.txt", lines, ["state"])
    state = json.loads(out.splitlines()[-1])
    (ART / "palette_sort.json").write_text(json.dumps({
        "shuffled": shuffled, "sorted": state["palette"],
    }, indent=1), encoding="utf-8")
    print(f"# palette: {len(shuffled)} colors shuffled -> engine-sorted")


def build_aa():
    """The same line-and-curve figure with AA off vs on (ADR 0008 edges)."""
    figure = [
        "SelectTool(Line)", "SetLineWidth(2)", "SetPrimaryColor(#78B0E8FF)",
        "Stroke([(3,40),(44,9)])",
        "SetPrimaryColor(#F0A050FF)",
        "Stroke([(4,44),(45,30)])",
        "SelectTool(Ellipse)", "SetShapeFill(false)", "SetLineWidth(2)",
        "SetPrimaryColor(#E8F4FFFF)",
        "Stroke([(14,6),(38,30)])",
    ]
    for name, aa in [("aa_off", "false"), ("aa_on", "true")]:
        lines = ["NewDocument(48, 48)", f"SetAA({aa})"] + figure
        run_mkpx(f"{name}.txt", lines, [f"render:0:{ART}/{name}.png:8".replace("\\", "/")])


def build_airbrush():
    """One sweeping stroke per airbrush variant: Dots, Soft, Mist."""
    path = []
    for i in range(72):
        t = i / 71
        x = 4 + t * 56
        y = 16 + 9 * math.sin(t * math.pi * 1.6 + 0.4)
        path.append(f"({int(x)},{int(y)})")
    stroke = f"Stroke([{','.join(path)}])"
    for name, tool, passes in [("air_dots", "Airbrush", 1), ("air_soft", "AirbrushSoft", 1),
                               ("air_mist", "AirbrushMist", 4)]:
        lines = [
            "NewDocument(64, 32)",
            f"SelectTool({tool})", "SetBrushSize(7)",
            "SetPrimaryColor(#78B0E8FF)",
        ] + [stroke] * passes
        run_mkpx(f"{name}.txt", lines, [f"render:0:{ART}/{name}.png:8".replace("\\", "/")])


def build_gradient8():
    """An 8-stop linear gradient ramp, engine-blended."""
    stops = ["#20244CFF@0", "#4040A0FF@0.14", "#7050C8FF@0.28", "#C050B0FF@0.43",
             "#E86840FF@0.57", "#F0A050FF@0.71", "#F8D890FF@0.86", "#F6EEDEFF@1"]
    lines = [
        "NewDocument(64, 20)",
        "SelectTool(Gradient)", "SetGradientType(Linear)",
        f"SetGradientStops([{', '.join(stops)}])",
        "Stroke([(0,10),(63,10)])",
    ]
    run_mkpx("gradient8.txt", lines, [f"render:0:{ART}/gradient8.png:8".replace("\\", "/")])


def build_coat():
    """Single-coat strokes (ADR 0007): one self-crossing 55%-alpha figure-eight
    stroke lays one flat coat even where it crosses itself; the same figure as two
    separate strokes stacks a second coat at the crossing."""
    def fig8(t):
        return (int(24 + 19 * math.sin(t)), int(24 + 12 * math.sin(2 * t)))
    n = 96
    pts = [fig8(i / n * 2 * math.pi) for i in range(n + 1)]
    fmt = lambda ps: f"Stroke([{','.join(f'({x},{y})' for x, y in ps)}])"
    setup = ["NewDocument(48, 48)", "SelectTool(Pencil)", "SetBrushSize(5)",
             "SetPixelPerfect(false)", "SetPrimaryColor(#78B0E88C)"]
    run_mkpx("coat_one.txt", setup + [fmt(pts)],
             [f"render:0:{ART}/coat_one.png:8".replace("\\", "/")])


def lakeside_stages():
    """A 64x64 lakeside dusk, authored in five stages for the replay filmstrip."""
    s1 = [
        "NewDocument(64, 64)",
        "SelectTool(Gradient)", "SetGradientType(Linear)",
        "SetGradientStops([#141C34FF@0, #3A2C50FF@0.38, #B4503CFF@0.62, #F0A050FF@0.85, #F8D890FF@1])",
        "Stroke([(32,0),(32,44)])",
    ]
    s2 = [
        "SelectTool(Ellipse)", "SetShapeFill(true)",
        "SetPrimaryColor(#F8E8B0FF)", "Stroke([(37,26),(49,38)])",
        "SetPrimaryColor(#FFF6D8FF)", "Stroke([(39,28),(47,36)])",
    ]
    px3 = {}
    far, near = "#2A2038FF", "#170F20FF"
    for x in range(64):
        h1 = 8 + 5 * math.sin(x * 0.19 + 1.1) + 2.5 * math.sin(x * 0.47)
        for y in range(int(44 - h1), 45):
            px3[(x, y)] = far
        h2 = 4 + 4 * math.sin(x * 0.15 + 4.2) + 2 * math.sin(x * 0.66 + 0.8)
        for y in range(int(45 - h2), 45):
            px3[(x, y)] = near
    s3 = []
    emit_pixels(s3, px3)
    s4 = [
        "SelectTool(SelectRect)", "Stroke([(0,45),(63,63)])",
        "SelectTool(Gradient)", "SetGradientType(Linear)",
        "SetGradientStops([#B4503CFF@0, #3A2C50FF@0.5, #141C34FF@1])",
        "Stroke([(32,45),(32,63)])",
        "ClearSelection()",
    ]
    px4 = {}
    for (rx0, rx1, ry) in [(36, 50, 47), (39, 47, 50), (34, 52, 53), (40, 46, 57), (37, 49, 61)]:
        for x in range(rx0, rx1):
            px4[(x, ry)] = "#F0B06CB4"
    emit_pixels(s4, px4)
    px5 = {}
    for sx, sy in [(6, 5), (17, 9), (29, 4), (45, 7), (57, 11), (38, 13), (11, 16), (52, 3),
                   (24, 7), (60, 8), (3, 12)]:
        px5[(sx, sy)] = "#F6F0E0FF"
    # birds silhouetted against the bright sky, near the sun
    for bx, by in [(20, 24), (28, 20), (13, 28)]:
        for dx in (-2, -1, 1, 2):
            px5[(bx + dx, by - (1 if abs(dx) == 2 else 0))] = "#221428FF"
    # sun glint: a bright broken column on the water below the sun
    for gx0, gx1, gy in [(41, 45, 46), (42, 44, 48), (40, 46, 51), (42, 44, 55), (41, 45, 59)]:
        for x in range(gx0, gx1 + 1):
            px5[(x, gy)] = "#F8E8B0E6"
    s5 = []
    emit_pixels(s5, px5)
    return [s1, s2, s3, s4, s5]


def build_replay():
    stages = lakeside_stages()
    for k in range(1, 6):
        lines = [ln for st in stages[:k] for ln in st]
        run_mkpx(f"replay_s{k}.txt", lines,
                 [f"render:0:{ART}/replay_s{k}.png:6".replace("\\", "/")])


ASSETS = {
    "mushroom": build_mushroom, "ghost": build_ghost, "rotate": build_rotate,
    "scale": build_scale, "blend": build_blend, "levels": build_levels,
    "ball": build_ball, "palette": build_palette,
    "aa": build_aa, "airbrush": build_airbrush, "gradient8": build_gradient8,
    "coat": build_coat, "replay": build_replay,
}

if __name__ == "__main__":
    picks = sys.argv[1:] or list(ASSETS)
    for p in picks:
        ASSETS[p]()
