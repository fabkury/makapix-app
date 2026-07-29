#!/usr/bin/env python3
"""Generate synthetic GIFs for the memory-audit import measurements (pure stdlib).

Two modes:
  full  — every frame is a full-canvas opaque solid (color cycles per frame). Uses the
          byte-aligned literal-LZW trick (min_code_size=7 → every 8-bit code is one output
          byte; a Clear every 125 literals keeps the code width at 8), so no real LZW is
          needed and the image crate decodes it fine. This is the "legitimate big animation"
          for measuring the import transient.
  noise — like full, but every pixel gets a pseudo-random palette index, so every decoded
          tile is content-unique (defeats the .mkpx tile-dictionary dedup — needed to
          demonstrate the over-budget save/reload consequence of audit finding P-0).
  bomb  — the adversarial case from the audit (P-3): a large logical screen with N tiny
          1x1 sub-frames. The file stays a few KB per frame descriptor, but a compositing
          decoder materializes the FULL logical screen per frame (w*h*4 bytes), so total
          decode attempts N * w * h * 4 with no aggregate cap.

Usage:
  python make_gif.py full|noise <w> <h> <frames> <out.gif>
  python make_gif.py bomb <screen_w> <screen_h> <frames> <out.gif>
"""
import struct
import sys


def _header(w: int, h: int) -> bytes:
    out = bytearray(b"GIF89a")
    out += struct.pack("<HH", w, h)
    # GCT present, color resolution 7, GCT size flag 7 -> 256 entries.
    out += bytes([0x80 | 0x70 | 0x07, 0x00, 0x00])
    # 256-entry global color table: a simple ramp so per-frame colors differ.
    for i in range(256):
        out += bytes([i, (i * 3) % 256, (255 - i) % 256])
    return bytes(out)


def _gce(delay_cs: int = 4) -> bytes:
    # Graphic Control Extension: no transparency, disposal 1 (leave in place).
    return bytes([0x21, 0xF9, 0x04, 0x04]) + struct.pack("<H", delay_cs) + bytes([0x00, 0x00])


def _sub_blocks(data: bytes) -> bytes:
    out = bytearray()
    for i in range(0, len(data), 255):
        chunk = data[i : i + 255]
        out += bytes([len(chunk)]) + chunk
    out += b"\x00"
    return bytes(out)


def _full_frame(w: int, h: int, color_index: int, noise: bool) -> bytes:
    """Image descriptor + literal-LZW image data for an opaque full-canvas frame."""
    out = bytearray()
    out += b"\x2C" + struct.pack("<HHHH", 0, 0, w, h) + b"\x00"  # descriptor, no LCT
    out += b"\x07"  # LZW min code size 7 -> 8-bit codes, clear=0x80, EOI=0x81
    total = w * h
    if noise:
        # splitmix64 finalizer per (frame, pixel) — a real mix, so every 32x32 tile is
        # content-unique after decode (a cheap linear formula collapses to repeated tiles).
        m = (1 << 64) - 1

        def mix(x: int) -> int:
            x &= m
            x ^= x >> 30
            x = (x * 0xBF58476D1CE4E5B9) & m
            x ^= x >> 27
            x = (x * 0x94D049BB133111EB) & m
            x ^= x >> 31
            return x

        px_stream = bytearray(mix((color_index << 32) | k) & 0x7F for k in range(total))
    else:
        px_stream = bytearray([color_index & 0x7F]) * total  # literals stay below Clear (128)
    data = bytearray()
    pos = 0
    while pos < total:
        run = min(125, total - pos)  # <=125 literals between Clears keeps codes at 8 bits
        data += px_stream[pos : pos + run]
        pos += run
        data += b"\x80"  # Clear
    data += b"\x81"  # End of Information
    out += _sub_blocks(bytes(data))
    return bytes(out)


def _bomb_frame() -> bytes:
    """Image descriptor + minimal LZW for a single 1x1 sub-frame at (0,0)."""
    out = bytearray()
    out += b"\x2C" + struct.pack("<HHHH", 0, 0, 1, 1) + b"\x00"
    # min code size 2 -> initial 3-bit codes: Clear=4 (100b), literal 1 (001b), EOI=5 (101b).
    # LSB-first packing of 100 001 101 -> bytes 0x4C 0x01.
    out += b"\x02" + _sub_blocks(bytes([0x4C, 0x01]))
    return bytes(out)


def main() -> None:
    if len(sys.argv) != 6 or sys.argv[1] not in ("full", "noise", "bomb"):
        print(__doc__)
        sys.exit(2)
    mode, w, h, frames, path = (
        sys.argv[1],
        int(sys.argv[2]),
        int(sys.argv[3]),
        int(sys.argv[4]),
        sys.argv[5],
    )
    with open(path, "wb") as f:
        f.write(_header(w, h))
        for i in range(frames):
            f.write(_gce())
            f.write(_bomb_frame() if mode == "bomb" else _full_frame(w, h, i, mode == "noise"))
        f.write(b"\x3B")  # trailer
    print(f"wrote {path}: {mode} {w}x{h} x {frames} frames")


if __name__ == "__main__":
    main()
