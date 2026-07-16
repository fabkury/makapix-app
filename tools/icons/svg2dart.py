# SVG -> Dart vector data converter for the Makapix custom icon set.
# Handles exactly the subset gen_icons.py emits: <path>, <rect rx>, <circle>,
# <ellipse>; stroke (2px, round caps/joins), fill, stroke-dasharray.
# Arcs become cubics; dashed strokes are flattened to explicit dash sub-paths,
# so the Dart painter only needs moveTo/lineTo/cubicTo/close + fill-vs-stroke.
import math
import re


# ------------------------------------------------------------ path parsing
_TOKEN = re.compile(r"[MmLlHhVvCcAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?")


def parse_path(d):
    """Return list of absolute commands: ('M',x,y) ('L',x,y) ('C',6 floats) ('Z',)."""
    toks = _TOKEN.findall(d)
    out, i = [], 0
    cx = cy = sx = sy = 0.0
    cmd = None
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
        elif cmd is None:
            raise ValueError("path starts without command")
        rel = cmd.islower()
        c = cmd.upper()

        def num(k):
            return float(toks[i + k])

        if c == "M":
            x, y = num(0), num(1)
            i += 2
            if rel:
                x, y = cx + x, cy + y
            out.append(("M", x, y))
            cx, cy, sx, sy = x, y, x, y
            cmd = "l" if rel else "L"          # implicit lineto after moveto
        elif c == "L":
            x, y = num(0), num(1)
            i += 2
            if rel:
                x, y = cx + x, cy + y
            out.append(("L", x, y))
            cx, cy = x, y
        elif c == "H":
            x = num(0)
            i += 1
            if rel:
                x = cx + x
            out.append(("L", x, cy))
            cx = x
        elif c == "V":
            y = num(0)
            i += 1
            if rel:
                y = cy + y
            out.append(("L", cx, y))
            cy = y
        elif c == "C":
            v = [num(k) for k in range(6)]
            i += 6
            if rel:
                v = [v[0] + cx, v[1] + cy, v[2] + cx, v[3] + cy, v[4] + cx, v[5] + cy]
            out.append(("C", *v))
            cx, cy = v[4], v[5]
        elif c == "A":
            rx, ry, rot, laf, swf, x, y = [num(k) for k in range(7)]
            i += 7
            if rel:
                x, y = cx + x, cy + y
            out.extend(arc_to_cubics(cx, cy, rx, ry, rot, int(laf), int(swf), x, y))
            cx, cy = x, y
        elif c == "Z":
            out.append(("Z",))
            cx, cy = sx, sy
        else:
            raise ValueError("unsupported command " + c)
    return out


def arc_to_cubics(x1, y1, rx, ry, rot_deg, laf, swf, x2, y2):
    """SVG endpoint arc -> list of ('C',...) commands (F.6.5 + <=90-degree splits)."""
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [("L", x2, y2)]
    phi = math.radians(rot_deg)
    cosp, sinp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p = cosp * dx + sinp * dy
    y1p = -sinp * dx + cosp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p**2 / rx**2 + y1p**2 / ry**2
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx**2 * ry**2 - rx**2 * y1p**2 - ry**2 * x1p**2
    den = rx**2 * y1p**2 + ry**2 * x1p**2
    co = math.sqrt(max(0.0, num / den))
    if laf == swf:
        co = -co
    cxp = co * rx * y1p / ry
    cyp = -co * ry * x1p / rx
    cx = cosp * cxp - sinp * cyp + (x1 + x2) / 2
    cy = sinp * cxp + cosp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        d = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1, min(1, (ux * vx + uy * vy) / d)))
        return -a if ux * vy - uy * vx < 0 else a

    th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if swf == 0 and dth > 0:
        dth -= 2 * math.pi
    elif swf == 1 and dth < 0:
        dth += 2 * math.pi

    nseg = max(1, math.ceil(abs(dth) / (math.pi / 2)))
    out = []
    for k in range(nseg):
        a0 = th1 + dth * k / nseg
        a1 = th1 + dth * (k + 1) / nseg
        d = (a1 - a0) / 2
        kap = 4 / 3 * math.tan(d / 2)

        def pt(a):
            return (cx + rx * math.cos(a) * cosp - ry * math.sin(a) * sinp,
                    cy + rx * math.cos(a) * sinp + ry * math.sin(a) * cosp)

        def tan_(a):
            return (-rx * math.sin(a) * cosp - ry * math.cos(a) * sinp,
                    -rx * math.sin(a) * sinp + ry * math.cos(a) * cosp)

        p0, p3 = pt(a0), pt(a1)
        t0, t3 = tan_(a0), tan_(a1)
        out.append(("C", p0[0] + kap * t0[0], p0[1] + kap * t0[1],
                    p3[0] - kap * t3[0], p3[1] - kap * t3[1], p3[0], p3[1]))
    return out


