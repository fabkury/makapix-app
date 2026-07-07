// Widget tests for SyncedPixelArtImage + PixelArtImage routing — no engine, no
// network, no image codec. The decode pipeline is covered by animation_decode_test.dart;
// here the frame cache is PRE-WARMED with frames fabricated via `Picture.toImageSync`
// (dart:ui codec futures are unreliable under flutter_test's fake-async zone), so the
// widgets exercise their synchronous cache-hit path and the tests assert routing,
// clock registration, clock-driven frame selection, and painting — all deterministic.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/club/anim/animation_decoder.dart';
import 'package:makapix_club/club/anim/animation_timeline.dart';
import 'package:makapix_club/club/anim/frame_cache.dart';
import 'package:makapix_club/club/state/animation_clock.dart';
import 'package:makapix_club/club/state/animation_settings.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';
import 'package:makapix_club/club/ui/widgets/synced_pixel_art_image.dart';

const _url = 'https://vault.example/art.gif';

/// A hand-driven clock: registration is counted but never starts a real Ticker, and
/// tests move time with [setNow].
class _FakeClock extends SyncFrameClock {
  int regs = 0;
  @override
  void register() => regs++;
  @override
  void unregister() => regs--;
  void setNow(int ms) => state = ms;
}

class _FixedAutoplay extends AnimationAutoplayController {
  _FixedAutoplay(bool v) {
    state = v;
  }
}

Widget _harness(_FakeClock clock,
    {required Widget child, required AnimationFrameCache cache, bool autoplay = true}) {
  return ProviderScope(
    overrides: [
      animationFrameCacheProvider.overrideWithValue(cache),
      // Never used by cache-hit tests; a pending future keeps any stray decode inert.
      animationBytesFetcherProvider.overrideWithValue((_) => Completer<Never>().future),
      syncFrameClockProvider.overrideWith((ref) => clock),
      animationAutoplayProvider.overrideWith((ref) => _FixedAutoplay(autoplay)),
    ],
    child: MaterialApp(
      home: Center(child: SizedBox(width: 50, height: 50, child: child)),
    ),
  );
}

ui.Image _fabricatedFrame() {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  return rec.endRecording().toImageSync(1, 1);
}

/// Seed [cache] with a ready 2-frame animation (delays 100 + 200 ms after clamping,
/// like the GIF fixture the decode tests walk through the real codec).
void _prewarm(AnimationFrameCache cache) {
  cache.put(
    _url,
    DecodedAnimation(
      frames: [_fabricatedFrame(), _fabricatedFrame()],
      timeline: AnimationTimeline([0, 200]),
      byteSize: 8,
      isPartial: false,
    ),
  );
}

