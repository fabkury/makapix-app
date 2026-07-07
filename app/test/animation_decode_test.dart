// Decoder + frame-cache tests — no engine, no network.
//
// Orchestration (dedupe, caching, partial→full, refcounting, cap re-check, error
// mapping) is tested against an injected FAKE codec, because dart:ui codec futures
// are unreliable under flutter_test's fake-async zone (the decode completes but its
// delivery through multi-hop future chains can stall — a test-env artifact only).
// Real-codec fidelity (the GIF fixture's frames and delays) is covered by one
// probe-style test that awaits the codec DIRECTLY inside `tester.runAsync`, the one
// shape that resolves reliably (crop_widget_test.dart precedent).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/anim/animation_decoder.dart';
import 'package:makapix_club/club/anim/frame_cache.dart';

import 'anim_fixtures.dart';

const _url = 'https://vault.example/art.gif';

ui.Image _frame() {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  return rec.endRecording().toImageSync(1, 1);
}

class _FakeFrameInfo implements ui.FrameInfo {
  _FakeFrameInfo(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}

/// A 1×1 fake codec mirroring the GIF fixture: frame 0 with a 0 ms delay (clamps to
/// 100 ms), frame 1 with 200 ms. `getNextFrame` wraps like the real codec.
class _FakeCodec implements ui.Codec {
  _FakeCodec(this.frames);
  factory _FakeCodec.twoFrame() => _FakeCodec([
        _FakeFrameInfo(_frame(), Duration.zero),
        _FakeFrameInfo(_frame(), const Duration(milliseconds: 200)),
      ]);
  final List<_FakeFrameInfo> frames;
  int _next = 0;
  bool disposed = false;
  @override
  int get frameCount => frames.length;
  @override
  int get repetitionCount => -1;
  @override
  Future<ui.FrameInfo> getNextFrame() async => frames[_next++ % frames.length];
  @override
  void dispose() => disposed = true;
}

AnimationDecoder _decoder(
  AnimationFrameCache cache, {
  int? capBytes,
  Future<Uint8List> Function(String)? fetch,
  Future<ui.Codec> Function(Uint8List)? codec,
}) =>
    AnimationDecoder(
      cache: cache,
      fetchBytes: fetch ?? ((_) async => Uint8List(0)),
      perPostCapBytes: capBytes ?? kPerPostCapBytes,
      instantiateCodec: codec ?? ((_) async => _FakeCodec.twoFrame()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('estimateBytes is width*height*4*frames', () {
    expect(AnimationFrameCache.estimateBytes(width: 1, height: 1, frameCount: 2), 8);
    expect(AnimationFrameCache.estimateBytes(width: 64, height: 64, frameCount: 16),
        64 * 64 * 4 * 16);
    expect(
        AnimationFrameCache.underPerPostCap(width: 256, height: 256, frameCount: 1024),
        isFalse);
    expect(AnimationFrameCache.underPerPostCap(width: 64, height: 64, frameCount: 16),
        isTrue);
  });

  testWidgets('full decode: frames, clamped timeline, byteSize, cached', (tester) async {
    final cache = AnimationFrameCache();
    var fetches = 0;
    final codec = _FakeCodec.twoFrame();
    final decoder = _decoder(cache, fetch: (_) async {
      fetches++;
      return Uint8List(0);
    }, codec: (_) async => codec);

    final r = await decoder.request(_url, firstFrameOnly: false);
    expect(r.status, DecodeStatus.success);
    final anim = r.animation!;
    expect(anim.frames.length, 2);
    expect(anim.isPartial, isFalse);
    expect(anim.timeline.delaysMs, [100, 200]); // 0 ms clamps to 100
    expect(anim.timeline.totalDurationMs, 300);
    expect(anim.byteSize, 8); // from actually-decoded 1×1×2, not any hint
    expect(fetches, 1);
    expect(codec.disposed, isTrue);
    expect(cache.get(_url), same(anim));
    // A second request is a pure cache hit — no new fetch.
    final r2 = await decoder.request(_url, firstFrameOnly: false);
    expect(r2.animation, same(anim));
    expect(fetches, 1);
  });

  testWidgets('concurrent requests for one URL share a single fetch/decode', (tester) async {
    final cache = AnimationFrameCache();
    var fetches = 0;
    final decoder = _decoder(cache, fetch: (_) async {
      fetches++;
      return Uint8List(0);
    });
    final results = await Future.wait([
      decoder.request(_url, firstFrameOnly: false),
      decoder.request(_url, firstFrameOnly: false),
    ]);
    expect(fetches, 1);
    expect(results[0].animation, same(results[1].animation));
  });

  testWidgets('retain/release: images disposed only when the last reference drops', (tester) async {
    final cache = AnimationFrameCache();
    final decoder = _decoder(cache);
    final anim = (await decoder.request(_url, firstFrameOnly: false)).animation!;
    anim.retain(); // a widget adopts it (cache holds the other reference)
    cache.remove(_url); // eviction releases the cache's reference
    expect(anim.frames.first.debugDisposed, isFalse); // widget still painting
    anim.release(); // widget disposes
    expect(anim.frames.first.debugDisposed, isTrue);
  });

  testWidgets('partial (frame-0) decode, then full decode replaces it', (tester) async {
    final cache = AnimationFrameCache();
    final decoder = _decoder(cache);
    final partial = (await decoder.request(_url, firstFrameOnly: true)).animation!;
    expect(partial.isPartial, isTrue);
    expect(partial.frames.length, 1);
    expect(partial.byteSize, 4);
    expect(cache.get(_url), same(partial));
    // A partial hit does NOT satisfy a full request.
    final full = (await decoder.request(_url, firstFrameOnly: false)).animation!;
    expect(full.isPartial, isFalse);
    expect(full.frames.length, 2);
    expect(cache.get(_url), same(full));
    // The overwritten partial (only the cache held it) is disposed.
    expect(partial.frames.first.debugDisposed, isTrue);
    // But a full entry does satisfy a later frame-0 request.
    final r = await decoder.request(_url, firstFrameOnly: true);
    expect(r.animation, same(full));
  });

  testWidgets('over-cap discovered from the codec frame count (server hint mismatch)',
      (tester) async {
    final cache = AnimationFrameCache();
    final decoder = _decoder(cache, capBytes: 7); // real size is 1×1×4×2 = 8
    // The pre-decode hint check would pass if the server claimed 1 frame…
    expect(
        AnimationFrameCache.underPerPostCap(
            width: 1, height: 1, frameCount: 1, capBytes: 7),
        isTrue);
    // …but the decoder re-verifies against codec.frameCount and declines.
    final r = await decoder.request(_url, firstFrameOnly: false);
    expect(r.status, DecodeStatus.overCap);
    expect(r.animation, isNull);
    expect(cache.get(_url), isNull);
  });

  testWidgets('fetch failure and undecodable bytes both yield error', (tester) async {
    final cache = AnimationFrameCache();
    final failingFetch =
        _decoder(cache, fetch: (_) async => throw Exception('offline'));
    expect((await failingFetch.request(_url, firstFrameOnly: false)).status,
        DecodeStatus.error);
    final failingCodec =
        _decoder(cache, codec: (_) async => throw Exception('bad bytes'));
    expect((await failingCodec.request(_url, firstFrameOnly: false)).status,
        DecodeStatus.error);
    expect(cache.get(_url), isNull);
  });

  testWidgets('real codec fidelity: the GIF fixture decodes as authored',
      (tester) async {
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(kTwoFrameGif);
      expect(codec.frameCount, 2);
      final f0 = await codec.getNextFrame();
      expect(f0.image.width, 1);
      expect(f0.image.height, 1);
      expect(f0.duration.inMilliseconds, lessThanOrEqualTo(10),
          reason: 'authored 0 cs delay — the timeline clamp turns this into 100 ms');
      final f1 = await codec.getNextFrame();
      expect(f1.duration.inMilliseconds, 200);
      codec.dispose();
      // Garbage bytes are rejected by the codec (the decoder maps this to error).
      await expectLater(
          ui.instantiateImageCodec(Uint8List.fromList(List.filled(32, 7))),
          throwsA(anything));
    });
  });
}
