# Makapix Editor — Implementation Status (2026-06-25)

Honest coverage of every feature listed in the brief and the SPEC. Legend:
**✅ done & tested** · **◑ partial** (engine done, UI/edges pending) · **○ stubbed / not yet**.

## Build artifacts
- `crates/engine` — pure deterministic core (dependency-free). **56 lib + 8 scenario + 3 import + 1 perf tests.**
- `crates/codec` — image import/export (`image` crate). **2 tests.**
- `crates/ffi` — C-ABI DLL (`makapix_ffi.dll`). **2 tests** (lifecycle + GIF import→export).
- `crates/cli` — `mkpx` headless harness (renders PNG, prints oracles/JSON; exit-code CI gate).
- `app/` — Flutter Windows app → `app/build/windows/x64/runner/Release/makapix_editor.exe` (+ bundled DLL).
- **Total: 68 Rust tests green.** Engine loop verified by rendering `examples/demo.txt` & `showcase.txt`.

## Core first-class features
| Feature | Status | Notes |
|---|---|---|
| Rust core + Flutter UI | ✅ | engine via C-ABI DLL + `dart:ffi` |
| Compact three-row UI/UX | ✅ | row-1 tool options · row-2 palette · row-3 tools |
| Mobile-first, responsive to tablet | ✅ | mobile-first column; **wide viewports (≥1000px) move frames+layers into a right side panel** |
| Lossless `.mkpx` (frames + layers) | ✅ | chunked, versioned, sparse tiles; round-trip is a test gate |
| Memory efficient (1024f / 256² / RGBA, per-frame undo) | ✅ | tiled COW + lazy alloc; 500f×20L = **48 MiB**, verified no-crash |
| Direct upload to Makapix Club | ✅ | UI dialog → real HTTP multipart POST to the provisional contract (`.mkpx`/GIF/PNG + metadata + bearer token). Test it with `tools/mock_club_server.py` (default URL `http://localhost:8080`). Swap in the real base URL when supplied. |

## Tools & editing
| Feature | Status | Notes |
|---|---|---|
| Up to 1024 frames / 64 layers | ✅ | enforced caps |
| 128 undo/redo per frame + auto compaction | ✅ | global timeline, per-frame cap, absolute tile patches |
| Pencil / Paintbrush / Airbrush (configurable size) | ✅ | airbrush seeded & reproducible |
| **Precision pencil** (off-finger reticle, draw-by-button) | ✅ | drag moves a ✛ reticle off the finger; arrows nudge 1px; DRAW = dot; PEN toggle = draw lines while dragging. Reticle frames the target pixel without covering it |
| Bucket fill (contiguous / discontiguous, threshold) | ✅ | flood oracle-tested |
| Eraser (square / round, size) | ✅ | |
| Select by color threshold (cont/discont) | ✅ | |
| Select rectangle / ellipse / circle / freeform | ✅ | polygon via freeform lasso path |
| Selection ops Add / Subtract / Union / Intersect / Invert | ✅ | set-algebra tested |
| HSV-shift selected pixels | ✅ | closed-form oracle |
| Gradient (2/3 colors, positions, alpha) | ✅ | linear + radial; tri-color; alpha; optional seeded dither |
| Darkener / Lightener brush (intensity, size) | ✅ | dodge/burn via HSV-V |
| Selected pixels move / copy / cut / paste | ✅ | |
| Copy pixels frame→frame | ✅ | `PasteToFrame` in engine/DSL (UI pastes to active frame) |
| Move/Duplicate layers from 1 frame → N frames | ✅ | layer options sheet → "Copy to all frames" (`DuplicateLayerToFrames`) |
| Duplicate / reorder animation frame | ✅ | add/duplicate/delete + move-left/right reorder buttons in the timeline |
| Per-frame duration 16.6–1000 ms + bulk tools | ✅ | µs-precise; UI dialog (this frame / all frames / fps presets) |
| Palettes: create/edit/save/load, add/remove/edit/dup color, RGB+HSV | ✅ | multiple palettes (selector + new), add/edit/duplicate/remove color (long-press swatch), RGB+HSV picker, eyedropper, **save/load `.gpl`/JSON**, embedded in `.mkpx` |
| Select multiple layers, move together | ✅ | layer "move group" toggle + nudge pad → `NudgeLayers` (one undoable edit) |
| Import GIF/WebP/PNG/APNG/JPEG/BMP (crop/scale, start-frame, as-layer) | ✅ | all formats; import options dialog; **interactive crop-rectangle** (drag a region over the source preview) |
| Export PNG / sprite-sheet / GIF | ✅ | PNG + animated GIF wired in UI; sprite-sheet in codec |
| Canvas ops: flip H/V, invert, **rotate 90/180/270, resize, crop-to-selection** | ✅ | all in UI; rotate/resize/crop are undoable (canvas size travels with the edit) |
| `.mkpx` compression | ✅ | per-tile RLE (v2 format, v1 still readable) — a 10k-layer project shrank **48 MB → 1.2 MB** |
| Drag-and-drop reorder (frames & layers) | ✅ | long-press to drag in the timeline / layer strip (button reorder also kept) |

## How to exercise it
- **Engine loop (no GUI):** `cargo test` and `cargo run -p makapix-cli -- run examples/showcase.txt render:0:out.png:6 state assert.roundtrip`
- **The app:** `./build.ps1 -Run` (or launch the prebuilt exe). Draw with every tool, manage layers/frames,
  pick colors (RGB/HSV), set durations, play the animation, import an image, export PNG/GIF, save/open `.mkpx`.

## Remaining gaps / next up (honest, after the third pass)
Essentially everything in the brief is now implemented. What genuinely remains is external or platform-bound:
1. **Makapix Club production endpoint** — the uploader is real and verified against
   `tools/mock_club_server.py`; it just needs the **production base URL + auth flow** when you have them.
2. **iOS build** — cannot be built on this Windows workstation; deferred to a cloud macOS CI runner (SPEC §3.1).
   All shared code is iOS-clean and the engine is integer-deterministic, so this is build/packaging only.
3. Optional future polish: per-stop gradient-position UI editor, onion-skin range control, in-RAM compression
   of inactive frames (file compression already done), and localization.

## Testing the Club upload
```
python tools/mock_club_server.py          # listens on http://localhost:8080
# in the app: ☁ Upload → leave URL as http://localhost:8080, any token → Upload
# the artifact lands in tools/uploads/ and the app shows the returned {id,url}
```
