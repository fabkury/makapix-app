# Makapix custom icon generator: 28 row-3 tool icons in two styles.
#   pixel  : 16x16 hard-pixel grids -> SVG rects (crispEdges)
#   smooth : 24x24 rounded 2px-stroke outline icons (hand-authored paths)
# Outputs: pixel/*.svg, smooth/*.svg, pixel_proof.txt (ASCII), contact_sheet.html
import os

HERE = os.path.dirname(os.path.abspath(__file__))
N = 16  # pixel grid size


# ---------------------------------------------------------------- pixel grid
class G:
    def __init__(self):
        self.c = set()

    def px(self, x, y, on=True):
        if 0 <= x < N and 0 <= y < N:
            (self.c.add if on else self.c.discard)((x, y))

    def rect(self, x0, y0, x1, y1, on=True):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, on)

    def box(self, x0, y0, x1, y1):
        for x in range(x0, x1 + 1):
            self.px(x, y0); self.px(x, y1)
        for y in range(y0, y1 + 1):
            self.px(x0, y); self.px(x1, y)

    def hline(self, x0, x1, y, on=True):
        for x in range(x0, x1 + 1):
            self.px(x, y, on)

    def vline(self, x, y0, y1, on=True):
        for y in range(y0, y1 + 1):
            self.px(x, y, on)

    def line(self, x0, y0, x1, y1):  # bresenham
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        e = dx + dy
        while True:
            self.px(x0, y0)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * e
            if e2 >= dy:
                e += dy; x0 += sx
            if e2 <= dx:
                e += dx; y0 += sy

    def disc(self, cx, cy, r, on=True):
        for y in range(N):
            for x in range(N):
                if (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2 <= r * r:
                    self.px(x, y, on)

    def ring(self, cx, cy, r_out, r_in):
        for y in range(N):
            for x in range(N):
                d2 = (x + .5 - cx) ** 2 + (y + .5 - cy) ** 2
                if r_in * r_in < d2 <= r_out * r_out:
                    self.px(x, y)

    def dashed_box(self, x0, y0, x1, y1, on=2, off=1):
        path = []
        path += [(x, y0) for x in range(x0, x1 + 1)]
        path += [(x1, y) for y in range(y0 + 1, y1 + 1)]
        path += [(x, y1) for x in range(x1 - 1, x0 - 1, -1)]
        path += [(x0, y) for y in range(y1 - 1, y0, -1)]
        per = on + off
        for i, (x, y) in enumerate(path):
            if i % per < on:
                self.px(x, y)

    def ascii(self):
        return "\n".join(
            "".join("#" if (x, y) in self.c else "." for x in range(N))
            for y in range(N))

    def svg(self):
        # merge horizontal runs per row into path subrects
        parts = []
        for y in range(N):
            x = 0
            while x < N:
                if (x, y) in self.c:
                    x2 = x
                    while (x2 + 1, y) in self.c:
                        x2 += 1
                    parts.append(f"M{x} {y}h{x2 - x + 1}v1h-{x2 - x + 1}z")
                    x = x2 + 1
                else:
                    x += 1
        d = "".join(parts)
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {N} {N}" '
                f'shape-rendering="crispEdges"><path fill="currentColor" d="{d}"/></svg>')


