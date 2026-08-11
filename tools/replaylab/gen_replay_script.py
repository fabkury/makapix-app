"""Generate representative replay DSL scripts for the deterministic-replay appraisal.

Models real interactive use as observed in editor_page.canvas.dart / editor_page.engine.dart:
- freehand strokes: PointerDown + one PointerMove per input event (no coalescing) + PointerUp
- tool switches: the ~17-line settings burst _selectTool sends
- color changes, bucket taps, undos, frame/layer structure, selection + HSV apply
Outputs plain scripts (runnable by mkpx) and a timestamped variant (recording-format size model)
into out/ (gitignored). Numbers and method: docs/replay/ANALYSIS.md.
"""
import random, gzip, zlib, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

SETTINGS_BURST = [
    "SetBrushSize({bs}); SetBrushShape({shape})",
    "SetThreshold(32); SetContiguous(true); SetAlphaCutoff(8)",
    "SetIntensity(255); SetShapeFill(false); SetLineWidth(1)",
    "SetSpacing(1); SetFillAllLayers(false)",
    "SetSelectionMode(Replace); SetProtectPixels(false); SetWrap(false)",
    "SetPixelPerfect(false); SetOverscanView(0)",
    "SetEyedropSource(Frame)",
    "SetSelectColorSource(Frame)",
    "SetCleanEdge(true); SetCleanEdgeWidth(1000)",
    "SetScaleCleanEdge(true); SetScaleCleanEdgeWidth(1000)",
]

PAINT_TOOLS = ["Pencil", "Brush", "Eraser", "Airbrush", "Dodge", "Burn"]

def rand_color(rng):
    return "#%02X%02X%02XFF" % (rng.randrange(256), rng.randrange(256), rng.randrange(256))

def stroke_path(rng, w, h, n_moves):
    """A smooth-ish random walk: what a finger drag looks like in canvas pixels."""
    x = rng.uniform(2, w - 3); y = rng.uniform(2, h - 3)
    vx = rng.uniform(-1.5, 1.5); vy = rng.uniform(-1.5, 1.5)
    pts = []
    for _ in range(n_moves):
        vx += rng.uniform(-0.6, 0.6); vy += rng.uniform(-0.6, 0.6)
        vx = max(-2.5, min(2.5, vx)); vy = max(-2.5, min(2.5, vy))
        x = max(0, min(w - 1, x + vx)); y = max(0, min(h - 1, y + vy))
        pts.append((int(x), int(y)))
    return pts

def gen_session(name, w, h, target_lines, frames, seed):
    rng = random.Random(seed)
    lines = [f"NewDocument({w}, {h})"]
    tool = "Pencil"
    strokes_done = 0
    frames_added = 1
    layer_count = 1

    def select_tool(t):
        lines.append(f"SelectTool({t})")
        bs = rng.choice([1, 1, 2, 3, 5])
        shape = rng.choice(["Round", "Square"])
        for s in SETTINGS_BURST:
            lines.append(s.format(bs=bs, shape=shape))

    select_tool(tool)
    lines.append(f"SetPrimaryColor({rand_color(rng)})")

    while len(lines) < target_lines:
        r = rng.random()
        if r < 0.75:  # a freehand stroke (the dominant activity)
            n_moves = max(3, int(rng.gauss(45, 25)))  # ~0.5s at 90Hz avg
            pts = stroke_path(rng, w, h, n_moves)
            lines.append(f"PointerDown({pts[0][0]},{pts[0][1]})")
            for (x, y) in pts[1:]:
                lines.append(f"PointerMove({x},{y})")
            lines.append("PointerUp()")
            strokes_done += 1
            if rng.random() < 0.07:
                lines.append("Undo()")
                if rng.random() < 0.3:
                    lines.append("Redo()")
        elif r < 0.83:  # color change
            lines.append(f"SetPrimaryColor({rand_color(rng)})")
        elif r < 0.90:  # tool switch (full settings burst)
            tool = rng.choice(PAINT_TOOLS)
            select_tool(tool)
        elif r < 0.94:  # bucket fill somewhere
            select_tool("Bucket")
            lines.append(f"Tap({rng.randrange(w)},{rng.randrange(h)})")
            select_tool(tool)
        elif r < 0.965:  # a selection band + HSV nudge (the showcase pattern)
            select_tool("SelectRect")
            y0 = rng.randrange(h - 8)
            lines.append(f"PointerDown(0,{y0})")
            lines.append(f"PointerMove({w - 1},{y0 + 6})")
            lines.append("PointerUp()")
            lines.append(f"SetHsvShift({rng.randrange(-40, 40)}, 0.1, 0.0); ApplyHsvShift()")
            lines.append("SelectNone()")
            select_tool(tool)
        elif r < 0.98 and frames_added < frames:  # grow the animation
            lines.append(f"DuplicateFrame({frames_added - 1})")
            frames_added += 1
            lines.append(f"SetActiveFrame({frames_added - 1})")
        elif r < 0.99 and layer_count < 4:
            lines.append("AddLayer()")
            layer_count += 1
        else:  # frame hop while animating
            if frames_added > 1:
                lines.append(f"SetActiveFrame({rng.randrange(frames_added)})")

    path = os.path.join(OUT, f"{name}.txt")
    text = "\n".join(lines) + "\n"
    with open(path, "w", newline="\n") as f:
        f.write(text)

    # Timestamped recording-format variant (what the sidecar would actually store):
    # "+<delta_ms> <line>" — deltas modeled at ~11ms between pointer events, bigger gaps between
    # strokes/ops. Never run through mkpx; size/compressibility model only.
    t_lines = []
    for ln in lines:
        if ln.startswith("PointerMove"):
            dt = max(4, int(rng.gauss(11, 3)))
        elif ln.startswith(("PointerDown", "PointerUp")):
            dt = rng.randrange(200, 3000)  # gap between strokes
        else:
            dt = rng.randrange(300, 8000)  # UI interactions between ops
        t_lines.append(f"+{dt} {ln}")
    t_text = "\n".join(t_lines) + "\n"
    t_path = os.path.join(OUT, f"{name}.log")
    with open(t_path, "w", newline="\n") as f:
        f.write(t_text)

    raw = text.encode(); traw = t_text.encode()
    gz = len(gzip.compress(traw, 6))
    z1 = len(zlib.compress(traw, 1))
    n_pointer = sum(1 for l in lines if l.startswith("Pointer"))
    print(f"{name}: lines={len(lines)} pointer%={100*n_pointer/len(lines):.0f} "
          f"strokes={strokes_done} frames={frames_added} layers={layer_count} "
          f"script_bytes={len(raw)} log_bytes={len(traw)} log_bytes/line={len(traw)/len(lines):.1f} "
          f"gzip6={gz} ({len(traw)/gz:.1f}x) zlib1={z1} ({len(traw)/z1:.1f}x)")

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_session("replay_small", 64, 64, 15_000, 1, 1)
    gen_session("replay_medium", 128, 128, 60_000, 8, 2)
    gen_session("replay_large", 256, 256, 150_000, 16, 3)
    # parse/dispatch floor: cheap non-painting actions
    rng = random.Random(9)
    lines = ["NewDocument(64, 64)"]
    for _ in range(100_000):
        lines.append(f"SetCursor({rng.randrange(64)},{rng.randrange(64)})")
    with open(os.path.join(OUT, "replay_cheap.txt"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(OUT, "baseline.txt"), "w", newline="\n") as f:
        f.write("NewDocument(64, 64)\n")
    print("replay_cheap: lines=100001 (SetCursor floor); baseline.txt written")