void main() {
  testWidgets('static posts keep the CachedNetworkImage path, no clock registration',
      (tester) async {
    final clock = _FakeClock();
    await tester.pumpWidget(_harness(clock,
        cache: AnimationFrameCache(), child: const PixelArtImage(url: _url)));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(SyncedPixelArtImage), findsNothing);
    expect(clock.regs, 0);
  });

  testWidgets('over-cap metadata routes to the unsynced fallback up front',
      (tester) async {
    final clock = _FakeClock();
    await tester.pumpWidget(_harness(clock,
        cache: AnimationFrameCache(),
        child: const PixelArtImage(
            url: _url, frameCount: 1024, width: 256, height: 256)));
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(SyncedPixelArtImage), findsNothing);
    expect(clock.regs, 0);
  });

  testWidgets('animated: loading placeholder while frames are not yet decoded',
      (tester) async {
    final clock = _FakeClock();
    // Empty cache + never-completing fetcher → the tile stays on the placeholder.
    await tester.pumpWidget(_harness(clock,
        cache: AnimationFrameCache(),
        child: const PixelArtImage(url: _url, frameCount: 2, width: 1, height: 1)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(clock.regs, 1, reason: 'registers on mount, before the decode lands');
    await tester.pumpWidget(_harness(clock,
        cache: AnimationFrameCache(), child: const SizedBox()));
    expect(clock.regs, 0);
  });

  testWidgets('cached animation paints a RawImage and the clock drives the frame',
      (tester) async {
    final clock = _FakeClock();
    final cache = AnimationFrameCache();
    _prewarm(cache);

    await tester.pumpWidget(_harness(clock,
        cache: cache,
        child: const Row(children: [
          Expanded(
              child: PixelArtImage(url: _url, frameCount: 2, width: 1, height: 1)),
          Expanded(
              child: PixelArtImage(url: _url, frameCount: 2, width: 1, height: 1)),
        ])));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(clock.regs, 2);

    List<dynamic> images() =>
        tester.widgetList<RawImage>(find.byType(RawImage)).map((w) => w.image).toList();

    // Loop is [0,100) → frame 0, [100,300) → frame 1 (fixture delays 100 + 200 ms).
    clock.setNow(0);
    await tester.pump();
    final frame0 = images();
    expect(frame0[0], same(frame0[1]), reason: 'duplicate tiles share one decode');

    clock.setNow(150);
    await tester.pump();
    final frame1 = images();
    expect(frame1[0], same(frame1[1]));
    expect(frame1[0], isNot(same(frame0[0])), reason: 'crossed the 100 ms boundary');

    clock.setNow(50); // back inside frame 0's span
    await tester.pump();
    expect(images()[0], same(frame0[0]),
        reason: 'frame is a pure function of the clock');

    clock.setNow(350); // 350 mod 300 = 50 → frame 0 again, a full loop later
    await tester.pump();
    expect(images()[0], same(frame0[0]),
        reason: 'wall-clock modulo wraps the loop');
  });

  testWidgets('tiles unregister from the clock when unmounted', (tester) async {
    final clock = _FakeClock();
    final cache = AnimationFrameCache();
    _prewarm(cache);
    await tester.pumpWidget(_harness(clock,
        cache: cache,
        child: const PixelArtImage(url: _url, frameCount: 2, width: 1, height: 1)));
    await tester.pump();
    expect(clock.regs, 1);
    await tester.pumpWidget(_harness(clock, cache: cache, child: const SizedBox()));
    expect(clock.regs, 0);
  });

  testWidgets('autoplay off: frame 0, no registration; forcePlay overrides',
      (tester) async {
    final clock = _FakeClock();
    final cache = AnimationFrameCache();
    _prewarm(cache);

    await tester.pumpWidget(_harness(clock,
        cache: cache,
        autoplay: false,
        child: const PixelArtImage(url: _url, frameCount: 2, width: 1, height: 1)));
    await tester.pump();
    // Frame 0 painted (a full cache entry serves frame-0 requests too), no clock.
    expect(find.byType(RawImage), findsOneWidget);
    expect(clock.regs, 0);
    final still = tester.widget<RawImage>(find.byType(RawImage)).image;
    clock.setNow(150); // even if time moves, a non-playing tile stays on frame 0
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(still));

    // The detail page's play override starts synced playback despite autoplay off.
    // (Same ProviderScope shape → Flutter updates the element, so `clock` persists.)
    await tester.pumpWidget(_harness(clock,
        cache: cache,
        autoplay: false,
        child: const PixelArtImage(
            url: _url, frameCount: 2, width: 1, height: 1, forcePlay: true)));
    await tester.pump();
    expect(clock.regs, 1);
  });

  testWidgets('a real SyncFrameClock ticks only while registered', (tester) async {
    final clock = SyncFrameClock();
    expect(clock.isTicking, isFalse);
    clock.register();
    expect(clock.isTicking, isTrue);
    clock.register();
    clock.unregister();
    expect(clock.isTicking, isTrue, reason: 'one registrant remains');
    clock.unregister();
    expect(clock.isTicking, isFalse);
    clock.dispose();
  });
}
