# Briefing: synchronized animation playback on Club feed grids

This document is a handoff brief. It records the conclusions, rationale, and codebase context from a design
discussion about keeping animated artworks on the Club feed grid in sync with each other. It intentionally
contains **no step-by-step instructions** — it is the context from which an implementation session can plan
its own work. The architecture-rule change it depends on (see "Rule change", below) is already committed to
`CLAUDE.md` and `SPEC-CLUB.md`.

## The goal

When an artist posts multiple animated artworks that connect visually (e.g. a triptych whose panels form one
scene), those animations must never lose synchrony while displayed together on any feed. More generally: all
animated tiles on a feed should share one timeline, so that pieces authored to the same loop duration are
always frame-locked with each other.

## Current state of the code (verified 2026-07-07)

- Feed tiles: `app/lib/club/ui/widgets/feed_grid.dart` — `FeedGrid` (infinite-scroll `GridView.builder`) and
  `_PostTile`, which delegates artwork rendering to `PixelArtImage`.
- `PixelArtImage` (`app/lib/club/ui/widgets/common.dart:72`) wraps `CachedNetworkImage` (`cached_network_image`
  package, custom `artImageCache` cache manager, `FilterQuality.none` for nearest-neighbor pixel art). The
  artwork detail page (`app/lib/club/ui/artwork_detail_page.dart`, `_stage()`) uses the same widget.
- Animated posts are **animated GIF or animated WebP** rendered by Flutter's built-in multi-frame codec via
  `CachedNetworkImage`. There is **no** custom `Ticker`, `AnimationController`, `ImageStream` handling, or
  frame-timing logic anywhere in the Club client.
- `Post` model (`app/lib/club/models/post.dart`): `artUrl` is the display URL; `isAnimated => frameCount > 1`.
  The client parses `frame_count` but **not** the server's `min/max_frame_duration_ms` playability hints
  (SPEC-CLUB §7.3). Per-frame durations exist only inside the GIF/WebP bytes themselves.
- The feed never has `.mkpx` sources — only rendered raster URLs. `.mkpx` download is a separate,
  author-gated, bearer-authed call used only by the edit round-trip (`app/lib/club/api/mkpx_api.dart`).

### Why tiles desynchronize today

Each image animates on a private timeline that starts when *that* image finishes decoding. Independent causes
of drift: network load skew; lazy tile mount/unmount in `GridView.builder` during scroll (a remounted tile
restarts its loop); image-cache eviction; per-codec frame scheduling slipping under UI load. One exception:
tiles showing the *same URL* share one Flutter `ImageStream`, so exact duplicates are already in sync — but
only that case.

## The decided architecture: derive the frame from a clock, don't maintain a shared start

A shared *start event* ("start them all together") is the fragile version — it dies the moment a tile
remounts or an image loads late. The robust version makes the displayed frame a **pure function of the
clock**:

```
loopPosition = (now − epoch) mod totalLoopDuration
frame        = the frame whose cumulative duration spans loopPosition
```

with a **fixed absolute epoch** (Unix epoch works). Then synchrony is not a state that can be lost: any tile,
mounted at any moment, computes the same answer. This survives scrolling away and back, pausing offscreen
tiles (a battery win — a paused tile is still correct when it resumes), navigating grid ⇄ detail page, and
app restarts. With a wall-clock epoch, two devices side by side even show the same frame — a charming property
for a social pixel-art app.

Concrete shape (pure Dart, Club-side only):

- Keep `artImageCache` / `cached_network_image` for **fetching and disk-caching bytes**; replace only the
  **decode/paint** stage for animated posts.
- Decode bytes to frames + real per-frame durations client-side — via `ui.instantiateImageCodec` (note: it is
  sequential-only; to seek you pre-decode frames) or the pure-Dart `image` package in a background isolate
  (gives random access and can keep indexed/palette form). No server or model changes are needed: timing
  lives in the file.
- One shared frame-clock (a Riverpod provider fits the codebase) driving a `SyncedPixelArtImage` widget; one
  ticker per feed page, each tile repainting only when its computed frame index actually changes. Synced
  tiles change frames on the same tick, which batches repaints.
- Estimated size: a contained few hundred lines of Dart plus tests. Club unit tests remain pure Dart.

## Costs and caveats (acknowledged, with chosen mitigations)

1. **Memory is the one real budget item.** Pre-decoded RGBA frames cost width×height×4 per frame; the spec
   allows 256×256 × up to 1024 frames ⇒ a pathological worst case of ~256 MB per post. Typical art is far
   smaller, but the design needs a **frame-cache byte budget**: pre-decode fully under the cap; above it,
   fall back to sequential catch-up decode on mount, or to today's unsynced behavior for extreme outliers.
   Indexed (1 byte/pixel + palette) storage via the Dart `image` package shrinks this ~4×.
