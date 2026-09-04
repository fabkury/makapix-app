# Makapix Club app — Implementation Status (2026-07-26)

Honest coverage of **both** of the app's co-equal pillars. The **Makapix Editor** (editor engine + Flutter
shell) is built and runnable on this workstation. The **Makapix Club** social layer (see
`SPEC-CLUB.md`) is **code-complete through phases C0–C3** (auth · read & discover · create &
publish · edit & remix) against the live server contract; **C4** (curate/manage) is **nearly done** — the
artist dashboard, settings (monitored hashtags), post management + ZIP data export, the profile redesign
(Reacted ⚡ tab · Highlights 💎 strip · own-profile Private tab), avatar-from-post, and **ugc-safety
(report · block · rules gate, live on prod 2026-07-09)** are done; highlights *management* and categories
remain, and **playlists are fully deferred** (2026-07-07: don't develop until further notice — the
server feature itself is mostly planned-but-deferred). Of **C5**, **player control + send-to-player**
(the Player Bar, 2026-06-29) and **player registration & management** (My Players, 2026-07-17) have
shipped, and **live notifications shipped 2026-08-11 over the server's SSE stream** (the C5 MQTT
plan is obsolete — the server's notification plane separation removed the browser/app MQTT
notification topics; message 0001 in `reference/makapix-club/docs/notification-architecture/`); the
soft-player kiosk is **not yet** started.
Of **C6** (moderation & extras), **mod-hashtags shipped 2026-07-05**, and **in-app moderation shipped
2026-08-06**: moderator post actions on the artwork kebab (hide/unhide · promote/demote · approve ·
permanent delete), comment mod actions (delete/undelete · hide · purge), the User Management page
(trust · hide · ban · reputation · email reveal), and the Moderation hub with the pending-approval
queue; the reports queue, audit log, and pulse remain website-only. The
two pillars sit under a neutral app shell
(`lib/shell/app_shell.dart`): the app **opens on the Club pillar** (signed-out users get Club's welcome/sign-in
funnel) and the editor is a co-equal feature reachable **without login** — the Club top bar's **Contribute**
control opens a swipeable Contribute page (editor or direct file upload); the signed-out welcome page keeps
a Contribute button of its own.

