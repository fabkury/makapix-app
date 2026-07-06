# Makapix Club app — Implementation Status (2026-07-05)

Honest coverage of **both** of the app's co-equal pillars. The **Makapix Editor** (editor engine + Flutter
shell) is built and runnable on this workstation. The **Makapix Club** social layer (see
[`SPEC-CLUB.md`](SPEC-CLUB.md)) is **code-complete through phases C0–C3** (auth · read & discover · create &
publish · edit & remix) against the live server contract; **C4** (curate/manage) is **in progress** — the
artist dashboard, settings (monitored hashtags), and post management + ZIP data export are done; playlists,
highlights, categories and reporting remain. **C5–C6** (real-time & players · moderation & extras) are **not
yet** started. The two pillars sit under a neutral app shell
(`lib/shell/app_shell.dart`): the app **opens on the Club pillar** (signed-out users get Club's welcome/sign-in
funnel) and the editor is a co-equal feature reachable **without login** via the centre ⊕ Create button.
Legend: **✅ done & tested** · **◑ partial** (engine done, UI/edges pending) · **○ stubbed / not yet**.

## Build artifacts
- `crates/engine` — pure deterministic core (dependency-free). **150 lib + 13 scenario + 4 fuzz + 1 perf tests.**
- `crates/codec` — image import/export (`image` crate). **2 tests.**
- `crates/ffi` — C-ABI DLL (`makapix_ffi.dll`). **2 tests** (lifecycle + GIF import→export).
- `crates/cli` — `mkpx` headless harness (renders PNG, prints oracles/JSON; exit-code CI gate).
- `app/` — Flutter Windows app → `app/build/windows/x64/runner/Release/makapix_club.exe` (+ bundled DLL).
- **Total: 174 Rust tests green.** Engine loop verified by rendering `examples/demo.txt` & `showcase.txt`.

## Core first-class features
| Feature | Status | Notes |
|---|---|---|
| Rust core + Flutter UI | ✅ | engine via C-ABI DLL + `dart:ffi` |
| Compact three-row UI/UX | ✅ | row-1 tool options · row-2 palette · row-3 tools (a **2-row, horizontally-scrolling, user-reorderable** tool grid) |
| Configurable tool order | ✅ | "Rearrange" mode: drag-and-drop tools + ◀▶ move-one-slot buttons; order persisted across launches (shared_preferences) |
| Mobile-first, responsive to tablet | ✅ | mobile-first column; **wide viewports (≥1000px) move frames+layers into a right side panel** |
| Lossless `.mkpx` (frames + layers) | ✅ | chunked, versioned (v4), sparse tiles; round-trip is a test gate |
| Off-canvas gutter + overscan view | ✅ | Move preserves pixels pushed off-canvas in a 1-canvas gutter each side (3×3 storage); paint stays canvas-only; ☰ View → Overscan reveals the dimmed gutter (keep-zoom-pan). See SPEC §8.3 |
| Memory efficient (1024f / 256² / RGBA, per-frame undo) | ✅ | tiled COW + lazy alloc; 500f×20L = **48 MiB**, verified no-crash |
| Post to Makapix Club (publish) | ✅ | "Post to Club" exports the document (static→PNG, animated→GIF) and hands **only bytes** to `lib/club`, which runs conformance → metadata/license/visibility → bearer-auth upload (the real C2 publish flow). `tools/mock_club_server.py` remains an optional local harness; see the Club table below. |

