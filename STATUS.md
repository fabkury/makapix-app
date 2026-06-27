# Makapix Club app — Implementation Status (2026-06-27)

Honest coverage of **both** of the app's co-equal pillars. The **Makapix Editor** (editor engine + Flutter
shell) is built and runnable on this workstation. The **Makapix Club** social layer (see
[`SPEC-CLUB.md`](SPEC-CLUB.md)) is **code-complete through phases C0–C3** (auth · read & discover · create &
publish · edit & remix) against the live server contract; **C4–C6** (curate/manage · real-time & players ·
moderation & extras) are **not yet** started. The two pillars sit under a neutral app shell
(`lib/shell/app_shell.dart`): the app **opens on the Club pillar** (signed-out users get Club's welcome/sign-in
funnel) and the editor is a co-equal feature reachable **without login** via the centre ⊕ Create button.
Legend: **✅ done & tested** · **◑ partial** (engine done, UI/edges pending) · **○ stubbed / not yet**.

## Build artifacts
- `crates/engine` — pure deterministic core (dependency-free). **56 lib + 8 scenario + 3 import + 1 perf tests.**
- `crates/codec` — image import/export (`image` crate). **2 tests.**
- `crates/ffi` — C-ABI DLL (`makapix_ffi.dll`). **2 tests** (lifecycle + GIF import→export).
- `crates/cli` — `mkpx` headless harness (renders PNG, prints oracles/JSON; exit-code CI gate).
- `app/` — Flutter Windows app → `app/build/windows/x64/runner/Release/makapix_club.exe` (+ bundled DLL).
- **Total: 68 Rust tests green.** Engine loop verified by rendering `examples/demo.txt` & `showcase.txt`.

## Core first-class features
| Feature | Status | Notes |
|---|---|---|
| Rust core + Flutter UI | ✅ | engine via C-ABI DLL + `dart:ffi` |
| Compact three-row UI/UX | ✅ | row-1 tool options · row-2 palette · row-3 tools (a **2-row, horizontally-scrolling, user-reorderable** tool grid) |
| Configurable tool order | ✅ | "Rearrange" mode: drag-and-drop tools + ◀▶ move-one-slot buttons; order persisted across launches (shared_preferences) |
| Mobile-first, responsive to tablet | ✅ | mobile-first column; **wide viewports (≥1000px) move frames+layers into a right side panel** |
| Lossless `.mkpx` (frames + layers) | ✅ | chunked, versioned, sparse tiles; round-trip is a test gate |
| Memory efficient (1024f / 256² / RGBA, per-frame undo) | ✅ | tiled COW + lazy alloc; 500f×20L = **48 MiB**, verified no-crash |
| Post to Makapix Club (publish) | ✅ | "Post to Club" exports the document (static→PNG, animated→GIF) and hands **only bytes** to `lib/club`, which runs conformance → metadata/license/visibility → bearer-auth upload (the real C2 publish flow). `tools/mock_club_server.py` remains an optional local harness; see the Club table below. |

## Tools & editing
| Feature | Status | Notes |
|---|---|---|
| Up to 1024 frames / 64 layers | ✅ | enforced caps |
| 128 undo/redo per frame + auto compaction | ✅ | global timeline, per-frame cap, absolute tile patches |
| Pencil / Paintbrush / Airbrush (configurable size) | ✅ | airbrush seeded & reproducible |
| **Precision mode** (off-finger reticle, draw-by-button) | ✅ | a per-tool toggle on Pencil/Brush/Airbrush/Eraser; drag moves a ✛ reticle off the finger; arrows nudge 1px; DRAW/SPRAY = one dab; PEN toggle = continuous stroke/spray while dragging. Reticle frames the target pixel without covering it |
| Bucket fill (contiguous / discontiguous, threshold) | ✅ | flood oracle-tested |
| Eraser (square / round, size) | ✅ | |
| **Figures** Line / Rectangle / Ellipse (draw → adjust → commit) | ✅ | drag previews an uncommitted figure with draggable endpoint handles; re-drag either handle (tap near, not on) to fine-tune; Fill/Outline updates the preview live; Commit ✓ rasterizes (one undo step), Cancel ✗ discards. Engine: `ShapeSet/ShapeCommit/ShapeCancel` |
| Select by color threshold (cont/discont) | ✅ | |
| Select rectangle / ellipse / circle / freeform | ✅ | polygon via freeform lasso path |
| Selection ops Add / Subtract / Union / Intersect / Invert | ✅ | set-algebra tested |
| HSV-shift selected pixels | ✅ | closed-form oracle |
| Gradient (2/3 colors, positions, alpha) | ✅ | linear + radial; tri-color; alpha; optional seeded dither |
| Darkener / Lightener brush (intensity, size) | ✅ | dodge/burn via HSV-V |
| Selected pixels move / copy / cut / paste | ✅ | |
| Copy pixels frame→frame | ✅ | `PasteToFrame` in engine/DSL (UI pastes to active frame) |
| Move/Duplicate layers from 1 frame → N frames | ✅ | layer options sheet → "Copy to all frames" (`DuplicateLayerToFrames`) |
| Duplicate / reorder animation frame | ✅ | film-roll of frame previews at the top of the canvas (tap to go to a frame; long-press for duplicate/duration/move/delete); engine-rendered cached thumbnails |
| Per-frame duration 16.6–1000 ms + bulk tools | ✅ | µs-precise; UI dialog (this frame / all frames / fps presets) |
| Palettes: create/edit/save/load, add/remove/edit/dup color, RGB+HSV | ✅ | multiple palettes (selector + new), add/edit/duplicate/remove color (long-press swatch), RGB+HSV picker, eyedropper, **save/load `.gpl`/JSON**, embedded in `.mkpx` |
| Select multiple layers, move together | ✅ | layer "move group" toggle + nudge pad → `NudgeLayers` (one undoable edit) |
| Import GIF/WebP/PNG/APNG/JPEG/BMP (crop/scale, start-frame, as-layer) | ✅ | all formats; import options dialog; **interactive crop-rectangle** (drag a region over the source preview) |
| Export PNG / sprite-sheet / GIF | ✅ | PNG + animated GIF wired in UI; sprite-sheet in codec |
| Canvas ops: flip H/V, invert, **rotate 90/180/270, resize, crop-to-selection** | ✅ | all in UI; rotate/resize/crop are undoable (canvas size travels with the edit) |
| `.mkpx` compression | ✅ | per-tile RLE (v2 format, v1 still readable) — a 10k-layer project shrank **48 MB → 1.2 MB** |
| Drag-and-drop reorder (frames & layers) | ✅ | long-press to drag in the timeline / layer strip (button reorder also kept) |

