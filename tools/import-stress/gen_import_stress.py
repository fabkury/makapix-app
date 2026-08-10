"""Generate the 3x3 image-import stress matrix (GIF/PNG/WebP x basic/medium/large).

Exercises the codec's decode size gates (MAX_DIM 4096, frame cap, aggregate-bytes cap —
crates/codec/src/lib.rs) and the off-isolate import decode (memory-audit #3): the basic
tier must import successfully with a responsive UI; medium and large must be refused
with the "image is too large" message — never a crash. Tier sizing rationale: basic fits
every budget, medium puts single decode buffers at 268-576 MB (the borderline zone under
Android's ~1 GiB scudo wall, docs/memlab/REPORT.md), large requires a >=1 GB single
allocation so it can never succeed.

Usage (needs numpy + Pillow):
    python gen_import_stress.py            # writes ~630 MB into out/ next to this script
    adb push out /sdcard/Download/makapix-import-stress
    adb shell content call --uri content://media --method scan_volume --arg external_primary

The media scan is required: adb push bypasses MediaStore, and the image picker only
shows indexed files (the Files app shows them regardless — don't be fooled).
First run on-device: 2026-08-10, all gates held (basic loaded, medium+large refused).
"""
import colorsys
import os
import time

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)


def rainbow_palette():
    pal = []
    for i in range(256):
        r, g, b = colorsys.hsv_to_rgb(i / 256.0, 1.0, 1.0 if i % 2 == 0 else 0.8)
        pal += [int(r * 255), int(g * 255), int(b * 255)]
    return pal


PAL = rainbow_palette()


def base(w, h, t):
    # XOR pattern with a per-frame phase shift; uint8 throughout so a
    # 22000x22000 plane stays under 500 MB during generation.
    x8 = (np.arange(w) % 256).astype(np.uint8)
    y8 = (np.arange(h) % 256).astype(np.uint8)[:, None]
    return (x8[None, :] ^ y8) + np.uint8((t * 37) % 256)


def pal_frame(w, h, t):
    im = Image.fromarray(base(w, h, t))  # mode L
    im.putpalette(PAL)  # converts to P
    return im


def rgb_frame(w, h, t):
    b = base(w, h, t)
    return Image.fromarray(np.dstack((b, b + np.uint8(85), b + np.uint8(170))))


def report(path, t0):
    mb = os.path.getsize(path) / 1e6
    print(f"  -> {os.path.basename(path)}: {mb:.1f} MB in {time.time() - t0:.0f}s", flush=True)


def make_gif(name, w, h, n):
    t0 = time.time()
    print(f"GIF {name}: {w}x{h} x{n} frames", flush=True)
    path = os.path.join(OUT, name)
    pal_frame(w, h, 0).save(
        path, save_all=True, append_images=(pal_frame(w, h, t) for t in range(1, n)),
        duration=100, loop=0, optimize=False,
    )
    report(path, t0)


def make_webp(name, w, h, n, lossless=False):
    # The large tier must be lossless: lossy VP8 hits libwebp's 512 KB partition-0 cap
    # ("WebPEncodingError: 6") at 16000px. Decoded size is identical either way.
    t0 = time.time()
    print(f"WebP {name}: {w}x{h} x{n} frames", flush=True)
    path = os.path.join(OUT, name)
    opts = {"lossless": True, "quality": 10} if lossless else {"quality": 60}
    rgb_frame(w, h, 0).save(
        path, save_all=True, append_images=(rgb_frame(w, h, t) for t in range(1, n)),
        duration=100, loop=0, method=0, **opts,
    )
    report(path, t0)


def make_png(name, w, h, noise=False):
    t0 = time.time()
    print(f"PNG {name}: {w}x{h}{' noise' if noise else ''}", flush=True)
    path = os.path.join(OUT, name)
    if noise:
        arr = np.random.default_rng(1).integers(0, 256, (h, w, 3), dtype=np.uint8)
    else:
        b = base(w, h, 0)
        arr = np.dstack((b, b + np.uint8(85), b + np.uint8(170)))
    Image.fromarray(arr).save(path, compress_level=1)
    report(path, t0)


make_gif("gif-1-basic-512px-60f.gif", 512, 512, 60)
make_png("png-1-basic-4096px.png", 4096, 4096, noise=True)  # 4096 = exactly MAX_DIM
make_webp("webp-1-basic-512px-60f.webp", 512, 512, 60)

make_gif("gif-2-medium-8192px-8f.gif", 8192, 8192, 8)
make_png("png-2-medium-12000px.png", 12000, 12000)
make_webp("webp-2-medium-8192px-8f.webp", 8192, 8192, 8)

make_gif("gif-3-large-16000px-4f.gif", 16000, 16000, 4)
make_png("png-3-large-22000px.png", 22000, 22000)
make_webp("webp-3-large-16000px-4f.webp", 16000, 16000, 4, lossless=True)

print("ALL DONE", flush=True)
