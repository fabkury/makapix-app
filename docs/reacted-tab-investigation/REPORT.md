# The "Reacted tab" bug investigation — missing counts + crash on scroll

**Date:** 2026-07-16 · **Status:** diagnosed; app mitigation shipped in this repo, server fix requested.

## Symptom as reported

On the user's own profile → **Reacted** tab (Pixel 10 Pro XL, sideloaded 1.0.11/vc15):

1. Grid tiles showed **0 reactions / 0 comments** for every artwork.
2. Scrolling the tab **crashed the app to the home screen**, reproducibly.

These turned out to be **two independent bugs**, and the crash is **not Reacted-specific at all**.

---

## Bug 1 — zero counts: server payload gap

`GET /api/v1/user/u/{sqid}/reacted-posts` returns a slimmer item shape than every other feed.
`ReactedPostItem` (server `api/app/schemas.py`) carries only
`id, public_sqid, title, art_url, width, height, owner*, reacted_at, emoji, created_at,
frame_count, files` — **no `reaction_count`, `comment_count`, or `user_has_liked`**.

The app's deliberately tolerant `Post.fromJson` (`app/lib/club/models/post.dart`) parses the
missing fields as `0 / 0 / false`, and the grid tile's info bar faithfully renders the zeros.
(Ironic side effect: nothing in the Reacted tab shows as liked, even though by definition the
viewer reacted to all of it.)

**Decision:** fix on the server — add the three fields to `ReactedPostItem`, populated with a
batched per-page count query (exact precedent: `api/app/routers/pmd.py`, the `reaction_counts`
map). Backward-compatible contract addition; the app needs zero changes. Requested via the
message-exchange convention: **`docs/reacted-posts-counts/messages/` in the server repo**
(kickoff message `0001-app-reacted-posts-counts-request.md`). No app-side mitigation (hiding the
info bar) — worse result for more work.

---

## Bug 2 — crash on scroll: Impeller/Vulkan engine bug on PowerVR (Pixel 10)

### The crash

Raster-thread SIGABRT. Captured live (logcat main buffer) at the moment of a repro:

```text
E flutter: [ERROR:impeller/renderer/backend/vulkan/allocator_vk.cc(361)] Impeller validation:
           Unable to allocate Vulkan Image: ErrorCompressionExhaustedEXT
           Type: Texture2D  Usage: { ShaderRead, RenderTarget }  Format: R8G8B8A8Unorm
E flutter: [ERROR:impeller/renderer/render_target.cc(439)] Could not create color texture.
E flutter: [ERROR:impeller/renderer/render_target.cc(26)] Render target does not have color
           attachment at index 0.   (×3)
F flutter: [FATAL:impeller/display_list/canvas.cc(1471)] Check failed: back_texture.
           Context is valid:0
```

A second flavor of the same failure appears as a SIGSEGV (null deref, fault addr `0x20`) in the
same `libflutter.so` region.

### Root cause chain

1. The Pixel 10 Pro XL ("mustang", Tensor G5) has an **Imagination PowerVR GPU** that uses
   fixed-rate compression for textures; its compression **metadata pool is finite**.
2. Normal art browsing (feeds/grids keep many image textures alive) gradually **exhausts the
   pool**.
3. The next allocation of an offscreen **backdrop texture** fails with
   `VK_ERROR_COMPRESSION_EXHAUSTED_EXT`, and Impeller **FML_CHECK-aborts** instead of degrading.
4. The app's **only** backdrop-texture consumer is **Android's stretch-overscroll effect**
   (framework-level; the app has no `BackdropFilter` and no advanced blend modes). Stretch fires
   whenever a scrollable is dragged past its edge.

### Why it masqueraded as a Reacted-tab bug

The Reacted tab is short content (one page ≈ a couple of screens), so "scrolling down" hits the
bottom edge — and the stretch effect — almost immediately; and it was typically visited **after**
long browsing sessions, when the compression pool was already nearly drained. The device's crash
buffer shows the identical fingerprint on 07-07 (Reacted tab ship-day testing), 07-12 (×3,
Reacted pagination testing), and 07-16 (×3) — always raster thread, always `back_texture`.