# diagonal helper: u = x - y (along NE/SW), w = x + y (anti-diagonal band)
def diag(g, u_range, w_range, skip=None):
    for u in u_range:
        for w in w_range:
            if (u + w) % 2:
                continue
            if skip and skip(u, w):
                continue
            g.px((u + w) // 2, (w - u) // 2)


# ------------------------------------------------------------- pixel designs
def rows(g, spec):
    for y, ss in spec.items():
        for a, b in (ss if isinstance(ss, list) else [ss]):
            g.hline(a, b, y)


def i_pencil(g):
    rows(g, {1: [(13, 14)], 2: [(11, 11), (14, 14)], 3: (10, 12), 4: (9, 12),
             5: (8, 11), 6: (7, 10), 7: (6, 9), 8: (5, 8), 9: (4, 7),
             10: (4, 6), 11: (3, 4), 12: (2, 3), 13: (2, 2)})


def i_brush(g):
    rows(g, {1: (13, 13), 2: (12, 12), 3: (11, 11), 4: (10, 10),   # 1px handle
             5: (9, 10), 6: (8, 9),                                # ferrule
             7: (6, 9), 8: (5, 9), 9: (4, 8), 10: (4, 7),          # bristles
             11: (3, 6), 12: (2, 4), 13: (2, 3)})
    g.px(1, 14)                                       # bristle flick


def i_airbrush(g):
    g.rect(1, 6, 4, 9)                                # nozzle body
    g.px(5, 7); g.px(5, 8)                            # tip
    for x, y in [(7, 6), (7, 9), (9, 4), (9, 8), (9, 11), (11, 2), (11, 6),
                 (11, 10), (11, 13), (13, 4), (13, 8), (13, 12), (14, 1),
                 (14, 14), (15, 6), (15, 10)]:
        g.px(x, y)


def i_eraser(g):
    rows(g, {2: (7, 11), 3: (6, 12), 4: (5, 12), 5: (4, 11), 6: (3, 10),
             7: (3, 9), 8: (4, 8)})
    for x, y in [(7, 2), (8, 3), (9, 4), (10, 5)]:    # sleeve split
        g.px(x, y, False)
    g.hline(2, 3, 11); g.hline(5, 6, 11); g.hline(8, 9, 11)  # swipe marks


def i_fill(g):
    # tilted bucket silhouette, pour tip at right, drop below
    rows = {3: (3, 4), 4: (3, 6), 5: (3, 8), 6: (4, 10), 7: (4, 12),
            8: (5, 11), 9: (5, 10), 10: (6, 9), 11: (6, 8), 12: (7, 8)}
    for y, (a, b) in rows.items():
        g.hline(a, b, y)
    g.px(13, 9)                                       # drop
    g.hline(12, 14, 10); g.hline(12, 14, 11)
    g.px(13, 12)


def i_gradient(g):
    for y in range(2, 14):
        for x in range(2, 14):
            if y >= 12:
                on = True                              # solid
            elif y >= 10:
                on = (x + 2 * y) % 4 != 3              # 75%
            elif y >= 8:
                on = (x + y) % 2 == 0                  # 50%
            elif y >= 6:
                on = (x + 2 * y) % 4 == 0              # 25%
            elif y >= 4:
                on = (x + 2 * y) % 8 == 0              # 12.5%
            else:
                on = (x, y) in ((4, 2), (10, 2), (7, 3), (13, 3))
            if on:
                g.px(x, y)


def i_line(g):
    for x in range(4, 12):                            # 2px 45-degree line
        g.px(x, 15 - x)
        g.px(x + 1, 15 - x)
    g.rect(1, 12, 3, 14)                              # endpoint handles
    g.rect(12, 1, 14, 3)


def i_shape(g):
    rows(g, {1: [(7, 8)], 2: [(6, 6), (9, 9)], 3: [(5, 5), (10, 10)],
             4: [(4, 4), (11, 11)], 5: [(3, 3), (12, 12)], 6: (3, 12)})
    g.box(1, 9, 6, 14)                                # square
    rows(g, {9: [(11, 12)], 10: [(10, 10), (13, 13)],       # circle
             11: [(9, 9), (14, 14)], 12: [(9, 9), (14, 14)],
             13: [(10, 10), (13, 13)], 14: [(11, 12)]})


def i_ruler(g):
    g.box(1, 5, 14, 10)
    for i, x in enumerate(range(3, 13, 2)):
        g.vline(x, 6, 8 if i % 2 == 0 else 7)


def i_dodge(g):
    g.disc(8, 8, 3.4)                                 # sun core
    g.vline(7, 1, 2); g.vline(8, 1, 2)                # N ray
    g.vline(7, 13, 14); g.vline(8, 13, 14)            # S
    g.hline(1, 2, 7); g.hline(1, 2, 8)                # W
    g.hline(13, 14, 7); g.hline(13, 14, 8)            # E
    for x, y in [(3, 3), (2, 2), (12, 3), (13, 2), (3, 12), (2, 13),
                 (12, 12), (13, 13)]:
        g.px(x, y)


def i_burn(g):
    rows(g, {2: (6, 7), 3: (4, 6), 4: (3, 5), 5: (3, 4), 6: (2, 4),
             7: (2, 4), 8: (2, 5), 9: (2, 6), 10: [(3, 9), (12, 12)],
             11: (3, 12), 12: (4, 11), 13: (6, 9)})   # crescent, horns NE
    g.px(13, 1); g.px(12, 2); g.px(13, 2)             # sparkle star
    g.px(14, 2); g.px(13, 3)


def i_pick(g):
    rows(g, {1: (10, 12), 2: (9, 13), 3: (9, 13), 4: (9, 13), 5: (10, 12)})
    rows(g, {6: (7, 10), 7: (7, 8), 8: (6, 7), 9: (5, 6), 10: (4, 5),
             11: (3, 4), 12: (2, 3)})                 # shaft (collar at y6)
    g.px(1, 14)                                       # drop


def i_move(g):
    g.hline(7, 8, 1); g.hline(6, 9, 2); g.hline(5, 10, 3)     # N head
    g.hline(7, 8, 14); g.hline(6, 9, 13); g.hline(5, 10, 12)  # S head
    g.vline(1, 7, 8); g.vline(2, 6, 9); g.vline(3, 5, 10)     # W head
    g.vline(14, 7, 8); g.vline(13, 6, 9); g.vline(12, 5, 10)  # E head
    g.rect(7, 4, 8, 11)                                        # arms
    g.rect(4, 7, 11, 8)


def i_copy(g):
    g.box(2, 1, 9, 10)                                # back page
    g.rect(5, 4, 15, 15, on=False)                    # knockout + gap
    g.box(6, 5, 13, 14)                               # front page


def i_select(g):
    # marching-ants rect: 2px corner Ls + one 4px dash per edge centre
    for cx, cy, dx, dy in [(2, 3, 1, 1), (13, 3, -1, 1),
                           (2, 12, 1, -1), (13, 12, -1, -1)]:
        g.px(cx, cy); g.px(cx + dx, cy); g.px(cx, cy + dy)
    g.hline(6, 9, 3); g.hline(6, 9, 12)               # edge dashes
    g.vline(2, 6, 9); g.vline(13, 6, 9)


def i_lasso(g):
    spans = {2: [(6, 9)], 3: [(4, 5), (10, 11)], 4: [(3, 3), (12, 12)],
             5: [(2, 2), (13, 13)], 6: [(2, 2), (13, 13)], 7: [(2, 2), (13, 13)],
             8: [(3, 3), (12, 12)], 9: [(4, 5), (10, 11)], 10: [(6, 9)]}
    for y, ss in spans.items():
        for a, b in ss:
            g.hline(a, b, y)
    g.rect(9, 10, 10, 11)                             # knot
    for x, y in [(8, 12), (7, 12), (6, 13), (5, 13), (4, 14), (3, 14)]:
        g.px(x, y)                                    # tail


def i_selcolor(g):
    diag(g, range(-8, 2), (15, 16))                   # wand shaft
    g.vline(11, 1, 7)                                 # 4-point star
    g.hline(8, 14, 4)
    g.px(10, 3); g.px(12, 3); g.px(10, 5); g.px(12, 5)
    g.px(7, 1); g.px(14, 8)                           # sparkle dots


def i_sellyr(g):
    # solid iso diamond (the layer) + dashed chevron beneath (selection)
    rows(g, {3: (7, 8), 4: (5, 10), 5: (3, 12), 6: (5, 10), 7: (7, 8)})
    rows(g, {9: [(3, 4), (11, 12)], 10: [(5, 6), (9, 10)], 11: (7, 8)})


def i_hsv(g):
    g.disc(7.5, 8, 6.2)                               # palette body
    g.disc(15, 9.5, 3.2, on=False)                    # thumb bite
    for x, y in [(3, 6), (6, 3), (9, 4), (3, 10)]:    # paint holes
        g.rect(x, y, x + 1, y + 1, on=False)


def i_bright(g):
    g.disc(7.5, 7.5, 5.8)
    g.rect(8, 1, 15, 14, on=False)                    # clear right half
    g.ring(7.5, 7.5, 5.8, 4.6)                        # full outline


def i_flip(g):
    for y in range(1, 15):                            # dashed axis
        if y % 3 != 0:
            g.vline(7, y, y); g.vline(8, y, y)
    for i in range(5):                                # left solid triangle
        g.vline(1 + i, 3 + i, 12 - i)
    g.vline(14, 3, 12)                                # right outline triangle
    for x, y in [(13, 4), (13, 11), (12, 5), (12, 10), (11, 6), (11, 9),
                 (10, 7), (10, 8)]:
        g.px(x, y)


def i_rotate(g):
    import math
    for y in range(N):
        for x in range(N):
            d2 = (x + .5 - 8) ** 2 + (y + .5 - 8) ** 2
            if 4.6 ** 2 < d2 <= 5.9 ** 2:
                a = math.degrees(math.atan2(y + .5 - 8, x + .5 - 8))
                if not (-85 < a < -20):               # gap top-right
                    g.px(x, y)
    g.hline(9, 13, 2); g.hline(9, 11, 1); g.hline(9, 11, 3)   # cw arrowhead
    g.rect(6, 6, 9, 9)                                # object square


def i_resize(g):
    g.hline(1, 5, 14); g.vline(1, 10, 14)             # small bracket (SW)
    g.hline(10, 14, 1); g.vline(14, 1, 5)             # large bracket (NE)
    for i in range(6):                                # shaft
        g.px(5 + i, 10 - i)
    g.hline(8, 10, 5); g.vline(10, 5, 7)              # NE head
    g.hline(5, 7, 10); g.vline(5, 8, 10)              # SW head


def i_invert(g):
    g.rect(2, 2, 7, 7)                                # TL solid
    g.rect(8, 8, 13, 13)                              # BR solid
    g.box(8, 2, 13, 7)                                # TR outline
    g.box(2, 8, 7, 13)                                # BL outline


def i_play(g):
    for i, (y0, y1) in enumerate([(3, 12), (4, 11), (5, 10), (6, 9), (7, 8)]):
        g.vline(4 + 2 * i, y0, y1)
        g.vline(5 + 2 * i, y0, y1)


def i_onion(g):
    g.hline(1, 2, 1); g.hline(4, 5, 1); g.hline(7, 8, 1)      # ghost top
    g.vline(1, 3, 4); g.vline(1, 6, 7)                        # ghost left
    g.box(6, 6, 14, 14)                               # current frame
    g.rect(9, 9, 11, 11)                              # content blob


def i_undo(g):
    for y in range(N):
        for x in range(N):
            d2 = (x + .5 - 8) ** 2 + (y + .5 - 9) ** 2
            if 3.8 ** 2 <= d2 <= 5.4 ** 2 and y <= 9:
                g.px(x, y)
    g.rect(12, 10, 13, 11)                            # right tail down
    g.hline(1, 5, 10); g.hline(2, 4, 11); g.px(3, 12) # left head (down)


def i_redo(g):
    t = G(); i_undo(t)
    for (x, y) in t.c:
        g.px(N - 1 - x, y)


# --------------------------------------------------------------- smooth 24px
S = {}
S["pencil"] = '''<path d="M4.5 19.5l1-4.5L16 4.5a2.12 2.12 0 0 1 3 3L8.5 18l-4 1.5Z"/><path d="M13.8 6.7l3.5 3.5"/>'''
S["brush"] = '''<path d="M20 4l-6.8 6.8"/><path d="M13.6 10.2c1.3 1.3 1.6 3.2.8 5-.9 2.1-3 3.6-5.4 4.3-2 .6-4.1.6-5.7 0 1.3-1.2 1.5-2.5 1.7-3.9.3-2.2 1.5-4.2 3.6-5.2 1.7-.8 3.7-.5 5 .8Z"/>'''
S["airbrush"] = ('<rect x="2.5" y="8.8" width="5.6" height="6.4" rx="1.6"/><path d="M8.1 12h1.6"/>'
                 + "".join(f'<circle cx="{x}" cy="{y}" r="1.05" fill="currentColor" stroke="none"/>'
                           for x, y in [(12.6, 9.4), (12.6, 14.6), (15.2, 6.8), (15.2, 12), (15.2, 17.2),
                                        (18, 9.2), (18, 14.8), (20.4, 4.6), (20.4, 12), (20.4, 19.4)]))
S["eraser"] = '''<path d="M13.2 4.3 19.7 10.8a1.9 1.9 0 0 1 0 2.7L14.5 18.7H10L4.3 13a1.9 1.9 0 0 1 0-2.7l6.2-6a1.9 1.9 0 0 1 2.7 0Z"/><path d="M7.6 7.7l6.9 6.9"/><path d="M10.5 21.2h10"/>'''
S["fill"] = '''<path d="M11 3.5l8 8-6.9 6.3a3.3 3.3 0 0 1-4.4 0L4 14.2 11 3.5Z"/><path d="M5.6 12.2h11.7"/><path fill="currentColor" stroke="none" d="M20.3 15.2c1.1 1.6 1.8 2.7 1.8 3.7a1.95 1.95 0 1 1-3.9 0c0-1 .9-2.1 2.1-3.7Z"/>'''
S["gradient"] = '''<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/><path fill="currentColor" stroke="none" d="M4.6 14h14.8v3.9a2.6 2.6 0 0 1-2.6 2.6H7.2a2.6 2.6 0 0 1-2.6-2.6Z"/><path d="M7 11h10" stroke-dasharray="2.6 2.4"/><path d="M7.2 7.8h9.6" stroke-dasharray="0.1 3.4"/>'''
S["line"] = '''<path d="M6.6 17.4 17.4 6.6"/><circle cx="5.4" cy="18.6" r="1.9" fill="currentColor" stroke="none"/><circle cx="18.6" cy="5.4" r="1.9" fill="currentColor" stroke="none"/>'''
S["shape"] = '''<path d="M12 3.2 16.4 10.4H7.6Z"/><rect x="3.8" y="14" width="6.4" height="6.4" rx="1.3"/><circle cx="16.9" cy="17.2" r="3.4"/>'''
S["ruler"] = '''<path d="M3 15.8 15.8 3 21 8.2 8.2 21 3 15.8Z"/><path d="M7.4 14.6l1.9 1.9M10.9 11.1l1.9 1.9M14.4 7.6l1.9 1.9"/>'''
S["dodge"] = '''<circle cx="12" cy="12" r="4.1"/><path d="M12 2.6v2.6M12 18.8v2.6M2.6 12h2.6M18.8 12h2.6M5.4 5.4l1.8 1.8M16.8 16.8l1.8 1.8M18.6 5.4l-1.8 1.8M7.2 16.8l-1.8 1.8"/>'''
S["burn"] = '''<path d="M20.2 14.6A8.5 8.5 0 1 1 9.4 3.8 7 7 0 0 0 20.2 14.6Z"/><path d="M17.6 4.4v2.6M16.3 5.7h2.6"/>'''
S["pick"] = '''<path d="M14.2 6.8 5.8 15.2l-1 4 4-1 8.4-8.4"/><path d="M13.2 5.8l1.6-1.6a2.5 2.5 0 0 1 3.5 0l1.5 1.5a2.5 2.5 0 0 1 0 3.5l-1.6 1.6"/><path d="M14.2 6.8l3 3"/>'''
S["move"] = '''<path d="M12 3.4v17.2M3.4 12h17.2"/><path d="M9.3 6 12 3.3 14.7 6M9.3 18 12 20.7 14.7 18M6 9.3 3.3 12 6 14.7M18 9.3 20.7 12 18 14.7"/>'''
S["copy"] = '''<rect x="8.8" y="8.8" width="11.7" height="11.7" rx="2"/><path d="M15.2 4.6H6.6a2 2 0 0 0-2 2v8.6"/>'''
S["select"] = '''<rect x="4" y="5.5" width="16" height="13" rx="2" stroke-dasharray="3.1 2.7"/>'''
S["lasso"] = '''<ellipse cx="12" cy="9.6" rx="7.6" ry="5"/><circle cx="8.4" cy="13.9" r="1.5" fill="currentColor" stroke="none"/><path d="M8.2 15.4c-1.7 1.2-.2 2.7-2.4 4.3"/>'''
S["selcolor"] = '''<path d="M5.4 18.6 11.8 12.2"/><path fill="currentColor" stroke="none" d="M15.9 3l1.2 3.7L20.8 7.9l-3.7 1.2-1.2 3.7-1.2-3.7-3.7-1.2 3.7-1.2Z"/><circle cx="20" cy="14.2" r="1.05" fill="currentColor" stroke="none"/><circle cx="12.2" cy="4.4" r="1.05" fill="currentColor" stroke="none"/>'''
S["sellyr"] = '''<path stroke-dasharray="2.9 2.4" d="M12 3.4 21 8.7 12 14 3 8.7Z"/><path d="M4.4 13.4 12 17.9l7.6-4.5"/>'''
S["hsv"] = '''<path d="M12 3a9 9 0 0 0 0 18c1.5 0 2.4-1.2 1.9-2.5-.5-1.4.5-2.8 2-2.8h2a3.1 3.1 0 0 0 3.1-3.2C20.9 7.1 16.9 3 12 3Z"/>''' + "".join(
    f'<circle cx="{x}" cy="{y}" r="1.15" fill="currentColor" stroke="none"/>'
    for x, y in [(7.3, 9.2), (10.6, 6.6), (14.7, 7.2), (6.6, 13.4)])
S["bright"] = '''<circle cx="12" cy="12" r="7.6"/><path fill="currentColor" stroke="none" d="M12 5.2a6.8 6.8 0 0 0 0 13.6Z"/>'''
S["flip"] = '''<path stroke-dasharray="2.9 2.6" d="M12 2.8v18.4"/><path fill="currentColor" stroke="none" d="M3.5 6.6v10.8L9.2 12Z"/><path d="M20.5 6.6v10.8L14.8 12Z"/>'''
S["rotate"] = '''<rect x="8.7" y="8.7" width="6.6" height="6.6" rx="1.3"/><path d="M19.6 10A7.9 7.9 0 1 1 10 4.4"/><path fill="currentColor" stroke="none" d="M13.4 3.6 9.4 6.7 9 2.2Z"/>'''
S["resize"] = '''<path d="M3 13.8V21h7.2"/><path d="M21 10.2V3h-7.2"/><path d="M8.1 15.9 15.9 8.1"/><path d="M12.9 8.1h3v3M11.1 15.9h-3v-3"/>'''
S["invert"] = '''<rect x="3.5" y="3.5" width="7.6" height="7.6" rx="1.4" fill="currentColor" stroke="none"/><rect x="12.9" y="12.9" width="7.6" height="7.6" rx="1.4" fill="currentColor" stroke="none"/><rect x="12.9" y="3.5" width="7.6" height="7.6" rx="1.4"/><rect x="3.5" y="12.9" width="7.6" height="7.6" rx="1.4"/>'''
S["play"] = '''<path fill="currentColor" stroke="none" d="M7.8 5.6c0-1.5 1.6-2.4 2.9-1.6l9.6 6.4c1.2.8 1.2 2.4 0 3.2l-9.6 6.4c-1.3.8-2.9-.1-2.9-1.6Z"/>'''
S["onion"] = '''<path stroke-dasharray="2.9 2.4" d="M3.5 13.5v-8a2 2 0 0 1 2-2h8"/><rect x="8.5" y="8.5" width="12" height="12" rx="2"/><circle cx="14.5" cy="14.5" r="1.7" fill="currentColor" stroke="none"/>'''
S["undo"] = '''<path d="M8 5 4.5 8.5 8 12"/><path d="M4.5 8.5H14a5.25 5.25 0 0 1 0 10.5H9.5"/>'''
S["redo"] = '''<path d="M16 5 19.5 8.5 16 12"/><path d="M19.5 8.5H10a5.25 5.25 0 0 0 0 10.5h4.5"/>'''


# -------- round 2: alternative smooth designs for the 19 unapproved tools
APPROVED = ["pencil", "airbrush", "eraser", "fill", "line", "pick",
            "selcolor", "sellyr", "flip"]

V = {}
V["brush"] = [
    # flat brush: bristle wedge + ferrule band + thin handle
    '''<path d="M4 20c.8-3.6 1.6-5.8 3.6-7.8L9.9 9.9l4.2 4.2-2.3 2.3c-2 2-4.2 2.8-7.8 3.6Z"/><path d="M11.3 8.5l4.2 4.2"/><path d="M13.4 10.6l5.8-5.8"/>''',
    # round brush drawing a paint stroke
    '''<path d="M20.7 3.3l-4.9 4.9"/><path d="M15.6 8.4c1.5 1.1 1.9 3.2.8 4.8-1.2 1.7-3.5 2.1-5.1.9-1.7-1.2-2-3.4-.8-5.1 1.2-1.6 3.5-1.9 5.1-.6Z"/><path d="M3.5 20.5c3.6 1 6.8-1.2 6.3-4.6"/>''',
]
V["gradient"] = [
    # frame + diagonal solid wedge
    '''<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/><path fill="currentColor" stroke="none" d="M4.5 10.5 16.9 19.5H7.5a3 3 0 0 1-3-3Z"/>''',
    # frame + dot fade
    ('<rect x="3.5" y="3.5" width="17" height="17" rx="2.5"/>'
     + "".join(f'<circle cx="{x}" cy="16.3" r="1.5" fill="currentColor" stroke="none"/>' for x in (7.4, 12, 16.6))
     + "".join(f'<circle cx="{x}" cy="11.9" r=".95" fill="currentColor" stroke="none"/>' for x in (7.4, 12, 16.6))
     + "".join(f'<circle cx="{x}" cy="7.6" r=".5" fill="currentColor" stroke="none"/>' for x in (7.4, 12, 16.6))),
]
V["shape"] = [
    # big square + circle overlap
    '''<rect x="4" y="4" width="8.8" height="8.8" rx="1.5"/><circle cx="15.3" cy="15.3" r="5.2"/>''',
    # triangle + circle
    '''<path d="M8.4 3.8 13.9 13H3Z"/><circle cx="16" cy="15.2" r="5"/>''',
]
V["ruler"] = [
    # horizontal ruler
    '''<rect x="2.5" y="8.2" width="19" height="7.6" rx="1.6"/><path d="M6.9 8.2v3.1M11 8.2v4.6M15.1 8.2v3.1M19.2 8.2v4.6"/>''',
    # drafting set-square
    '''<path d="M4.5 20.5V6.4c0-1.6 1.9-2.4 3-1.3l12.4 12.3c1.1 1.1.3 3.1-1.3 3.1Z"/><path d="M8.8 16.5v-4.6l4.6 4.6Z"/>''',
]
V["dodge"] = [
    # chunky sun: thick cardinal rays + diagonal dots
    ('<circle cx="12" cy="12" r="4.6"/><path d="M12 2.5v3.2M12 18.3v3.2M2.5 12h3.2M18.3 12h3.2"/>'
     + "".join(f'<circle cx="{x}" cy="{y}" r="1.05" fill="currentColor" stroke="none"/>'
               for x, y in [(5.4, 5.4), (18.6, 5.4), (5.4, 18.6), (18.6, 18.6)])),
    # sun with solid core
    '''<circle cx="12" cy="12" r="2.6" fill="currentColor" stroke="none"/><path d="M12 3v3.4M12 17.6V21M3 12h3.4M17.6 12H21M5.6 5.6 8 8M16 16l2.4 2.4M18.4 5.6 16 8M8 16l-2.4 2.4"/>''',
]
V["burn"] = [
    # plain fat crescent
    '''<path d="M20.6 14.2A8.9 8.9 0 1 1 9.8 3.4 7.3 7.3 0 0 0 20.6 14.2Z"/>''',
    # filled crescent + star
    '''<path fill="currentColor" stroke="none" d="M20.6 14.2A8.9 8.9 0 1 1 9.8 3.4 7.3 7.3 0 0 0 20.6 14.2Z"/><path d="M17.8 4.2v2.4M16.6 5.4H19"/>''',
]
V["move"] = [
    # stroke arms + filled heads
    '''<path d="M12 4.6v14.8M4.6 12h14.8"/><path fill="currentColor" stroke="none" d="M12 1.6 9.4 4.9h5.2ZM12 22.4 9.4 19.1h5.2ZM1.6 12l3.3-2.6v5.2ZM22.4 12l-3.3-2.6v5.2Z"/>''',
    # grab dot + chevrons
    '''<circle cx="12" cy="12" r="2.1" fill="currentColor" stroke="none"/><path d="M9.6 5 12 2.6 14.4 5M9.6 19 12 21.4 14.4 19M5 9.6 2.6 12 5 14.4M19 9.6 21.4 12 19 14.4"/>''',
]
V["copy"] = [
    # pages with dog-ear fold
    '''<path d="M15 4.5H6.5a2 2 0 0 0-2 2V15"/><path d="M15.5 8.5h-4a2 2 0 0 0-2 2V19a2 2 0 0 0 2 2h7a2 2 0 0 0 2-2v-6Z"/><path d="M15.5 8.5V11a2 2 0 0 0 2 2h3"/>''',
    # solid front + outline back
    '''<rect x="9" y="9" width="11.5" height="11.5" rx="2" fill="currentColor" stroke="none"/><path d="M15 4.5H6.5a2 2 0 0 0-2 2V15"/>''',
]
V["select"] = [
    # dashed rect + corner handles
    ('<rect x="5" y="6.5" width="14" height="11" rx="1.5" stroke-dasharray="3 2.6"/>'
     + "".join(f'<rect x="{x}" y="{y}" width="2.6" height="2.6" rx=".6" fill="currentColor" stroke="none"/>'
               for x, y in [(3.7, 5.2), (17.7, 5.2), (3.7, 16.2), (17.7, 16.2)])),
    # bracket marquee corners
    '''<path d="M4 9V6.5A2.5 2.5 0 0 1 6.5 4H9M15 4h2.5A2.5 2.5 0 0 1 20 6.5V9M20 15v2.5a2.5 2.5 0 0 1-2.5 2.5H15M9 20H6.5A2.5 2.5 0 0 1 4 17.5V15"/>''',
]
V["lasso"] = [
    # dashed freeform blob
    '''<path stroke-dasharray="3 2.7" d="M11.9 4c4.7-.5 8.5 2 8.6 5.2.1 2.6-2.1 4.6-5 5.4-2.7.8-4.3 2.7-7 3.3-2.5.5-4.9-.7-5.3-3-.4-2.3 1.2-4.4 3.1-5.9 1.8-1.5 3.2-4.7 5.6-5Z"/>''',
    # rope loop + knot + curled tail
    '''<ellipse cx="12.2" cy="9.3" rx="7.4" ry="4.9"/><circle cx="7.7" cy="13.4" r="1.5" fill="currentColor" stroke="none"/><path d="M7.2 14.9c-2.3.9-3 2.6-1.6 3.7 1.2.9 2.8.3 2.6-1-.2-1.2-1.9-1.3-3.4-.7"/>''',
]
V["hsv"] = [
    # colour wheel: circle + 6 segment ticks + hub
    '''<circle cx="12" cy="12" r="7.6"/><path d="M12 8.8V4.4M14.8 10.4l3.8-2.2M14.8 13.6l3.8 2.2M12 15.2v4.4M9.2 13.6l-3.8 2.2M9.2 10.4 5.4 8.2"/><circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/>''',
    # three sliders with knobs (the HSV panel itself)
    ('<path d="M4.5 6.2h15M4.5 12h15M4.5 17.8h15"/>'
     + "".join(f'<circle cx="{x}" cy="{y}" r="2" fill="currentColor" stroke="none"/>'
               for x, y in [(14.8, 6.2), (8.3, 12), (12.4, 17.8)])),
]
V["bright"] = [
    # diagonal-split circle
    '''<circle cx="12" cy="12" r="7.5"/><path fill="currentColor" stroke="none" d="M6.7 17.3A7.5 7.5 0 0 0 17.3 6.7Z"/>''',
    # half-filled sun (brightness + contrast in one)
    '''<circle cx="12" cy="12" r="4.9"/><path fill="currentColor" stroke="none" d="M12 7.1a4.9 4.9 0 0 0 0 9.8Z"/><path d="M12 2.6v2.2M12 19.2v2.2M2.6 12h2.2M19.2 12h2.2M5.4 5.4 7 7M17 17l1.6 1.6M18.6 5.4 17 7M7 17l-1.6 1.6"/>''',
]
V["rotate"] = [
    # plain big arc + filled head (no square)
    '''<path d="M19.4 14A7.7 7.7 0 1 1 14 4.6"/><path fill="currentColor" stroke="none" d="M16.9 5.4 12.4 6.7l1.2-4.8Z"/>''',
    # dashed square (before) + arc + head
    '''<rect x="8.7" y="8.7" width="6.6" height="6.6" rx="1.3" stroke-dasharray="2.5 2.1"/><path d="M19.6 10A7.9 7.9 0 1 1 10 4.4"/><path fill="currentColor" stroke="none" d="M13.4 3.6 9.4 6.7 9 2.2Z"/>''',
]
V["resize"] = [
    # small solid square -> big outline square with NE arrow
    '''<rect x="9.5" y="3.5" width="11" height="11" rx="2"/><rect x="4" y="15.5" width="4.6" height="4.6" rx="1" fill="currentColor" stroke="none"/><path d="M7.9 16.1l3.6-3.6"/><path d="M8.4 12.5h3.2v3.2"/>''',
    # chunky double-headed diagonal arrow
    '''<path d="M6.8 17.2 17.2 6.8"/><path d="M12.4 6.4h4.9v4.9M11.6 17.6H6.7v-4.9"/>''',
]
V["invert"] = [
    # circle, lower-right half solid
    '''<circle cx="12" cy="12" r="7.5"/><path fill="currentColor" stroke="none" d="M17.3 6.7A7.5 7.5 0 0 1 6.7 17.3Z"/>''',
    # droplet, right half solid
    '''<path d="M12 3.4c3.5 4.2 5.9 7.4 5.9 10.3a5.9 5.9 0 1 1-11.8 0C6.1 10.8 8.5 7.6 12 3.4Z"/><path fill="currentColor" stroke="none" d="M12 3.4v16.2a5.9 5.9 0 0 0 5.9-5.9c0-2.9-2.4-6.1-5.9-10.3Z"/>''',
]
V["play"] = [
    # outline triangle
    '''<path d="M7.8 5.6c0-1.5 1.6-2.4 2.9-1.6l9.6 6.4c1.2.8 1.2 2.4 0 3.2l-9.6 6.4c-1.3.8-2.9-.1-2.9-1.6Z"/>''',
    # play + pause combined
    '''<path fill="currentColor" stroke="none" d="M4 6.1c0-1.5 1.6-2.4 2.9-1.6l7.3 4.7c1.2.8 1.2 2.8 0 3.6l-7.3 4.7c-1.3.8-2.9-.1-2.9-1.6Z"/><path d="M17.6 5.5v13M21 5.5v13"/>''',
]
V["onion"] = [
    # fuller dashed ghost frame behind
    '''<path stroke-dasharray="2.9 2.4" d="M13.5 3.5h-8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h1"/><rect x="8.5" y="8.5" width="12" height="12" rx="2"/><circle cx="14.5" cy="14.5" r="1.7" fill="currentColor" stroke="none"/>''',
    # side-by-side frames (previous frame ghost, left)
    '''<path stroke-dasharray="2.9 2.4" d="M9.5 6.5H5a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h4.5"/><rect x="9.5" y="4.5" width="11.5" height="15" rx="2"/><circle cx="15.2" cy="12" r="1.7" fill="currentColor" stroke="none"/>''',
]
V["undo"] = [
    # 260-degree circular arrow, head at top-left
    '''<path d="M11.5 5.3a7 7 0 1 0 7.8 7.9"/><path fill="currentColor" stroke="none" d="M9.1 5.4 12.2 7.3 12 3.3Z"/>''',
    # straight tail + filled head
    '''<path d="M7.7 8.5H14a5.25 5.25 0 0 1 0 10.5H9.5"/><path fill="currentColor" stroke="none" d="M3.4 8.5 8.2 4.6v7.8Z"/>''',
]
V["redo"] = [
    '''<path d="M12.5 5.3a7 7 0 1 1-7.8 7.9"/><path fill="currentColor" stroke="none" d="M14.9 5.4 11.8 7.3 12 3.3Z"/>''',
    '''<path d="M16.3 8.5H10a5.25 5.25 0 0 0 0 10.5h4.5"/><path fill="currentColor" stroke="none" d="M20.6 8.5 15.8 4.6v7.8Z"/>''',
]


def smooth_svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
            '<g fill="none" stroke="currentColor" stroke-width="2" '
            f'stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>')