## Tools & editing
| Feature | Status | Notes |
|---|---|---|
| Up to 1024 frames / 64 layers | ✅ | enforced caps |
| 128 undo/redo per frame + auto compaction | ✅ | global timeline, per-frame cap, absolute tile patches |
| Pencil / Paintbrush / Airbrush (configurable size) | ✅ | airbrush seeded & reproducible |
| **Precision mode** (off-finger reticle, act-by-button) | ✅ | a per-tool toggle on Pencil/Brush/Airbrush/Eraser/Dodge/Burn/Eyedropper/Select Color; drag moves a ✛ reticle off the finger; arrows nudge 1px; DRAW/SPRAY = one dab, PICK = colour pick, SELECT = colour selection at the reticle; HOLD toggle = continuous stroke/spray while dragging (paint tools only). Reticle frames the target pixel without covering it |
| Bucket fill (contiguous / discontiguous, threshold) | ✅ | flood oracle-tested |
| Eraser (square / round, size) | ✅ | |
| **Figures** Line / Rectangle / Ellipse (draw → adjust → commit) | ✅ | drag previews an uncommitted figure with draggable endpoint handles; re-drag either handle (tap near, not on) to fine-tune; Fill/Outline updates the preview live; Commit ✓ rasterizes (one undo step), Cancel ✗ discards. Engine: `ShapeSet/ShapeCommit/ShapeCancel` |
| Select by color threshold (cont/discont) | ✅ | |
| Select rectangle / ellipse / circle / freeform | ✅ | polygon via freeform lasso path |
| Selection ops Add / Subtract / Union / Intersect / Invert | ✅ | set-algebra tested |
| HSV-shift selected pixels | ✅ | closed-form oracle |
| Brightness/Contrast (layer/selection, Frame scope) | ✅ | HSV-style tool: live engine preview, ±255 brightness + ±100% contrast around the 128 pivot; a non-zero adjustment is a draft resolved by the commit-menu (Commit = one undo step); closed-form oracle |
| Gradient (2/3 colors, positions, alpha) | ✅ | linear + radial; tri-color; alpha; optional seeded dither |
| Darkener / Lightener brush (intensity, size) | ✅ | dodge/burn via HSV-V |
| Selected pixels move / copy / cut / paste | ✅ | |
| Copy pixels frame→frame | ✅ | `PasteToFrame` in engine/DSL (UI pastes to active frame) |
| Move/Duplicate layers from 1 frame → N frames | ✅ | layer options sheet → "Copy to all frames" (`DuplicateLayerToFrames`) |
| Merge down (layer onto the one below) | ✅ | layer options sheet → "Merge down" (`MergeDown`): compositor-exact blend with the source's opacity, merged layer keeps the below layer's settings; one undo step; bottom/locked-below guarded |
| Duplicate / reorder animation frame | ✅ | film-roll of frame previews at the top of the canvas (tap to go to a frame; long-press for duplicate/duration/move/delete); engine-rendered cached thumbnails |
| Per-frame duration 16.6–1000 ms + bulk tools | ✅ | µs-precise; UI dialog (this frame / all frames / fps presets) |
| Palettes: create/edit/save/load, add/remove/edit/dup color, RGB+HSV | ✅ | multiple palettes (selector + new), add/edit/duplicate/remove color (long-press swatch), RGB+HSV picker, eyedropper, **save/load `.gpl`/JSON**, embedded in `.mkpx` |
| Select multiple layers, move together | ✅ | layer "move group" toggle + nudge pad → `NudgeLayers` (one undoable edit) |
| Import GIF/WebP/PNG/APNG/JPEG/BMP (crop/scale, start-frame, as-layer) | ✅ | all formats; import options dialog; **interactive crop-rectangle** (drag a region over the source preview) |
| Export PNG / sprite-sheet / GIF | ✅ | PNG + animated GIF wired in UI; sprite-sheet in codec |
| Canvas ops: invert, resize, crop-to-selection, **rotate canvas 90/180/270, flip canvas H/V** | ✅ | rotate/flip-canvas in the timeline ☰ menu's grouped **Canvas** submenu; resize/crop/rotate undoable (canvas size travels with the edit) |
| **Flip & Rotate tools: layer/selection-scoped** | ✅ | Flip H/V and Rotate act on the active layer, or just the selected pixels (the selection mask transforms with them); Rotate adds 90/180/270 instant + an "Angle" draft with an on-canvas handle (semitransparent preview, Commit = one undo), rotate-about-centre, clip to canvas |
| `.mkpx` compression | ✅ | per-tile RLE (v2 format, v1 still readable) — a 10k-layer project shrank **48 MB → 1.2 MB** |
| Drag-and-drop reorder (frames & layers) | ✅ | long-press to drag in the timeline / layer strip (button reorder also kept) |