## Club social layer (C0–C3, Dart-only — `app/lib/club/`)
| Area | Status | Notes |
|---|---|---|
| **C0** GitHub OAuth + PKCE + token store | ✅ | server-brokered OAuth, custom-scheme return leg (`flutter_web_auth_2`); tokens at rest in `flutter_secure_storage`; single-flight 401→refresh→retry (`api/club_api_client.dart`) |
| **C0** Welcome / sign-in funnel | ✅ | signed-out users land on `ClubWelcomePage` (featured grid + sign-in), matching the website |
| **C1** Feeds: Recent / Recommended / Following | ✅ | tabbed hub; cursor paging (`state/paged.dart`); pull-to-refresh |
| **C1** Search (posts / hashtags / users) | ✅ | `ui/search_page.dart`, `ui/hashtag_feed_page.dart` |
| **C1** Profiles + follow/unfollow | ✅ | `ui/profile_page.dart` |
| **C1** Reactions + comments | ✅ | `ui/widgets/reactions_bar.dart`, `comments_section.dart` |
| **C1** Notifications + unread badge | ✅ | `ui/notifications_page.dart`; badge in the hub |
| **C2** Publish (editor → Club) | ✅ | export bytes → conformance → metadata/license/visibility → upload; auth-gated (`ui/publish_page.dart` shows a sign-in prompt when signed out) |
| **C3** Edit / remix (Club → editor) | ✅ | a Club post opens in the editor via `pendingClubEditProvider`; `ClubEditSource` provenance enables **Replace original** vs **Post as new** |
| **C4–C6** curate/manage · real-time & players · moderation | ○ | not yet started |

## App shell
| Feature | Status | Notes |
|---|---|---|
| Two co-equal pillars under a neutral shell | ✅ | `lib/app.dart` (root) → `lib/shell/app_shell.dart`; pillars in a keep-alive `IndexedStack` |
| Opens on the social experience | ✅ | launches on the Club pillar; welcome/sign-in funnel when signed out |
| Editor reachable without login | ✅ | prominent centre ⊕ **Create** button (notched `BottomAppBar` on phones, `NavigationRail` on wide windows) |

## How to exercise it
- **Engine loop (no GUI):** `cargo test` and `cargo run -p makapix-cli -- run examples/showcase.txt render:0:out.png:6 state assert.roundtrip`
- **The app:** `./build.ps1 -Run` (or launch the prebuilt exe). It opens on the Club hub; tap ⊕ Create to enter
  the editor. Draw with every tool, manage layers/frames, pick colors (RGB/HSV), set durations, play the
  animation, import an image, export PNG/GIF, save/open `.mkpx`; sign in to post to Club, or remix a Club post.

## Remaining gaps / next up (honest)
The editor pillar is feature-complete; the Club pillar is complete through C3. What genuinely remains:
1. **Club phases C4–C6** — curate/manage, real-time & players, moderation & extras (see `SPEC-CLUB.md` §28).
2. **iOS build** — cannot be built on this Windows workstation; deferred to a cloud macOS CI runner (SPEC §3.1).
   All shared code is iOS-clean and the engine is integer-deterministic, so this is build/packaging only.
3. Optional future polish: per-stop gradient-position UI editor, onion-skin range control, in-RAM compression
   of inactive frames (file compression already done), and localization.

## Local upload harness (optional)
The real publish flow runs against `development.makapix.club` / `makapix.club` (`config/club_config.dart`).
For offline testing of the multipart upload leg, `tools/mock_club_server.py` listens on
`http://localhost:8080` and writes received artifacts to `tools/uploads/`.