2. **Synchrony is only well-defined for equal loop durations.** Animations with different total loop lengths
   realign only at the LCM of their periods — no scheme fixes that. Wall-clock-modulo degrades gracefully:
   equal-duration pieces are perfectly locked; everything else is at least deterministic. The artist story
   implicitly assumes the connected series shares one loop duration; surfacing loop duration in the publish
   flow (so artists can verify a series matches) is a worthwhile companion change. The server already stores
   `min/max_frame_duration_ms` as hints.
3. **GIF timing quantization.** GIF delays are centisecond-granular and encoders commonly clamp tiny delays
   to 100 ms. Consistent (all clients use the same decoder) but potentially surprising to artists authoring
   fast animations; animated WebP (already the recommended publish format) is millisecond-precise.
4. **Clock choice.** `DateTime.now()` can step under NTP adjustment, causing a rare visible jump; a monotonic
   session clock avoids that but gives up cross-device sync. Decision: use wall clock and accept the rare
   jump.
5. **CPU is minor** for pixel-art frame paints at feed sizes.

## Product gap noted alongside (not part of this implementation, but recorded deliberately)

**Sync in time does not give adjacency in space.** Feeds sort by recency/engagement, column count varies with
window width, and other users' posts interleave — a connected triptych may render synced but scattered, out of
order, or wrapped across rows. If the deeper goal is "artworks designed to display together," the stronger
product feature is a **multi-panel post / series** concept (one post, N panels, guaranteed layout), with
global animation sync as the ambient mechanism underneath. Global sync is still worth building first: it makes
any future series feature work for free. Related future idea: once frame = f(wall clock), a per-post **phase
offset** metadata field becomes a cheap creative tool (e.g. a wave rippling across a series) — the design
should simply not hard-code the assumption that offset = 0.

## The Rust question, resolved

We examined whether this feature justifies (a) relaxing the "engine stays out of Club" rule or (b) a second
Rust engine for Club. Conclusions:

- **A second Rust engine: ruled out flatly.** It would duplicate the entire expensive perimeter — the
  hand-written C ABI, the Windows DLL + Android arm64/arm32 cross-compile pipeline, loader plumbing, build
  scripts — to reimplement decoding that `crates/codec` already does. If Rust ever earns its way into Club
  playback, the right move is a new narrow entry point on the **existing** FFI seam (thin glue over
  `crates/codec`), never a parallel engine.
- **For this feature, Rust is not needed.** What Rust playback would buy — indexed frame storage and true
  random-access frame seeking — only bites in the pathological tail, which the frame-cache budget already
  handles. Meanwhile FFI-in-the-feed has structural costs: Club tests currently run without the engine
  binary; FFI calls are synchronous (isolate plumbing needed); feed correctness would couple to the engine
  build for no present gain.
- **Rule change (already committed).** The old wording ("Club is Dart-only; the engine is never touched by
  the social code") banned the safe direction along with the dangerous one — SPEC-CLUB §4 already had Rust
  decoding downloaded artworks for edit/remix. `CLAUDE.md` and `SPEC-CLUB.md` (§1.2, §30.2) now state the
  rule as a **dependency direction, not a language ban**: the engine never depends on or knows about Club (no
  networking, async I/O, or social-domain concepts in Rust); Club may consume engine/codec services through
  the bytes-only FFI seam when there is a concrete reason; Dart fetches, Rust computes; Club unit tests keep
  running without the engine binary.
- **Kept open as a later optimization:** a `decode_animation` / `frame_at(time)` FFI entry point backed by
  `crates/codec`, as a drop-in replacement for the Dart decoder if profiling ever demands it. The
  derived-clock architecture is identical either way, so nothing in the Dart-first implementation is wasted.
  This also aligns with SPEC-CLUB §11 ("animated art plays via the engine renderer (or the downloaded
  GIF/WebP)") and the C5 player trajectory.

## Boundary conditions the implementation inherits

- Pure Dart, inside `app/lib/club/` (plus its tests in `app/test/`); no engine/FFI changes, no server or
  `Post`-model contract changes required.
- Preserve nearest-neighbor rendering (`FilterQuality.none`) and the existing `artImageCache` fetch path.
- Static posts (`frameCount == 1`) keep the current `CachedNetworkImage` path untouched.
- The detail page uses the same widget, so it inherits sync — grid → detail continuity is expected to come
  for free and is worth verifying.
- Club unit tests must keep passing with `flutter test` alone (no engine binary, no network).