### Controlled experiment (2026-07-16, on device)

| Test | Prediction | Result |
|---|---|---|
| Gallery tab, stretch past the bottom edge | crash | **crashed** (`back_texture` abort captured live) |
| Reacted tab, gentle mid-content scroll (no edges) | no crash | **no crash** |

Crash follows the **overscroll stretch**, not the Reacted data. Diagnosis confirmed.

### Not to be confused with

The burst of main-thread `mkpx_run` scudo-OOM SIGABRTs in the same day's logs (06:05–06:12) was
the **memlab ladder** deliberately probing the allocator wall (`docs/memlab/REPORT.md`) — an
unrelated, expected signature. When reading this device's crash buffer, check the thread name:
memlab aborts are `lub.makapix.app` main thread through `mkpx_run`; this bug is `N.raster`.

### Upstream status

- Issue: [flutter/flutter#187564](https://github.com/flutter/flutter/issues/187564) —
  "[Impeller][Vulkan] Unhandled `VK_ERROR_COMPRESSION_EXHAUSTED_EXT` render-target allocation
  failure crashes the raster thread on PowerVR (Pixel 10)".
- Fix: [flutter/flutter#187586](https://github.com/flutter/flutter/pull/187586) — "Retry
  uncompressed when fixed-rate compression is exhausted", **merged to master 2026-06-09**.
- **Not in any stable release**: the 3.44 line's engine was cut 2026-05-27; hotfixes 3.44.1–3.44.6
  don't carry it (checked the stable CHANGELOG). This repo pins Flutter 3.44.1.

### Decision: app-side mitigation now, upstream fix later

`app/lib/app.dart` sets a `GlowOverscrollBehavior` on the `MaterialApp`: Android overscroll uses
the classic **glow** indicator instead of the Material-3 **stretch**. That removes the app's sole
backdrop-texture request, so the exhausted pool has nothing left to kill. Cosmetic trade-off only.

**Caveat:** the pool exhaustion itself is a device-wide driver condition; only the engine fix
truly cures it. Until the pinned Flutter carries #187586:

- don't reintroduce the stretch effect;
- don't add other backdrop consumers (`BackdropFilter`, blur dialogs, advanced `BlendMode`s) —
  they would resurface the crash on PowerVR devices.

**Revisit trigger:** on the next Flutter upgrade, check whether the engine includes #187586
(master 2026-06-09 or later); if so, the glow behavior may be reverted to stretch — or kept, as a
taste call.

### Follow-ups (done 2026-07-16)

- Mitigation **device-verified**: after installing the glow build, the previous repro steps
  produced zero new crash-buffer records on the Pixel 10.
- Workstation Flutter upgraded 3.44.1 → **3.44.6** (latest stable hotfix; unrelated Android
  Impeller fixes, e.g. shutdown/rotation crash). `flutter analyze` clean, full test suite green.
- **Cherry-pick of #187586 into 3.44 stable requested upstream**: the `cp: stable` label needs
  triage rights, so the request was filed as a comment with the required CP fields —
  <https://github.com/flutter/flutter/pull/187586#issuecomment-4994275706>. If granted, the fix
  arrives in a 3.44.x hotfix; either way, re-check on the next Flutter upgrade.

---

## Diagnostic notes for next time

- `adb logcat -d -b crash` retains **weeks** of crash records across reinstalls — read it before
  asking for a fresh repro.
- The raster thread's `E flutter:` Impeller validation preamble (the actual root cause) lands in
  the **main** buffer only; the crash buffer has just the abort message and stack. Capture both:
  `adb logcat -b main,crash flutter:V libc:F DEBUG:F "*:S"`.
- A release-build stack through an exported FFI symbol (`mkpx_run+244`) is trustworthy; unlabeled
  frames around it are static Rust internals (no dynsym entries).