## Club social layer (C0–C3, Dart-only — `app/lib/club/`)
| Area | Status | Notes |
|---|---|---|
| **C0** GitHub OAuth + PKCE + token store | ✅ | server-brokered OAuth via **HTTPS App Links** (`flutter_web_auth_2`; app id `club.makapix.app`); tokens at rest in `flutter_secure_storage`; single-flight 401→refresh→retry (`api/club_api_client.dart`). **Verified on-device** (App Links verified on both hosts; returns into the app). Residual one-tap Custom-Tab return is accepted (§6.3) |
| **C0** Welcome / sign-in funnel | ✅ | signed-out users land on `ClubWelcomePage` (featured grid + sign-in), matching the website |
| **C0b** In-app account creation | ✅ | **chosen-password** register → single 6-digit OTP verify → auto sign-in (A2) → welcome wizard (handle w/ live availability + **Back** · avatar/bio · `complete-welcome`). "Verify your email" recovery + forgot-password (OTP) on sign-in; Settings → Account (change password/handle, linked logins). Handle rules mirror the server (1–32 printable-Unicode code points). **Verified end-to-end on-device against dev.** `ui/auth/*`, `state/registration_controller.dart` (`docs/plans/C0b-account-creation.md`) |
| **C1** Feeds: Recent / Recommended / Following | ✅ | tabbed hub; cursor paging (`state/paged.dart`); pull-to-refresh |
| **C1** Search (posts / hashtags / users) | ✅ | `ui/search_page.dart`, `ui/hashtag_feed_page.dart` |
| **C1** Profiles + follow/unfollow | ✅ | `ui/profile_page.dart` |
| **C1** Reactions + comments | ✅ | `ui/widgets/reactions_bar.dart`, `comments_section.dart` |
| **C1** Notifications + unread badge | ✅ | `ui/notifications_page.dart`; badge in the hub |
| **C2** Publish (editor → Club) | ✅ | export bytes → conformance → metadata/license/visibility → upload; auth-gated (`ui/publish_page.dart` shows a sign-in prompt when signed out) |
| **C3** Edit / remix (Club → editor) | ✅ | a Club post opens in the editor via `pendingClubEditProvider`; `ClubEditSource` provenance enables **Replace original** vs **Post as new** |
| **mkpx-upload** Layers-file attachments | ✅ | optional `.mkpx` on posts: share checkbox at publish, golden Edit button downloads `GET /v1/d/{sqid}.mkpx` and engine-loads the layered document, author attach/replace/detach menu (`api/mkpx_api.dart`). All UI gated on `GET /config` → `upload.mkpx.enabled`; **live on prod 2026-07-03** (contract: `reference/makapix-club/docs/mkpx-upload/API-CONTRACT.md`, E2E 23/23 in message 0004) |
| **C4** Settings — monitored hashtags | ✅ | `ui/settings_page.dart`; content-filter opt-in via `PATCH /user/{key}{approved_hashtags}` (§21); feeds re-filter server-side on save |
| **C4** Artist dashboard (aggregate) | ✅ | `ui/artist_dashboard_page.dart`; totals + country/device/emoji breakdowns + per-post table + authenticated-only toggle (§19). Per-post `/post/{id}/stats` drill-in deferred |
| **C4** Post management + ZIP export | ✅ | `ui/post_management_page.dart`; bulk hide/unhide/delete + license + async ZIP data export (§20) via the unversioned `/api/pmd/*` (`ClubApiClient.dioRoot`) |
| **mod-hashtags** Moderator hashtags | ✅ | moderator-owned tags on posts: shield-marked display + "Tagged by a moderator" legend for artist/mods, "Edit mod hashtags" in the detail-page overflow menu (monitored quick-picks, optional audit note — `api/moderation_api.dart`), `mod_hashtags_updated` notification. Editor UI gated on `GET /config` → `max_mod_hashtags_per_post`; **live on prod 2026-07-05** (contract: `reference/makapix-club/docs/mod-hashtags/API-CONTRACT.md`; plan: `docs/mod-hashtags/`) |
| **C4** Edit own profile | ✅ | `ui/edit_profile_page.dart`; avatar upload/remove (immediate, `POST`/`DELETE /user/{key}/avatar`) + tagline/bio via one `PATCH /user/{key}` of only the changed fields; reached from the own-profile header and the account page. **Not** included: website field, handle-in-page (handle change stays in Settings → Account), Markdown bio preview (plan: `docs/profile-editing/`) |
| **C4 (rest)** playlists · highlights · categories · reporting · **C5–C6** | ○ | not yet started |

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
The editor pillar covers the whole core of SPEC.md (engine, tools, selections, animation, layers, undo,
`.mkpx`, FFI, three-row UI) but a handful of SPEC v1.1 items are still open; the Club pillar is complete
through C3 plus most of C4. Verified against the code 2026-07-05:

**Editor — SPEC.md items not yet built:**
1. **Mirror/symmetry drawing** (SPEC §28.3; pulled into v1 by §26.6) — nothing in engine or UI (the only
   "mirror" code is the Flip tool).
2. **APNG export** (a §26.4 *must-have*) — the codec decodes APNG but has no encoder; the export dialog
   offers PNG/GIF/WebP only (animated WebP, the nice-to-have, *is* done).
3. **Sprite-sheet export UI** — supported in `crates/codec`, not wired into the export dialog.
4. **Trim to non-transparent bounds** (§28.1) — resize + crop-to-selection exist; Trim doesn't.
5. **Reference image underlay** (§28.3) — not implemented.
6. **Keyboard shortcuts** (§28.5) — no key handling in the editor (tools, undo/redo, save, play/pause,
   zoom, frame prev/next).
7. **Preferences screen** (§28.5) — individual settings persist ad-hoc via `shared_preferences`; no
   preferences UI (default canvas size, grid/onion defaults, theme, autosave interval, haptics,
   confirm-before-destructive).

**Editor — partial:**
8. **Onion skin** is an on/off toggle only — configurable range/opacity (§28.3) missing.
9. **Action journal** (§28.2) — autosave + crash recovery are fully built
   (`editor_page.persistence.dart`); the append-only action journal (bug-repro format) was never added.
10. **Gradient per-stop position UI** — engine supports stop positions; the UI doesn't expose them.

**Club:**
11. **C4 remainder** — playlists, highlights, categories, reporting; **C5** real-time & players; **C6**
    moderation & extras (mod-hashtags already shipped; see `SPEC-CLUB.md` §28).

**Deferred by decision, not omission:**
- **iOS build** — cannot be built on this Windows workstation; deferred to a cloud macOS CI runner
  (SPEC §3.1). All shared code is iOS-clean and the engine is integer-deterministic, so this is
  build/packaging only.
- **Localization** (post-v1 per §28.5; strings are currently hardcoded) and **in-RAM compression of
  inactive frames** (file compression already done).

## Local upload harness (optional)
The real publish flow runs against `development.makapix.club` / `makapix.club` (`config/club_config.dart`).
For offline testing of the multipart upload leg, `tools/mock_club_server.py` listens on
`http://localhost:8080` and writes received artifacts to `tools/uploads/`.