# ------------------------------------------------------- element -> commands
def rect_cmds(x, y, w, h, rx):
    if rx <= 0:
        return [("M", x, y), ("L", x + w, y), ("L", x + w, y + h),
                ("L", x, y + h), ("Z",)]
    k = 0.5522847498 * rx  # cubic control offset along the tangent
    out = [("M", x + rx, y), ("L", x + w - rx, y),
           ("C", x + w - rx + k, y, x + w, y + rx - k, x + w, y + rx),
           ("L", x + w, y + h - rx),
           ("C", x + w, y + h - rx + k, x + w - rx + k, y + h, x + w - rx, y + h),
           ("L", x + rx, y + h),
           ("C", x + rx - k, y + h, x, y + h - rx + k, x, y + h - rx),
           ("L", x, y + rx),
           ("C", x, y + rx - k, x + rx - k, y, x + rx, y), ("Z",)]
    return out


def ellipse_cmds(cx, cy, rx, ry):
    k = 0.5522847498
    return [("M", cx + rx, cy),
            ("C", cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry),
            ("C", cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy),
            ("C", cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry),
            ("C", cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy),
            ("Z",)]


# --------------------------------------------------------- dash flattening
def _flatten(cmds, step=0.12):
    """Commands -> list of polylines (list of (x,y)), one per subpath, with
    a parallel flag: closed or not."""
    polys, cur, closed = [], [], False
    px = py = None
    for c in cmds:
        if c[0] == "M":
            if cur:
                polys.append((cur, False))
            cur = [(c[1], c[2])]
            px, py = c[1], c[2]
        elif c[0] == "L":
            n = max(1, math.ceil(math.hypot(c[1] - px, c[2] - py) / step))
            for k in range(1, n + 1):
                cur.append((px + (c[1] - px) * k / n, py + (c[2] - py) * k / n))
            px, py = c[1], c[2]
        elif c[0] == "C":
            x1, y1, x2, y2, x3, y3 = c[1:]
            approx = (math.hypot(x1 - px, y1 - py) + math.hypot(x2 - x1, y2 - y1)
                      + math.hypot(x3 - x2, y3 - y2))
            n = max(4, math.ceil(approx / step))
            for k in range(1, n + 1):
                t = k / n
                mt = 1 - t
                cur.append((mt**3 * px + 3 * mt**2 * t * x1 + 3 * mt * t**2 * x2 + t**3 * x3,
                            mt**3 * py + 3 * mt**2 * t * y1 + 3 * mt * t**2 * y2 + t**3 * y3))
            px, py = x3, y3
        elif c[0] == "Z":
            if cur:
                x0, y0 = cur[0]
                n = max(1, math.ceil(math.hypot(x0 - px, y0 - py) / step))
                for k in range(1, n + 1):
                    cur.append((px + (x0 - px) * k / n, py + (y0 - py) * k / n))
                polys.append((cur, True))
                px, py = x0, y0
            cur = []
    if cur:
        polys.append((cur, False))
    return polys