**Distribution:** **Android** — **live on Google Play since 2026-07-27**
([store page](https://play.google.com/store/apps/details?id=club.makapix.app); production 1.0.18+23,
promoted from the alpha closed-testing track, 177 countries; alpha remains the testing track). **iOS** — **live on the App Store since 2026-07-17**; **universal iPhone + iPad since
1.0.16** (approved 2026-07-26; 1.0.18 build 10 live the same day). iOS builds ship via Codemagic →
TestFlight; the Rust engine ships as a dynamic `MakapixFFI.framework`, guarded by the codemagic.yaml R2
export gate; Sign in with Apple live end-to-end. **Windows** — developer build from this workstation
(`build.ps1`).
Legend: **✅ done & tested** · **◑ partial** (engine done, UI/edges pending) · **○ stubbed / not yet**.

**Battery discipline (2026-08-12):** a measured editor battery program shipped in one day
(docs/battery/ — ASSESSMENT · RECOMMENDATIONS incl. the close-out ledger · BASELINE with all
numbers): idle-with-selection dropped **2 083 → 938 mW** (marching ants now repaint at their
5.7 Hz content rate inside a RepaintBoundary instead of driving 120 fps full-page frames),
editor-session network fell **42 → 2 requests/10 min** (pillar+lifecycle-gated player poll),
2 fps playback dropped **1 835 → 979 mW** (hybrid ticker/timer playback clock, R3), plus a
single-flight redraw scheduler (R1) and an O(log n) playback poll (F15). Phases 3–4 and
Gate B are deliberately parked with pickup notes in the RECOMMENDATIONS ledger.

## Build artifacts
- `crates/engine` — pure deterministic core (dependency-free). **228 lib + 23 scenario + 4 fuzz + 1 perf tests.**
- `crates/codec` — image import/export (`image` crate). **12 tests.**
- `crates/ffi` — C-ABI engine library: Windows `makapix_ffi.dll` · Android `libmakapix_ffi.so` (jniLibs) ·
  iOS dynamic `MakapixFFI.framework` (built by `build_ios.sh`; export-gated in CI). **7 tests.**
- `crates/cli` — `mkpx` headless harness (renders PNG, prints oracles/JSON; exit-code CI gate).
- `app/` — Flutter: Windows exe (`build.ps1`) · Android APK/AAB (`build_android.ps1`,
  `release_android.ps1` → Play) · iOS ipa (Codemagic → TestFlight/App Store, `codemagic.yaml`).
- **Total: 275 Rust tests + 366 Dart tests green** (verified 2026-07-26). Engine loop verified by rendering
  `examples/demo.txt` & `showcase.txt`.
- `tools/memlab/` — **memory-limit stress study (2026-07-16, ✅ measured on Windows + Pixel 10 Pro XL)**:
  full-noise adversarial documents, headless CLI matrix + intent-gated in-app ladder. Findings + budgets:
  [`docs/memlab/REPORT.md`](docs/memlab/REPORT.md); headline: Android aborts (scudo ~1 GiB size-class wall,
  SIGABRT not LMK) long before the nominal 1024×64 frame/layer limits; `.mkpx` save transient 6–7× doc;
  scripted frame-adding retains O(frames²·layers) undo tables. **Enforcement SHIPPED 2026-07-16**
  (memory-budget-enforcement M1–M6; the plan file is retired to git history): COW tile
  tables, 96 MiB history byte budget, 256/320 MiB document budget on unique payload (rollback at the three
  mutation chokepoints + loader refusal + editor banner/snackbar), clone-free `.mkpx` save (byte-identical,
  peak 6.2×→3.2×). Invariant: a session is never over the hard budget — the Android SIGABRT workloads now
  end as graceful refusals (device-re-validated).

## Core first-class features
| Feature | Status | Notes |
|---|---|---|
| Rust core + Flutter UI | ✅ | engine via a C-ABI dynamic library + `dart:ffi` (Windows `.dll` · Android `.so` · iOS `MakapixFFI.framework`) |
| Compact three-row UI/UX | ✅ | row-1 tool options · row-2 palette · row-3 tools (a **2-row, horizontally-scrolling, user-reorderable** tool grid; optional 3-row mode in ☰ View with a long-press-configurable third pinned slot (default Pencil) — 2-row is the default everywhere since 2026-07-24; **☰ View → Show/hide tools…** hides tiles from the grid without disabling the tool — shortcuts/hold-pick/pinned slot still reach it, hidden tools keep their order slot, one-visible floor + Show all, hiding Onion while on turns it off — ADR 0018); custom tool iconography (12 generated icon painters + brush Shape glyphs) |
| Configurable tool order | ✅ | "Rearrange" mode: drag-and-drop tools + ◀▶ move-one-slot buttons; order persisted across launches (shared_preferences) |
| Pick color sources (primary-to-target) | ✅ | 2026-08-31: the one `ColorPickerDialog` carries a sources strip — Primary · Prev (X swap partner) · the palette as a scrolling lane; a tap sets the working color (dialog stays open, OK commits); the Primary source is withheld when picking the primary itself. The contract for every current and future color target (SPEC §10) |
| Truthful-alpha color swatches | ✅ | transparency-checker backing in the row-2 strip, palette page, and Gradient options; one diagonal dual-indicator everywhere when alpha < 255 (opaque top-left / composited bottom-right — the primary swatch's rectangular split retired 2026-08-05); "Overwrite with primary color" in the swatch long-press sheet (2026-07-21 → 08-05) |
| Mobile-first, responsive to tablet/iPad | ✅ | mobile-first column; **wide viewports (≥1000px) move frames+layers into a right side panel**; tablet pass 2026-07-19: editor landscape layout + chrome scaling, Club centered surfaces + capped sheets, two-pane artwork detail, tablet-scaled profile header; **iPad enabled (universal)**, shipped in iOS 1.0.16 |
| Lossless `.mkpx` (frames + layers) | ✅ | **v10** typed-chunk container (single canonical version; older versions rejected with `UnsupportedVersion`): content-addressed tile dictionary, byte-deterministic, CRC-32C + content-hash check; round-trip is a test gate (`docs/mkpx-format/`). 2026-08-05 blend-modes groundwork: tolerant production loader (content-hash mismatch = logged warning; strict in tests/CLI) + typed FFI load codes (newer-version / corrupt / over-budget distinguishable in the UI); the per-layer blend byte is live (values 0..=10, unknown → Normal) |
| Off-canvas gutter + overscan view | ✅ | Move preserves pixels pushed off-canvas in a 1-canvas gutter each side (3×3 storage); paint stays canvas-only; ☰ View → Overscan reveals the dimmed gutter (keep-zoom-pan). See SPEC §8.3 |
| Memory efficient (1024f / 512² / RGBA, per-frame undo) | ✅ | tiled COW + lazy alloc; 500f×20L = **48 MiB**, verified no-crash. Canvas cap 256 → 512 on 2026-09-03 (ADR 0021): memory is area-linear, budgets unchanged, so a 512 document reaches them at ~¼ the frames/layers/undo depth (47 full-canvas undos vs 128); older app versions refuse >256 files as corrupt (accepted); Club publishing stays capped at 256 |
| Post to Makapix Club (publish) | ✅ | "Post to Club" exports the document (static→PNG, animated→GIF) and hands **only bytes** to `lib/club`, which runs conformance → metadata/license/visibility → bearer-auth upload (the real C2 publish flow). `tools/mock_club_server.py` remains an optional local harness; see the Club table below. |

## Tools & editing
| Feature | Status | Notes |
|---|---|---|
| Up to 1024 frames / 64 layers | ✅ | enforced caps |
| 128 undo/redo per frame + auto compaction | ✅ | global timeline, per-frame cap, absolute tile patches |
| Pencil / Paintbrush / Airbrush (configurable size) | ✅ | airbrush seeded & reproducible; Dots / Soft / Mist modes (hard spray / smoothstep-falloff stamp / center-weighted translucent specks) |
| **Precision mode** (off-finger reticle, act-by-button) | ✅ | a per-tool toggle on Pencil/Brush/Airbrush/Eraser/Dodge/Burn/Eyedropper/Select Color; drag moves a ✛ reticle off the finger; arrows nudge 1px; DRAW/SPRAY = one dab, PICK = color pick, SELECT = color selection at the reticle; HOLD toggle = continuous stroke/spray while dragging (paint tools only). Reticle frames the target pixel without covering it |
| Bucket fill (contiguous / discontiguous, threshold) | ✅ | flood oracle-tested |
| Eraser (square / round, size) | ✅ | rides the per-stroke coat since 2026-08-15 (ADR 0008) — hard erase pixel-identical, and the substrate for AA |
| **AA (anti-alias) toggle** | ✅ | 2026-08-15 (ADR 0008): one shared `SetAA` flag — round Brush, Line/Rect/Ellipse/Triangle, round Eraser get 16×16-supersampled fractional-coverage edges (257 levels, integer-deterministic incl. rotation via `det_sincos`); size-1/Square brushes, Pencil, Bucket, Gradient stay hard forever; 1-bit selections hard-clip; preview == commit by construction; default OFF, persisted "AA" chip. Companion fixes shipped with it: GIF export thresholds alpha at 128 **and tells the artist** (was: silent promote-to-opaque), journal replay drops only an unknown verb's own line (was: the batch remainder) |
| **Figures** Line / Rectangle / Ellipse (draw → adjust → commit) | ✅ | drag previews an uncommitted figure with draggable endpoint handles; re-drag either handle (tap near, not on) to fine-tune; Fill/Outline updates the preview live; Commit ✓ rasterizes (one undo step), Cancel ✗ discards. Engine: `ShapeSet/ShapeCommit/ShapeCancel` |
| Select by color threshold (cont/discont) | ✅ | source toggle: composited frame (default) or active layer's raw pixels (`SetSelectColorSource`) |
| Select rectangle / ellipse / circle / freeform | ✅ | polygon via freeform lasso path; in the UI lasso is a mode of the Select tool (Rect · Oval · Lasso toggle), not a separate tile |
| Selection ops Add / Subtract / Union / Intersect / Invert | ✅ | set-algebra tested |
| HSV-shift selected pixels | ✅ | closed-form oracle |
| Brightness/Contrast (layer/selection, Frame scope) | ✅ | HSV-style tool: live engine preview, ±255 brightness + ±100% contrast around the 128 pivot; a non-zero adjustment is a draft resolved by the commit-menu (Commit = one undo step); closed-form oracle |
| **Repeat** (repeat-redo) | ✅ | 2026-08-30 (ADR 0017): with the redo stack empty, the Redo tile becomes **Repeat** and re-executes the last repeatable op on the live target (active frame/layer/selection) — adjustment bakes (Levels/HSV/BC with scope), layer-scoped Flip/Rotate/Scale, paste-stamp (pixels snapshotted), and since 2026-09-04 (ADR 0024) the **Bucket fill** (tap or Fill button: seed as a canvas pixel + color/threshold/contiguous/all-layers snapshotted; Journal epoch `#mkpxj 3`). Params snapshot at commit; record survives Undo/Redo, dies with the document; carried by replay checkpoints; Ctrl+Y rides the Redo command |
| Gradient (2–8 colors, positions, alpha) | ✅ | linear + radial; up to 8 evenly-spaced colors (2026-08-30 — was 6); the extra colors + count persist across sessions and pillar switches (2026-08-31); extra chips: tap = Pick color, long-press/right-click = quick menu (Use primary color · Set as primary · Edit color); alpha; optional smoothstep easing; blends source-over onto layer content (2026-08-16 — was overwrite; transparent stops leave pixels untouched), with a pixel-exact composited draft preview |
| Darkener / Lightener brush (intensity, size) | ✅ | dodge/burn via HSV-V |
| **Ruler** (distance + **Angle** mode) | ✅ | pure-Dart canvas overlay (no engine): draggable endpoints with a px readout; Angle mode adds a third point C — 0–180° readout, cyan arc, smart chip flip, whole-cell snapping (2026-07-19) |
| **Resize tool** (scale layer/selection) | ✅ | engine `Scale` verb; draft-adjust-commit like Rotate; per-tool **cleanEdge** resampling (upscale-only gate), 0.1×–8× (2026-07-14) |
| **Eyedropper**: drag-pick + Frame/Layer source | ✅ | continuous picking while the finger drags; source toggle — composited frame (default) or the active layer's raw pixels (1.0.18) |
| Selected pixels move / copy / cut / paste | ✅ | **Slow** chip at the end of the Move and CopyPaste row-1 (ADR 0020, 2026-09-02): gears the Move draft / selection-mask / Paste draft drags down for exact placement — 4× finger travel per draft pixel at coarse zoom, capped so one pixel never costs more than 32 screen px, off past 32 px/px; shell-side only, the Journal sees the same deltas; session-only. Row-1 clipboard swatch (2026-08-30): live 30×30 checker-backed preview left of Copy ("×" when empty); tap → view-only zoom dialog (pinch 0.5–32×, nearest-neighbor). New FFI `mkpx_clipboard_rgba` + `clipboard_gen`/`clipboard_size` in the state probe |
| Copy pixels frame→frame | ✅ | `PasteToFrame` in engine/DSL (UI pastes to active frame) |
| Move/Duplicate layers from 1 frame → N frames | ✅ | layer options sheet → "Copy to all frames" (`DuplicateLayerToFrames`) |
| Merge down (layer onto the one below) | ✅ | layer options sheet → "Merge down" (`MergeDown`): compositor-exact blend with the source's opacity **and blend mode** (baked Photoshop-style), merged layer keeps the below layer's settings; one undo step; bottom/locked-below guarded |
| Layer blend modes (10 + Normal) | ✅ | 2026-08-05: Multiply · Screen · Overlay · Darken · Lighten · Addition · Subtract · Difference · Exclusion · Hard Light — integer-exact W3C math in the one compositor (`color::composite`), so canvas, exports, thumbnails, frame-source eyedropper, and all-layers Bucket all see blended colors (by design). Layer sheet → Blend opens a grouped picker (live preview via `PreviewLayerBlend`, apply-on-close = one undo step via `SetLayerBlend`); two-letter tile badge when non-Normal. Persisted in the reserved `.mkpx` blend byte (older readers show Normal + a logged hash warning — the groundwork's designed degradation; same for lagging Club clients on layers files). Paste-draft preview ignores blend (v1 limitation); GIF export may quantize blended gradients |
| Duplicate / reorder animation frame | ✅ | film-roll of frame previews at the top of the canvas (tap to go to a frame; long-press for duplicate/duration/move/delete); engine-rendered cached thumbnails. **Delete frame / Delete layer confirm by a second tap** (ADR 0022, 2026-09-03): the sheet button arms on the first tap ("Tap again to confirm", filled red) and deletes on a second tap within 3 s; the window's expiry, a retarget, any other sheet action, or closing the sheet disarms it silently; the keyboard Delete frame command arms the same way (toast) |
| Per-frame duration 16.6–1000 ms + bulk tools | ✅ | µs-precise; UI dialog (this frame / all frames / fps presets) |
| Palettes: create/edit/save/load, add/remove/edit/dup color, RGB+HSV | ✅ | full-screen **palette page** (row-2 palette button): swatch previews of every palette (3-row cards, `…` trim), tap to load, rename/duplicate/reorder/clear/delete (destructive ops reconfirm — palette edits are outside undo), per-palette `.gpl` export, `.gpl`/JSON import, **bundled presets** (PICO-8, Endesga 32, Resurrect 64, NES, comfort44s), **"From artwork colors"** (inspect-before-commit since 2026-09-01: an **Artwork colors page** extracts in a background isolate behind a spinner, shows the over-256 / empty / failed message or the palette-ordered swatch grid — engine `used_colors_sorted_json`, the `SortPalette` order, so no sort on Accept — with a per-color sheet: exact value + copy `#RRGGBB`/`#RRGGBBAA`, add to the active palette (duplicates skipped, cap refuses), set as primary; Accept creates the palette, Reject is live only when there is one), **Sort** (engine `SortPalette`/`SortPaletteAt`: grays-first hue ramps — gray ramp dark→light, then 12 hue buckets each dark→light by luma, opaque before translucent, integer-exact; reconfirms); color-level editing stays in the row-2 strip (add/edit/duplicate/remove via long-press swatch — compact header: identity left, move arrows right, arrows orientation-remapped in landscape; Remove/Overwrite reconfirm), **optional per-color names** (slot-bound: follow swap/sort/duplicate, survive color edits; pencil edit in the swatch sheet, empty = clear; hover tooltips on row-2 + palette page; persisted in the ancillary `UPCN` chunk — old builds still open new files), RGB+HSV picker, eyedropper, embedded in `.mkpx` |
| Select multiple layers, move together | ✅ | layer "move group" toggle + nudge pad → `NudgeLayers` (one undoable edit) |
| Import GIF/WebP/PNG/APNG/JPEG/BMP (crop/scale, start-frame, as-layer) | ✅ | **Open** (File → Open, 2026-09-03) accepts the same raster formats as a **new drawing at native size** — one frame per animation frame with its duration, title from the file name, provenance marked imported; refused above 512 per side with a pointer to Import (CONTEXT.md: Open preserves or refuses, Import converts); the picked bytes are sniffed for the `.mkpx` signature, never trusted by extension, so mislabeled files still open. **Import:** all formats; import options dialog; **dedicated crop editor** — static + animated preview (play/pause), draggable corner reticles, X/Y/W/H numeric entry, optional canvas-aspect lock, **zoomable/pannable view** (2026-09-01: one finger edits the crop, two fingers/trackpad pan + pinch, wheel zooms at the cursor, right/middle-drag pans, double-tap fit ↔ 4×, fit … 32 px/px); the region is placed **1:1 centered** (downscaled to fit only when larger than the canvas, never upscaled). The Fit/Stretch/Crop chooser appears only for a source larger than the canvas (Crop opens the editor at once); a smaller source is placed 1:1 centered with an optional "Scale up to fit" switch, an exact-size source has no scaling UI. **Place step** (ADR 0019, 2026-09-01): whenever the result leaves canvas uncovered, the dialog's Next opens a pre-import page — canvas + the start frame's composite as backdrop, the animated import floating, one-finger drag snapped to canvas px, X/Y chips + ±1 px arrows, off-canvas allowed (shaded, dropped at import) — and its Import commits with an engine `placement` offset; Crop and Place share one decoded preview |
| Export PNG / sprite-sheet / GIF | ✅ | PNG + animated GIF wired in UI; sprite-sheet in codec |
| Canvas ops: invert, resize, crop-to-selection, **rotate canvas 90/180/270, flip canvas H/V** | ✅ | rotate/flip-canvas in the timeline ☰ menu's grouped **Canvas** submenu; resize/crop/rotate undoable (canvas size travels with the edit) |
| **Flip & Rotate tools: layer/selection-scoped** | ✅ | Flip H/V and Rotate act on the active layer, or just the selected pixels (the selection mask transforms with them); Rotate adds 90/180/270 instant + an "Angle" draft with an on-canvas handle (semitransparent preview, Commit = one undo), rotate-about-center, clip to canvas |
| `.mkpx` compression | ✅ | v10: content-addressed tile **dedup** + per-tile codec menu (`RAW`/`RLE`/`INDEXED`, RAW floor) — the RLE-era baseline already shrank a 10k-layer project **48 MB → 1.2 MB**; v10 dedups repeated tiles on top |
| Drag-and-drop reorder (frames & layers) | ✅ | long-press to drag in the timeline / layer strip (button reorder also kept) |

## Club social layer (C0–C3, Dart-only — `app/lib/club/`)
| Area | Status | Notes |
|---|---|---|
| **C0** GitHub OAuth + PKCE + token store | ✅ | server-brokered OAuth via `flutter_web_auth_2` — return leg is an **HTTPS App Link on dev** and the **`club.makapix.app://` custom scheme on prod** (Chrome same-site handling; `club_config.dart` documents why); app id `club.makapix.app`; tokens at rest in `flutter_secure_storage`; single-flight 401→refresh→retry (`api/club_api_client.dart`). **Verified on-device**. Residual one-tap Custom-Tab return is accepted (§6.3) |
| **Sign in with Apple** (iOS, guideline 4.8) | ✅ | native `ASAuthorizationController` sheet → `apple_identity_token` grant on `/auth/token` (`auth/apple_oauth.dart`, `ClubSession.loginApple`); nonce replay protection; relay-email ("Hide My Email") → separate account, verified non-relay email links like GitHub. **Live end-to-end on prod, device-verified 2026-07-09** (contract + rollout: `docs/ios-release/apple-signin-server.md`, server `docs/apple-signin/` msgs 0001–0004). iOS-only by nature; button self-hides elsewhere |
| **C0** Welcome / sign-in funnel | ✅ | signed-out users land on `ClubWelcomePage` (featured grid + sign-in), matching the website |
| **C0b** In-app account creation | ✅ | **chosen-password** register → single 6-digit OTP verify → auto sign-in (A2) → welcome wizard (handle w/ live availability + **Back** · avatar/bio · `complete-welcome`). "Verify your email" recovery + forgot-password (OTP) on sign-in; Settings → Account (change password/handle, linked logins). Handle rules mirror the server (1–32 printable-Unicode code points). **Verified end-to-end on-device against dev.** `ui/auth/*`, `state/registration_controller.dart` |
| **C1** Feeds: Recent / Recommended / Following | ✅ | tabbed hub; cursor paging (`state/paged.dart`); pull-to-refresh |
| **Feed filters & sort** (website FilterButton parity) | ✅ | filter FAB + draft-then-apply sheet on Recent, hashtag feeds, and profile galleries (2026-07-29): sort created_at/reactions/file_bytes + order, static/animated, base (min side), size multi-select (≤3), exponential file-size range. Session-only per feed (`feedFiltersProvider`); default filters keep using the cheap dedicated endpoints, anything else reroutes through parameterized `GET /post` (`models/feed_filters.dart`, `ui/widgets/feed_filter.dart`) |
| **C1** Search (posts / hashtags / users) | ✅ | `ui/search_page.dart`, `ui/hashtag_feed_page.dart`; Search is a swipeable home page since 2026-07-26. Since 2026-07-29: all three tabs infinite-scroll (cursor paging), Users sort A–Z/Newest/Reputation, Hashtags sort Popular/A–Z/Recent, and Users/Hashtags double as browse-all directories on an empty query |
| **C1** Profiles + follow/unfollow | ✅ | `ui/profile_page.dart`; **redesigned 2026-07-11**: art-backdrop header with a compact info block, app bar collapsing into a pinned mini-bar, highlights showcase strip, richer meta/share/zoom quick wins. Since 2026-07-29: bios render the website's mini-markdown (`widgets/markdown_bio.dart`) and tapping the badge chips opens the badges sheet (`widgets/badges_sheet.dart`, `GET /badge`) |
| **C1** Reactions + comments | ✅ | `ui/widgets/reactions_bar.dart`, `comments_section.dart`; comment authors tap through to their profile (`author_public_sqid`, 2026-07-11); moderator take-downs render as tombstones (`deleted_by_mod`); long-press a comment's like button → who-liked sheet (2026-07-29) |
| **C1** Notifications + unread badge | ✅ | `ui/notifications_page.dart`; badge in the hub; tappable actor avatar → profile (`actor_public_sqid`, prod-live 2026-07-20); infinite-scroll load-more (2026-07-29); **live SSE stream** while foregrounded (`state/notifications_sse.dart` on `GET /realtime/notifications`: badge reconciles to the `connected` greeting, new items prepend into the list, immediate reconnect on the ~300 s bounded close, backoff on errors; the 60 s poll stays as background/fallback — 2026-08-11) |
| Artwork disk cache | ✅ | `cached_network_image` keyed by the immutable `art_url` (art: 1000 entries / 90 d; avatars: 7 d) + feed-page precache (`club/cache/artwork_cache.dart`); in releases since 1.0.7+10 |
| **Super posts** — 2×2 home-feed tiles | ✅ | one random post per home feed renders as a 2×2 tile (`SuperPostGridLayout` + `superPostIdProvider`, re-rolls on refresh); shipped 2026-07-16 |
| **Trending-hashtag bar** | ✅ | horizontal strip of top hashtags under the home top bar (`GET /api/hashtags/top` via `dioRoot`; server-driven rotation, no client timer); feeds-only, refetch on load + pull-to-refresh; shipped 1.0.14+19 |
| **feed-anim-sync** Synchronized animation playback | ✅ | animated posts derive their frame from the wall clock (`frame = f((now − epoch) mod loop)`, `club/anim/` + `state/animation_clock.dart`), so loop-compatible artworks stay frame-locked across tiles, scroll remounts, grid⇄detail, restarts, even devices; shared frame clock ticks only while animated tiles are visible; per-URL frame cache (96 MB LRU, 32 MB per-post cap → unsynced-fallback seam; JIT catch-up decode is the designated upgrade); "Play animations" local setting + OS reduce-motion honored (detail-page play overlay); publish sheet shows loop duration. **Verified on-device (Android) 2026-07-07.** As-uploaded `art_url` contract confirmed (msgs 0008/0009) |
| **C2** Publish (editor → Club) | ✅ | export bytes → conformance → metadata/license/visibility → upload; auth-gated (`ui/publish_page.dart` shows a sign-in prompt when signed out). Non-conformant sizes get a one-tap "Scale to W×H (nearest neighbor)" remedy (2026-07-29, engine isolate via `lib/share/artwork_rescale.dart`; hidden when the draft carries a `.mkpx` — resize in the editor instead) |
| **C3** Edit / remix (Club → editor) | ✅ | a Club post opens in the editor via `pendingClubEditProvider`; `ClubEditSource` provenance enables **Replace original** vs **Post as new** |
| **mkpx-upload** Layers-file attachments | ✅ | optional `.mkpx` on posts: share checkbox at publish, golden Edit button downloads `GET /v1/d/{sqid}.mkpx` and engine-loads the layered document, author attach/replace/detach menu (`api/mkpx_api.dart`). All UI gated on `GET /config` → `upload.mkpx.enabled`; **live on prod 2026-07-03** (contract: `reference/makapix-club/docs/mkpx-upload/API-CONTRACT.md`, E2E 23/23 in message 0004) |
| **C4** Settings — monitored hashtags | ✅ | `ui/settings_page.dart`; content-filter opt-in via `PATCH /user/{key}{approved_hashtags}` (§21); feeds re-filter server-side on save; moved to its own Settings sub-page 2026-07-24 |
| **C4** Artist dashboard (aggregate + per-post) | ✅ | `ui/artist_dashboard_page.dart`; totals + country/device/emoji breakdowns + per-post table + authenticated-only toggle (§19). Per-post `/post/{id}/stats` drill-in shipped 2026-07-29: owner ⋮ → **Statistics** (`ui/post_stats_page.dart` — 30-day daily-views trend, country/device/type/emoji breakdowns, force-refresh) |
| **C4** Post management + ZIP export | ✅ | `ui/post_management_page.dart`; bulk hide/unhide/delete + license + async ZIP data export (§20) via the unversioned `/api/pmd/*` (`ClubApiClient.dioRoot`). Single-post **Edit details / Hide / Delete** on the detail-page ⋮ since 2026-07-29 (`PATCH /post/{id}`, `POST`/`DELETE /post/{id}/hide`, `DELETE /post/{id}`; `ui/edit_post_details_page.dart`) |
| **Followers / following lists** | ✅ | the Followers stat on any profile opens `ui/follows_page.dart` (Followers · Following tabs, cursor-paged `GET /user/u/{sqid}/followers` / `…/following`); 2026-07-29 |
| **Artwork downloads (save-to-device)** | ✅ | detail-page ⋮ → **Download…** sheet: native format, upscaled WebP, alternative formats from `post.files`, and the `.mkpx` layers file (`/d/{sqid}*`, saved via the OS file dialog like the PMD ZIP); 2026-07-29 |
| **mod-hashtags** Moderator hashtags | ✅ | moderator-owned tags on posts: shield-marked display + "Tagged by a moderator" legend for artist/mods, "Edit mod hashtags" in the detail-page overflow menu (monitored quick-picks, optional audit note — `api/moderation_api.dart`), `mod_hashtags_updated` notification. Editor UI gated on `GET /config` → `max_mod_hashtags_per_post`; **live on prod 2026-07-05** (contract: `reference/makapix-club/docs/mod-hashtags/API-CONTRACT.md`; decisions: `docs/mod-hashtags/`) |
| **C4** Edit own profile | ✅ | `ui/edit_profile_page.dart`; avatar upload/remove (immediate, `POST`/`DELETE /user/{key}/avatar`) + tagline/bio via one `PATCH /user/{key}` of only the changed fields; reached from the own-profile header and the account page. **Not** included: website field, handle-in-page (handle change stays in Settings → Account), Markdown bio preview |
| **Use as profile photo** (avatar from post) | ✅ | detail-page ⋮ → preview dialog → `avatar-from-post` endpoint → profile reload; works on any viewable artwork; shipped 1.0.15+20 (2026-07-19) |
| **Account deletion** (Apple 5.1.1(v)) | ✅ | Settings → Account → Danger zone → type-DELETE page → `POST /v1/user/delete-account`; server-verified end-to-end on dev+prod (2026-07-16) |
| **ugc-safety** Report · block · rules gate | ✅ | Store-compliance safety (contract v1): full-screen **report** flow (posts/comments/users, works signed-out) from post/comment/profile entries; **block/unblock** + blocked-user profile state + Settings → Blocked users; `403 blocked` handled at all five interaction sites; published moderation contact (Settings/report footer/gate); first-run **community-rules gate** (versioned, reactive, covers Club pillar + Post-to-Club; references the formal **Terms of Service** since `kRulesVersion=2`); `new_report`/`report_resolved` notifications — since 2026-09-02 they show the reported artwork / user and open it (report-artwork message 0001). Gated on `GET /config` → `moderation`. **Live on prod since 2026-07-09** (app 1.0.9+14); store UGC declarations completed on **both stores** (Play IARC; iOS age rating 13+ + privacy label). Decisions: `docs/ugc-safety/` |
| **C5** Player Bar — player control + send-to-player | ✅ | list/control the user's online player devices (swap next/back, show artwork, play channel, pause, brightness, rotation, mirror — `api/player_api.dart`, `state/player_providers.dart`, `ui/widgets/player_bar.dart`); `SendTargetBinder` on home feeds / profile / hashtag feed / detail keeps "send to player" following what's on screen. Shipped 2026-06-29 (`9e14b69`); auto-hides on pages with no send target (2026-07-26) |
| **C5** Player registration & management | ✅ | register a physical player by device code, rename/delete, and a **My Players** screen (lifecycle only; certificates excluded); three entry points (☰ menu · Player Bar ⋮ · Account); pure Dart on the already-live API; shipped 1.0.14+19 (2026-07-17) |
| **Playlists** | — | **fully deferred (2026-07-07): don't develop until further notice** — server-side, playlists are mostly a planned-but-deferred feature. The app only *recognizes* playlist posts (badge on feed tiles; excluded from mkpx/mod/report menus) |
| **C4** Profile tabs: Private 🔒 · Gallery · Reacted ⚡ (+ Highlights 💎 strip) | ✅ | collapsing-header TabBar; own profiles get a **Private** tab (local My Drawings, left of Gallery — Gallery stays default; full Rename/Delete/New parity, tap opens the editor; 1.0.14+19) · **Reacted** = posts the user reacted to (`GET /user/u/{sqid}/reacted-posts`, signed-in viewers, cursor-tolerant paging; the pagination-500 and overscroll-crash follow-ups closed 2026-07-12/16) · **Highlights** became a display-only header **showcase strip** in the 2026-07-11 redesign (management still pending). Silent profile reload keeps tabs/scroll across refresh + edit-return |
| **C4 (rest)** highlights management (pin/unpin) · categories | ○ | not yet started |
| **C5 (rest)** soft-player kiosk · **C6** | ○ | not yet started. (The planned MQTT live notifications became the **SSE stream, shipped 2026-08-11** — the server's plane separation removed the notification MQTT topics, dissolving SPEC-CLUB §31.1's MQTT-auth question) |

## App shell
| Feature | Status | Notes |
|---|---|---|
| Two co-equal pillars under a neutral shell | ✅ | `lib/app.dart` (root) → `lib/shell/app_shell.dart`; **mounts ONE pillar at a time** (keeping both mounted, e.g. via `IndexedStack`, corrupts the Windows accessibility tree — see CLAUDE.md); the editor survives switches via an `.mkpx` session snapshot, Club state lives in long-lived Riverpod providers |
| Opens on the social experience | ✅ | launches on the Club pillar; welcome/sign-in funnel when signed out |
| Editor reachable without login | ✅ | no persistent pillar-switching chrome: the Club top bar's **Contribute** control opens a swipeable Contribute page (`ui/contribute_page.dart` — editor or direct file upload); the signed-out welcome page has its own Contribute button; editor ☰ → Club returns |
| Richer About dialog | ✅ | runtime version via `package_info_plus`, product blurb, website/repo/store/contact links, Flutter `LicensePage` (2026-07-24) |

## How to exercise it
- **Engine loop (no GUI):** `cargo test` and `cargo run -p makapix-cli -- run examples/showcase.txt render:0:out.png:6 state assert.roundtrip`
- **The app:** `./build.ps1 -Run` (or launch the prebuilt exe). It opens on the Club hub; tap the top-bar
  **Contribute** control → Makapix Editor to enter
  the editor. Draw with every tool, manage layers/frames, pick colors (RGB/HSV), set durations, play the
  animation, import an image, export PNG/GIF, save/open `.mkpx`; sign in to post to Club, or remix a Club post.

## Remaining gaps / next up (honest)
The editor pillar covers the whole core of SPEC.md (engine, tools, selections, animation, layers, undo,
`.mkpx`, FFI, three-row UI) but a handful of SPEC v1.1 items are still open; the Club pillar is complete
through C3 plus most of C4. Verified against the code 2026-07-26:

**Editor — SPEC.md items not yet built:**
1. **Mirror/symmetry drawing** (SPEC §28.3; pulled into v1 by §26.6) — nothing in engine or UI (the only
   "mirror" code is the Flip tool).
2. **APNG export** (a §26.4 *must-have*) — the codec decodes APNG but has no encoder; the export dialog
   offers PNG/GIF/WebP only (animated WebP, the nice-to-have, *is* done).
3. **Sprite-sheet export UI** — supported in `crates/codec`, not wired into the export dialog.
4. **Trim to non-transparent bounds** (§28.1) — resize + crop-to-selection exist; Trim doesn't.
5. **Reference image underlay** (§28.3) — not implemented.
6. ~~**Keyboard shortcuts** (§28.5)~~ — **✅ shipped 2026-08-16** (phase 6.A of
   `docs/keyboard-shortcuts/DESIGN.md` + ADR 0009): the whole ~45-Command catalog as fixed default
   Bindings (hybrid Primary-chord + tool-letter map), Hold bindings (Space-pan · Alt-eyedrop),
   broad Shift-constrain on every directional drag, the hold-Primary cheat-sheet overlay + the
   ☰ → Keyboard page, and the 6.B-ready stored-bindings loader. The rebinding UI (6.B) remains
   open. Android + keyboard: light device pass OK 2026-08-16 (including hold-Shift constrain);
   iPad ships best-effort by decision.
7. **Preferences screen** (§28.5) — individual settings persist ad-hoc via `shared_preferences`; no
   preferences UI (default canvas size, grid/onion defaults, theme, autosave interval, haptics,
   confirm-before-destructive).

**Editor — partial:**
8. **Onion skin** is an on/off toggle only — configurable range/opacity (§28.3) missing. (Neighbors
   **loop-wrap** since 2026-07-09: frame 0 ghosts the last frame as prev, the last frame ghosts frame 0 as
   next — all animations are assumed loops.)
9. ~~**Action journal** (§28.2)~~ — **resolved with the replay work (1.2.0, 2026-08)**: autosave + crash
   recovery (`editor_page.persistence.dart`) *and* the append-only action journal are both built — the
   journal (`app/lib/editor/replay/journal_recorder.dart`, crash-torn-line repair) powers Watch-replay
   and timelapse export, and doubles as the bug-repro format.
10. **Gradient per-stop position UI** — engine supports stop positions; the UI doesn't expose them.

**Club:**
11. **C4 remainder** — highlights *management* (pin/unpin) and categories. **Playlists are fully deferred**
    (2026-07-07; don't develop until further notice). **C5** — player control + send-to-player (2026-06-29),
    player registration & management (2026-07-17), and live notifications via SSE (2026-08-11, replacing
    the obsolete MQTT plan) shipped; the soft-player kiosk remains. **C6** moderation & extras — mod-hashtags shipped 2026-07-05; in-app moderation
    shipped 2026-08-06 (post kebab actions, comment mod menu, User Management incl. reputation +
    email reveal, Moderation hub + pending-approval queue); still website-only: reports queue,
    violations/badges panels, cross-user bulk PMD, recent-posts feed, pulse, audit log, metrics (see
    `SPEC-CLUB.md` §28).

**Deferred by decision, not omission:**
- **Localization** (post-v1 per §28.5; strings are currently hardcoded; design ready in
  `docs/i18n/DESIGN.md` — do not start unprompted) and **in-RAM compression of inactive frames** (file
  compression already done). (iPad support, deferred here until 2026-07-19, has since shipped: universal
  iPhone + iPad in iOS 1.0.16.)

## Local upload harness (optional)
The real publish flow runs against `development.makapix.club` / `makapix.club` (`config/club_config.dart`).
For offline testing of the multipart upload leg, `tools/mock_club_server.py` listens on
`http://localhost:8080` and writes received artifacts to `tools/uploads/`.