# ------------------------------------------------------------------- catalog
TOOLS = [
    ("pencil", "Pencil", "Pencil", "edit"),
    ("brush", "Brush", "Brush", "brush"),
    ("airbrush", "Airbrush", "Airbrush", "blur_on"),
    ("eraser", "Eraser", "Eraser", "auto_fix_normal"),
    ("fill", "Fill", "Bucket", "format_color_fill"),
    ("gradient", "Gradient", "Gradient", "gradient"),
    ("line", "Line", "Line", "show_chart"),
    ("shape", "Shape", "Shape", "category_outlined"),
    ("ruler", "Ruler", "Ruler", "straighten"),
    ("dodge", "Dodge", "Dodge", "light_mode"),
    ("burn", "Burn", "Burn", "dark_mode"),
    ("pick", "Pick", "Eyedropper", "colorize"),
    ("move", "Move", "Move", "open_with"),
    ("copy", "Copy", "CopyPaste", "content_copy"),
    ("select", "Select", "SelectShape", "highlight_alt"),
    ("lasso", "Lasso", "SelectFree", "gesture"),
    ("selcolor", "Sel Color", "SelectByColor", "colorize_outlined"),
    ("sellyr", "Sel Lyr", "SelectLayer", "opacity"),
    ("hsv", "HSV", "HsvShift", "palette"),
    ("bright", "Bright", "BrightnessContrast", "brightness_6"),
    ("flip", "Flip", "Flip", "flip"),
    ("rotate", "Rotate", "Rotate", "rotate_90_degrees_cw"),
    ("resize", "Resize", "Resize", "aspect_ratio"),
    ("invert", "Invert", "Invert", "invert_colors"),
    ("play", "Play", "PlayPause", "play_arrow"),
    ("onion", "Onion", "Onion", "layers"),
    ("undo", "Undo", "Undo", "undo"),
    ("redo", "Redo", "Redo", "redo"),
]

