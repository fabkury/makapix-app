# Feed animation sync — synchronized playback of animated posts

Implemented 2026-07-07. Design brief: `prompt/feed-animation-sync-brief.md` (goals, rationale, the
Rust-question resolution and its panic-abort gate). Server exchange: `reference/makapix-club/message/0008`
(as-uploaded `art_url` guarantee + proposed `total_duration_ms` field).

## The idea

When an artist posts multiple animated artworks that connect visually (a triptych sharing one loop
duration), the panels must never drift apart on a feed. Instead of maintaining a shared *start* (fragile —
dies on tile remount or a late decode), the displayed frame is a **pure function of the wall clock**:

```
loopPosition = (nowMs − Unix epoch + phaseOffsetMs) mod totalLoopDurationMs
frame        = the frame whose cumulative duration spans loopPosition
```

Synchrony is not a state that can be lost: any tile, mounted at any moment, computes the same answer. It
survives scroll remounts, cache eviction, grid ⇄ detail navigation, backgrounding, app restarts — and two
devices side by side show the same frame. `phaseOffsetMs` is a parameter (default 0), so a future per-post
phase-offset field (a wave rippling across a series) needs no rework. Synchrony is only well-defined for
equal loop durations; unequal loops realign at the LCM of their periods — deterministic, gracefully degraded.

## Architecture (pure Dart, Club-side; no engine/FFI, no server/model changes)

| Piece | File | Role |
|---|---|---|
| `AnimationTimeline` | `app/lib/club/anim/animation_timeline.dart` | pure clock→frame mapping; delay clamp (≤10 ms → 100 ms, the browser convention, matching website playback) + 30 ms min-loop floor; `computeTotalDurationMs` shared with the publish sheet |
| `ByteBudgetLru` | `app/lib/club/anim/byte_budget_lru.dart` | generic byte-accounted LRU with `onEvict` |
| `DecodedAnimation` / `AnimationFrameCache` | `app/lib/club/anim/frame_cache.dart` | per-URL cache of decoded `ui.Image` frames; 96 MiB global budget, 32 MiB per-post cap (both tunable consts); **refcounted** (cache holds one ref, each widget one) so an eviction mid-paint never disposes an image under the raster thread |
| `AnimationDecoder` | `app/lib/club/anim/animation_decoder.dart` | `ui.instantiateImageCodec` walk; concurrent byte fetches, **serialized codec walks** (single FIFO worker), per-URL in-flight dedupe; three-way `DecodeResult`: success / **overCap** / error |
| `SyncFrameClock` | `app/lib/club/state/animation_clock.dart` | keepAlive StateNotifier owning a raw `Ticker`; state = wall-clock ms sampled **once per tick**; runs only while ≥1 synced widget is registered and the app is foregrounded (`inactive` = desktop focus loss still plays) |
| `AnimationAutoplayController` | `app/lib/club/state/animation_settings.dart` | local "Play animations" switch (`club.animation_autoplay`, SharedPreferences, default ON, applies live) |
| `SyncedPixelArtImage` | `app/lib/club/ui/widgets/synced_pixel_art_image.dart` | the player: registers with the clock, watches it through a `select` on its computed frame index (rebuilds only on index change), paints `RawImage` with `FilterQuality.none` |
| `PixelArtImage` routing | `app/lib/club/ui/widgets/common.dart` | `frameCount/width/height/forcePlay` params (server hints); static → untouched CachedNetworkImage path; animated under cap → synced; over cap / unknown dims → fallback seam |

Fetch/disk-cache is unchanged: bytes still come from `artImageCache` (`getSingleFile` → `readAsBytes`), and
feed precache stays bytes-only (no ImageCache decode) — the frame cache is the sole decoder for animated
posts. First paint waits for the full decode (the existing placeholder), then appears already in sync.

**Surfaces wired:** feed grid, search results, artwork detail (`_stage`, which also carries the play
overlay), comments header, reactions page, post management. Notification 40×40 thumbs stay static.

**Motion controls:** OS reduce-motion (`MediaQuery.disableAnimations`) or the settings switch freeze
animated posts on frame 0 (via a cheap frame-0-only partial decode). The detail page then shows a play/stop
overlay; playback started there joins the shared clock (in phase with everything else).

## The fallback seam (and its designated upgrade)

`buildUnsyncedAnimatedFallback` in `synced_pixel_art_image.dart` is the **one** route for every animated
post that is not pre-decoded: detected up front from server metadata, or mid-decode when the codec's
authoritative frame count pushes the real size over the cap. Today it renders native unsynced playback
(exactly the pre-feature behavior — it doubles as a one-edit kill switch). The **designated upgrade** is a
just-in-time catch-up decoder (decode to the clock-computed position on mount, then decode just-in-time)
that would keep even over-cap posts on the shared clock; it slots in behind this seam and
`AnimationDecoder.request` without touching any widget. Trade-offs of JIT (perpetual decode CPU, per-remount
catch-up bursts, lag-under-load desync risk) are analyzed in the brief's session notes — revisit if
real-world posts hit the cap more than expected.

## The frame_count trust model

`Post.frameCount/width/height` come from the server and can disagree with the file (e.g. encoders that merge
equal sequential frames — Pillow does this for WebP). They are **routing/budget hints only**:

- Server-says-static-but-animated → today's native unsynced path. Server-says-animated-but-static → synced
  path shows one frame, and the widget skips clock registration. Both benign.
- The decoder re-verifies the per-post cap against `codec.frameCount` + actual dimensions right after
  `instantiateImageCodec` (before walking frames) and returns `overCap` → the fallback seam, not the error
  widget. Cache accounting always uses actually-decoded frames.
- Sync itself is immune: the timeline is built from decoded durations, and a merge of equal frames preserves
  the total loop duration — merged and unmerged panels of a series stay locked (we sync on time, not index).

## Publish companion

`PublishDraft.totalDurationMs` (nullable) is shown on the publish sheet ("· 1.2 s loop") so an artist can
verify a series shares one loop. Editor path computes it from the engine state JSON's per-frame
`duration_us`; direct upload walks the already-instantiated codec. Same clamp rules as playback
(`AnimationTimeline.computeTotalDurationMs`). Best-effort — never blocks posting.

## Tests (`flutter test` alone — no engine, no network)

- `test/animation_timeline_test.dart` — clamps, min-loop padding, modulo at epoch scale, boundary
  ownership, phase offsets, `computeTotalDurationMs` parity.
- `test/byte_budget_lru_test.dart` — byte accounting, LRU order, recency refresh, overwrite/remove/clear
  eviction, over-budget refusal.
- `test/animation_decode_test.dart` — decodes an in-code 2-frame GIF fixture (`test/anim_fixtures.dart`);
  clamped timeline, in-flight dedupe, refcount disposal, partial→full upgrade, the hint-mismatch overCap
  path, fetch/decode errors. Codec futures need the real event loop → `tester.runAsync`.
- `test/synced_image_widget_test.dart` — routing (static / over-cap / synced), placeholder-until-decoded,
  hand-driven clock moves frames identically across duplicate tiles, register/unregister lifecycle,
  autoplay-off + `forcePlay`, real `SyncFrameClock` tick gating.