def _rdp(pts, eps=0.03):
    if len(pts) < 3:
        return pts
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        px, py = pts[i]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / L if L else math.hypot(px - x0, py - y0)
        if d > dmax:
            dmax, idx = d, i
    if dmax <= eps:
        return [pts[0], pts[-1]]
    a = _rdp(pts[:idx + 1], eps)
    b = _rdp(pts[idx:], eps)
    return a[:-1] + b


def dash_cmds(cmds, on, off):
    """Flatten dashed stroke commands into explicit dash polyline commands."""
    out = []
    for pts, _closed in _flatten(cmds):
        # cumulative arclength
        acc = [0.0]
        for i in range(1, len(pts)):
            acc.append(acc[-1] + math.hypot(pts[i][0] - pts[i - 1][0],
                                            pts[i][1] - pts[i - 1][1]))
        total = acc[-1]

        def point_at(s):
            lo, hi = 0, len(acc) - 1
            while lo < hi:
                mid = (lo + hi) // 2
                if acc[mid] < s:
                    lo = mid + 1
                else:
                    hi = mid
            i = max(1, lo)
            seg = acc[i] - acc[i - 1]
            t = 0 if seg == 0 else (s - acc[i - 1]) / seg
            return (pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * t,
                    pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t)

        s = 0.0
        while s < total - 1e-6:
            e = min(s + on, total)
            run = [point_at(s)]
            run += [p for a, p in zip(acc, pts) if s < a < e]
            run.append(point_at(e))
            run = _rdp(run)
            out.append(("M", *run[0]))
            out.extend(("L", x, y) for x, y in run[1:])
            s += on + off
    return out


# ------------------------------------------------------------- svg parsing
_ELEM = re.compile(r"<(path|rect|circle|ellipse)\b([^/>]*)/?>")
_ATTR = re.compile(r'([\w-]+)="([^"]*)"')


def svg_to_segs(body):
    """SVG body markup -> list of (fill: bool, cmds) with dashes flattened."""
    segs = []
    for m in _ELEM.finditer(body):
        tag, raw = m.group(1), m.group(2)
        at = dict(_ATTR.findall(raw))
        fill = at.get("fill") == "currentColor" and at.get("stroke", "none") == "none"
        if tag == "path":
            cmds = parse_path(at["d"])
        elif tag == "rect":
            cmds = rect_cmds(float(at["x"]), float(at["y"]), float(at["width"]),
                             float(at["height"]), float(at.get("rx", 0)))
        elif tag == "circle":
            r = float(at["r"])
            cmds = ellipse_cmds(float(at["cx"]), float(at["cy"]), r, r)
        else:  # ellipse
            cmds = ellipse_cmds(float(at["cx"]), float(at["cy"]),
                                float(at["rx"]), float(at["ry"]))
        dash = at.get("stroke-dasharray")
        if dash and not fill:
            on, off = [float(v) for v in re.split(r"[ ,]+", dash.strip())]
            cmds = dash_cmds(cmds, on, off)
        segs.append((fill, cmds))
    return segs


# ---------------------------------------------------------------- emitters
def _fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def segs_to_svg(segs):
    """Re-serialize converted segs to SVG (verification roundtrip)."""
    parts = []
    for fill, cmds in segs:
        d = ""
        for c in cmds:
            d += c[0] if c[0] == "Z" else c[0] + " ".join(_fmt(v) for v in c[1:])
        style = ('fill="currentColor" stroke="none"' if fill else
                 'fill="none" stroke="currentColor" stroke-width="2" '
                 'stroke-linecap="round" stroke-linejoin="round"')
        parts.append(f'<path {style} d="{d}"/>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            + "".join(parts) + "</svg>")


OP = {"M": 0, "L": 1, "C": 2, "Z": 3}


def segs_to_dart(name, segs):
    body = []
    for fill, cmds in segs:
        ops = []
        for c in cmds:
            ops.append(str(OP[c[0]]))
            ops.extend(_fmt(v) for v in c[1:])
        body.append(f"    MpxSeg({'true' if fill else 'false'}, [{', '.join(ops)}]),")
    return (f"  static const {name} = MpxIcon._([\n" + "\n".join(body) + "\n  ]);")