PIXEL_FN = {k: v for k, v in globals().items() if k.startswith("i_")}


def build():
    proof = []
    pixel_svgs, smooth_svgs, material_svgs = {}, {}, {}
    for d in ("pixel", "smooth"):
        os.makedirs(os.path.join(HERE, d), exist_ok=True)
    for key, label, dsl, mat in TOOLS:
        g = G()
        PIXEL_FN["i_" + key](g)
        proof.append(f"=== {label} ({dsl})\n{g.ascii()}\n")
        pixel_svgs[key] = g.svg()
        smooth_svgs[key] = smooth_svg(S[key])
        try:
            # Material reference glyphs for the contact sheets; fetch with e.g.
            # curl https://cdn.jsdelivr.net/npm/@material-design-icons/svg/filled/<name>.svg
            with open(os.path.join(HERE, "material", mat + ".svg"), encoding="utf-8") as f:
                m = f.read()
        except FileNotFoundError:
            m = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"/>'
        material_svgs[key] = m.replace('height="24"', "").replace('width="24"', "")
        with open(os.path.join(HERE, "pixel", key + ".svg"), "w", encoding="utf-8") as f:
            f.write(pixel_svgs[key])
        with open(os.path.join(HERE, "smooth", key + ".svg"), "w", encoding="utf-8") as f:
            f.write(smooth_svgs[key])
    with open(os.path.join(HERE, "pixel_proof.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(proof))
    return pixel_svgs, smooth_svgs, material_svgs


def sz(svg_str, px):
    return f'<span class="ic" style="width:{px}px;height:{px}px">{svg_str}</span>'


def build_html(px_svgs, sm_svgs, mat_svgs):
    def strip(svgs, cls):
        inner = "".join(sz(svgs[k], 18) for k, *_ in TOOLS)
        return f'<div class="bar {cls}">{inner}</div>'

    bars = ""
    for title, svgs in [("Current (Material)", mat_svgs),
                        ("Option A — Pixel-grid", px_svgs),
                        ("Option B — Smooth", sm_svgs)]:
        bars += (f'<h3>{title}</h3>'
                 f'{strip(svgs, "light")}{strip(svgs, "dark")}')

    rowhtml = ""
    for key, label, dsl, _ in TOOLS:
        p, s, m = px_svgs[key], sm_svgs[key], mat_svgs[key]
        rowhtml += f'''<tr>
<th><b>{label}</b><small>{dsl}</small></th>
<td><div class="chip light">{sz(m, 24)}</div></td>
<td><div class="chip light">{sz(p, 18)}{sz(p, 32)}{sz(p, 48)}</div>
    <div class="chip dark">{sz(p, 18)}{sz(p, 32)}{sz(p, 48)}</div></td>
<td><div class="chip light">{sz(s, 18)}{sz(s, 32)}{sz(s, 48)}</div>
    <div class="chip dark">{sz(s, 18)}{sz(s, 32)}{sz(s, 48)}</div></td>
</tr>'''

    html = f'''<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Makapix row-3 tool icons — contact sheet</title>
<style>
 body {{ font: 15px/1.5 system-ui, sans-serif; margin: 24px auto; max-width: 1060px;
        padding: 0 16px; background:#fbfbfd; color:#1b1b22; }}
 h1 {{ font-size: 1.5em; margin-bottom:.2em }}
 h3 {{ margin: 1.2em 0 .35em }}
 .note {{ color:#555; max-width: 72ch }}
 .ic {{ display:inline-flex; align-items:center; justify-content:center; }}
 .ic svg {{ width:100%; height:100% }}
 .bar {{ display:flex; flex-wrap:wrap; gap:14px; padding:10px 14px; border-radius:10px;
        margin:6px 0; align-items:center }}
 .light {{ background:#f2f2f5; color:#2a2a33; border:1px solid #e0e0e6 }}
 .dark  {{ background:#1d1d24; color:#d9d9e3; border:1px solid #2e2e38 }}
 table {{ border-collapse:collapse; width:100%; margin-top:18px }}
 th, td {{ padding:7px 8px; text-align:left; vertical-align:middle;
          border-top:1px solid #e4e4ea }}
 th small {{ display:block; font-weight:normal; color:#888; font-size:.78em }}
 .chip {{ display:inline-flex; gap:12px; align-items:center; padding:7px 12px;
         border-radius:9px; margin:2px 6px 2px 0 }}
 thead th {{ border:none; color:#666; font-size:.85em; text-transform:uppercase;
            letter-spacing:.06em }}
 .wrap {{ overflow-x:auto }}
</style>
<h1>Makapix — row-3 tool icons, two custom options</h1>
<p class="note">All 28 row-3 symbols (26 tools + pinned Undo/Redo). <b>Option A</b> is a
16×16 hard-pixel grid (drawn like pixel art, dithers for gradients/ghosts). <b>Option B</b>
is a rounded 2px-stroke outline set on a 24×24 grid. Both are single-colour and inherit
the theme colour. The toolbar strips below render at <b>18 px — the exact size row 3
uses today</b>; the table shows each tool at 18/32/48 px on light and dark.</p>
{bars}
<div class="wrap"><table>
<thead><tr><th>Tool</th><th>Current</th><th>Option A — Pixel-grid</th>
<th>Option B — Smooth</th></tr></thead>
{rowhtml}
</table></div>
<p class="note">Note on Option A at 18 px: 16 px art in an 18 px box means a small
non-integer scale; pixels may render slightly uneven depending on screen density. In the
app we would letterbox it 1:1 inside the 18 px slot (or bump row-3 to a 16/32 px icon
size) so every pixel stays square.</p>'''
    with open(os.path.join(HERE, "contact_sheet.html"), "w", encoding="utf-8") as f:
        f.write(html)


def build_round2(sm_svgs, mat_svgs):
    by_key = {k: (label, dsl) for k, label, dsl, _ in TOOLS}
    locked = "".join(sz(sm_svgs[k], 20) for k in APPROVED)

    rowhtml = ""
    for key, label, dsl, _ in TOOLS:
        if key not in V:
            continue
        cells = f'<td><div class="chip light">{sz(mat_svgs[key], 24)}</div></td>'
        options = [sm_svgs[key]] + [smooth_svg(b) for b in V[key]]
        for i, svg in enumerate(options, 1):
            cells += (f'<td><div class="chip light">{sz(svg, 18)}{sz(svg, 36)}</div>'
                      f'<div class="chip dark">{sz(svg, 18)}{sz(svg, 36)}</div></td>')
        rowhtml += f'<tr><th><b>{label}</b><small>{dsl}</small></th>{cells}</tr>'

    html = f'''<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Makapix tool icons — round 2 (smooth variants)</title>
<style>
 body {{ font: 15px/1.5 system-ui, sans-serif; margin: 24px auto; max-width: 1120px;
        padding: 0 16px; background:#fbfbfd; color:#1b1b22; }}
 h1 {{ font-size: 1.45em; margin-bottom:.2em }}
 .note {{ color:#555; max-width: 78ch }}
 .ic {{ display:inline-flex; align-items:center; justify-content:center }}
 .ic svg {{ width:100%; height:100% }}
 .bar {{ display:flex; flex-wrap:wrap; gap:14px; padding:10px 14px; border-radius:10px;
        margin:8px 0 20px; align-items:center; width:fit-content }}
 .light {{ background:#f2f2f5; color:#2a2a33; border:1px solid #e0e0e6 }}
 .dark  {{ background:#1d1d24; color:#d9d9e3; border:1px solid #2e2e38 }}
 table {{ border-collapse:collapse; width:100% }}
 th, td {{ padding:7px 8px; text-align:left; vertical-align:middle;
          border-top:1px solid #e4e4ea }}
 th small {{ display:block; font-weight:normal; color:#888; font-size:.78em }}
 .chip {{ display:inline-flex; gap:10px; align-items:center; padding:6px 10px;
         border-radius:9px; margin:2px 6px 2px 0 }}
 thead th {{ border:none; color:#666; font-size:.85em; text-transform:uppercase;
            letter-spacing:.06em }}
 .wrap {{ overflow-x:auto }}
</style>
<h1>Round 2 — smooth variants for the 19 remaining tools</h1>
<p class="note"><b>Locked in from round 1</b> (approved, unchanged):</p>
<div class="bar dark">{locked}</div>
<p class="note">For each remaining tool: the current Material icon, then <b>B1</b> (the
round-1 design, for reference) and two new takes <b>B2</b> / <b>B3</b>. Each shown at
18&nbsp;px (row-3 size) and 36&nbsp;px, light and dark. Reply per tool, e.g.
“Brush&nbsp;B2, Gradient&nbsp;B3, Move&nbsp;none”.</p>
<div class="wrap"><table>
<thead><tr><th>Tool</th><th>Current</th><th>B1 (round 1)</th><th>B2</th><th>B3</th></tr></thead>
{rowhtml}
</table></div>'''
    with open(os.path.join(HERE, "round2.html"), "w", encoding="utf-8") as f:
        f.write(html)


if __name__ == "__main__":
    p, s, m = build()
    build_html(p, s, m)
    build_round2(s, m)
    print("OK: svgs + proofs + contact_sheet.html + round2.html written")
