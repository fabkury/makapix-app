import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/timelapse_plan.dart';
import 'package:makapix_club/editor/replay/visible_index.dart';

/// A timeline at positions `1..n` from parallel working-time / event lists.
ReplayTimeline tl(List<int> workMs, List<int> isEvent) => ReplayTimeline(
      Int32List.fromList([for (var i = 1; i <= workMs.length; i++) i]),
      Uint8List.fromList(isEvent),
      Uint32List.fromList(workMs),
    );

/// Per-tick dwell from a cumulative axis.
List<int> dwells(Uint32List cum) => [for (var k = 0; k < cum.length; k++) cum[k] - (k == 0 ? 0 : cum[k - 1])];

void main() {
  // The 30 s preset: 900 frames × 33,333 µs.
  const t30 = 900 * kProgressFrameUs; // 29,999,700
  const floor30 = t30 ~/ kEventFloorDivisor; // 299,997 (> 6 frames = 199,998)
  const ceil30 = t30 ~/ kEventCeilDivisor; // 2,499,975

  group('progressDurationUs', () {
    test('is exactly the frame count times the frame duration', () {
      expect(progressDurationUs(15), 450 * kProgressFrameUs);
      expect(progressDurationUs(30), t30);
      expect(progressDurationUs(60), 1800 * kProgressFrameUs);
    });
  });

  group('paceTimeline — proportion, floor, ceiling', () {
    test('all-stream: dwell is exactly proportional to working time', () {
      final cum = paceTimeline(tl([1000, 3000], [0, 0]), 30);
      expect(cum, [t30 ~/ 4, t30]);
    });

    test('no timing at all → uniform, the legacy pacing', () {
      final cum = paceTimeline(tl([0, 0, 0, 0], [0, 1, 0, 1]), 30);
      expect(cum, [t30 ~/ 4, t30 ~/ 2, 3 * t30 ~/ 4, t30]);
      expect(paceTimeline(ReplayTimeline.uniform(3), 15).last, progressDurationUs(15));
    });

    test('a fast tap after a minute of stroking still gets the event floor', () {
      // 60 s of pencil work, then a bucket tap 10 ms later.
      final cum = paceTimeline(tl([60000, 10], [0, 1]), 30);
      expect(dwells(cum)[1], floor30);
      expect(cum.last, t30);
    });

    test('a long tuning session is capped at the event ceiling', () {
      // 10 s of strokes, then 40 s of (clamped) Levels tuning landing on the Apply.
      final cum = paceTimeline(tl([10000, 40000], [0, 1]), 30);
      expect(dwells(cum)[1], ceil30);
      expect(dwells(cum)[0], t30 - ceil30);
    });

    test('an event between floor and ceiling dwells in proportion', () {
      // Streams 20 s, event 1 s: proportional share = 1/21 of T ≈ 1.43 s, inside [T/100, T/12].
      final cum = paceTimeline(tl([10000, 1000, 10000], [0, 1, 0]), 30);
      final d = dwells(cum);
      expect(d[1], closeTo(t30 / 21, 2));
      expect(d[0], closeTo(10 * t30 / 21, 2));
      expect(cum.last, t30);
    });

    test('the floor scales with the preset and never drops under 6 frames', () {
      final at15 = dwells(paceTimeline(tl([60000, 10], [0, 1]), 15))[1];
      final at60 = dwells(paceTimeline(tl([60000, 10], [0, 1]), 60))[1];
      expect(at15, kEventFloorFrames * kProgressFrameUs, reason: '15 s: T/100 < 6 frames');
      expect(at60, progressDurationUs(60) ~/ kEventFloorDivisor);
    });

    test('floors shrink when events alone would overrun 60 % of the preset', () {
      // 200 instant fills (1 ms each) + one second of stroking at 15 s: 200 × 0.2 s ≫ 9 s, so
      // the floor shrinks to 0.6·T/200 = 45 ms and still binds (1 ms of work is far under it).
      final timeline = tl([1000, for (var i = 0; i < 200; i++) 1], [0, for (var i = 0; i < 200; i++) 1]);
      final cum = paceTimeline(timeline, 15);
      final t15 = progressDurationUs(15);
      final d = dwells(cum);
      final eventTotal = d.skip(1).fold(0, (a, b) => a + b);
      expect(eventTotal, closeTo(t15 * 3 / 5, 200 + 1), reason: 'floors claim exactly their share');
      expect(d[0], closeTo(t15 * 2 / 5, 200 + 1), reason: 'the stroke keeps the rest');
      expect(cum.last, t15);
    });

    test('events only, all saturated under the budget → scaled up to fill the preset', () {
      // Four fills, nothing else: 4 × ceiling < T, so they share T equally instead.
      final cum = paceTimeline(tl([1000, 1000, 1000, 1000], [1, 1, 1, 1]), 30);
      expect(cum, [t30 ~/ 4, t30 ~/ 2, 3 * t30 ~/ 4, t30]);
    });

    test('a zero-work event still gets its floor; a zero-work stream tick gets nothing', () {
      final cum = paceTimeline(tl([500, 0, 0, 500], [0, 1, 0, 0]), 30);
      final d = dwells(cum);
      expect(d[1], floor30);
      expect(d[2], 0);
      expect(d[0], closeTo(d[3], 1), reason: 'equal shares up to the rounding half');
    });

    test('monotone, exact total, event dwells inside the band (property check)', () {
      var seed = 12345;
      int next(int mod) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        return seed % mod;
      }
      final works = <int>[], events = <int>[];
      for (var i = 0; i < 5000; i++) {
        final isEvent = next(10) == 0; // ~500 events: 500 × 0.3 s = 150 s > 0.6·T → floors shrink
        events.add(isEvent ? 1 : 0);
        works.add(isEvent ? next(3000) : next(40));
      }
      final cum = paceTimeline(tl(works, events), 30);
      expect(cum.last, t30);
      var prev = 0;
      final d = dwells(cum);
      for (var k = 0; k < cum.length; k++) {
        expect(cum[k], greaterThanOrEqualTo(prev));
        prev = cum[k];
        if (events[k] == 1) {
          expect(d[k], lessThanOrEqualTo(ceil30 + 1));
          expect(d[k], greaterThanOrEqualTo(1));
        }
      }
    });

    test('empty timeline → empty axis', () {
      expect(paceTimeline(ReplayTimeline.empty, 30), isEmpty);
    });
  });

  group('tickIndexAt', () {
    final cum = Uint32List.fromList([100, 100, 250, 400]);
    test('the starting state before the first instant; the last tick from the total on', () {
      expect(tickIndexAt(cum, 0), -1);
      expect(tickIndexAt(cum, -5), -1);
      expect(tickIndexAt(cum, 400), 3);
      expect(tickIndexAt(cum, 10000), 3);
    });
    test('the first tick whose cumulative time reaches the instant; empty intervals skipped', () {
      expect(tickIndexAt(cum, 1), 0);
      expect(tickIndexAt(cum, 100), 0);
      expect(tickIndexAt(cum, 101), 2, reason: 'tick 1 has no dwell');
      expect(tickIndexAt(cum, 250), 2);
      expect(tickIndexAt(cum, 251), 3);
    });
    test('empty axis', () {
      expect(tickIndexAt(Uint32List(0), 5), -1);
    });
  });

  group('samplePositions (over the paced timeline)', () {
    List<int> allPositions(int n) => List<int>.generate(n, (i) => i + 1);
    Uint32List uniform(int n, int seconds) => paceTimeline(ReplayTimeline.uniform(n), seconds);

    test('count, monotonic, last == positions.last', () {
      final s = samplePositions(allPositions(150000), uniform(150000, 15), 450);
      expect(s.length, 450);
      expect(s.last, 150000);
      for (var i = 1; i < s.length; i++) {
        expect(s[i], greaterThanOrEqualTo(s[i - 1]));
      }
      // Uniform pacing spreads the samples evenly: frame 224 of 450 sits at the halfway point.
      expect(s[224], closeTo(75000, 400));
    });

    test('short pools repeat positions (legal duplicates)', () {
      final s = samplePositions(allPositions(10), uniform(10, 15), 30);
      expect(s.length, 30);
      expect(s.last, 10);
      expect(s.toSet().length, lessThanOrEqualTo(10));
    });

    test('a sparse pool samples only its members — no dead in-between frames', () {
      // The whole point of visible-change sampling: positions inside fiddle stretches
      // (6..3999 here) never become video frames.
      final pool = [5, 100, 4000];
      final s = samplePositions(pool, paceTimeline(ReplayTimeline.uniform(3), 15), 6);
      expect(s.toSet().difference(pool.toSet()), isEmpty);
      expect(s.last, 4000);
      expect(s.length, 6);
    });

    test('dwell decides the share of frames', () {
      // Tick 1 owns 3/4 of the axis, tick 2 the rest.
      final cum = paceTimeline(tl([3000, 1000], [0, 0]), 30);
      final s = samplePositions([1, 2], cum, 900);
      expect(s.where((p) => p == 1).length, 675);
      expect(s.where((p) => p == 2).length, 225);
    });

    test('a tick with no dwell never gets a frame; a trailing one still ends the plan', () {
      final cum = paceTimeline(tl([500, 0, 500, 0], [0, 0, 0, 0]), 15);
      final s = samplePositions([1, 2, 3, 4], cum, 450);
      expect(s.contains(2), isFalse);
      expect(s.last, 4, reason: 'the final position always closes the progress portion');
      expect(s[448], 3, reason: 'the frame before it shows the last state that had dwell');
    });

    test('zero samples or an empty pool → empty', () {
      expect(samplePositions(allPositions(100), uniform(100, 15), 0), isEmpty);
      expect(samplePositions(const [], Uint32List(0), 30), isEmpty);
    });
  });

  group('finaleLoopCount — the grilled branch table', () {
    // C = 0.4 s → aim ≥3 s wants 8 loops, cap 5 wins → 5 loops (2.0 s).
    test('C=0.4s → 5 loops (count cap wins)', () {
      expect(finaleLoopCount(400_000), 5);
    });
    // C = 0.5 s → ceil(3/0.5)=6 → clamp 5.
    test('C=0.5s → 5 loops', () {
      expect(finaleLoopCount(500_000), 5);
    });
    // C = 1 s → ceil(3/1)=3 loops (3 s, under the 8 s cap).
    test('C=1s → 3 loops', () {
      expect(finaleLoopCount(1_000_000), 3);
    });
    // C = 5 s → ≥2-plays floor wants 2 (10 s) but the ~8 s cap decrements → 1 full play.
    test('C=5s → 1 play (time cap beats the 2-play floor)', () {
      expect(finaleLoopCount(5_000_000), 1);
    });
    // C = 3.5 s → 2 plays = 7 s ≤ 8 s → the floor holds.
    test('C=3.5s → 2 plays', () {
      expect(finaleLoopCount(3_500_000), 2);
    });
    // C = 9 s → a single full play is never truncated.
    test('C=9s → 1 full play', () {
      expect(finaleLoopCount(9_000_000), 1);
    });
    // C = 61 s → still 1 full play here; the >60 s excerpt choice is the caller's dialog.
    test('C=61s → 1 full play', () {
      expect(finaleLoopCount(61_000_000), 1);
    });
  });

  group('planFinale', () {
    test('static drawing holds 4.5 s', () {
      final f = planFinale([100000]);
      expect(f.single.frameIndex, 0);
      expect(f.single.durationUs, kStaticHoldUs);
    });

    test('animated: whole cycles from frame 1 at authored durations', () {
      final durations = [100000, 200000, 300000]; // C = 0.6 s → 5 loops
      final f = planFinale(durations);
      expect(finaleLoopCount(cycleUs(durations)), 5);
      expect(f.length, 15);
      for (var l = 0; l < 5; l++) {
        for (var i = 0; i < 3; i++) {
          expect(f[l * 3 + i].frameIndex, i);
          expect(f[l * 3 + i].durationUs, durations[i]);
        }
      }
    });

    test('excerpt: whole frames until ~60 s, one play', () {
      final durations = List.filled(120, 1_000_000); // 2-minute cycle
      expect(excerptFrameCount(durations), 60);
      final f = planFinale(durations, fullCycle: false);
      expect(f.length, 60);
      expect(f.first.frameIndex, 0);
      expect(f.last.frameIndex, 59);
    });

    test('excerpt is always ≥1 frame', () {
      expect(excerptFrameCount([70_000_000]), 1);
    });
  });

  group('planTimelapse + PTS accumulation', () {
    test('progress at 30fps + appended finale; total duration adds up', () {
      final durations = [100000, 100000]; // C=0.2s → 5 loops of 2 frames
      final plan = planTimelapse(
          timeline: ReplayTimeline.uniform(9000), seconds: 15, frameDurationsUs: durations);
      final progress = plan.where((e) => !e.isFinale).toList();
      final finale = plan.where((e) => e.isFinale).toList();
      expect(progress.length, 450);
      expect(progress.every((e) => e.durationUs == kProgressFrameUs), isTrue);
      expect(progress.last.position, 9000);
      expect(finale.length, 10);
      expect(totalDurationUs(plan), 450 * kProgressFrameUs + 10 * 100000);
    });

    test('a paced journal: the apply holds, the stroke flows', () {
      // A 30 s stroke of 900 moves, then an Apply 20 ms later, at the 15 s preset: the apply
      // gets the floor (6 frames), the stroke the other 444.
      final works = [for (var i = 0; i < 900; i++) 33, 20];
      final events = [for (var i = 0; i < 900; i++) 0, 1];
      final plan = planTimelapse(timeline: tl(works, events), seconds: 15, frameDurationsUs: [100000]);
      final progress = plan.where((e) => !e.isFinale).map((e) => e.position!).toList();
      expect(progress.where((p) => p == 901).length, kEventFloorFrames);
      expect(progress.length, 450);
    });
  });

  group('letterboxScale', () {
    test('the integer-clean 1024-class factors', () {
      expect(letterboxScale(64, 64, 1080, 1080), 16);
      expect(letterboxScale(128, 128, 1080, 1080), 8);
      expect(letterboxScale(256, 256, 1080, 1080), 4);
      expect(letterboxScale(256, 256, 1080, 1920), 4);
      expect(letterboxScale(256, 128, 1080, 1920), 4); // width binds
      expect(letterboxScale(64, 256, 1080, 1920), 7); // height binds: 1920/256
    });

    test('never below 1', () {
      expect(letterboxScale(2000, 2000, 1080, 1080), 1);
    });
  });

  group('wordmarkPlacement', () {
    test('portrait: ample bottom band → centered placement', () {
      // 256² art ×4 = 1024² content in 1080×1920: bottom band ≈ 448 px.
      final p = wordmarkPlacement(
          contentW: 1024, contentH: 1024, outW: 1080, outH: 1920, wmW: 392, wmH: 56);
      expect(p, isNotNull);
      expect(p!.x, (1080 - 392) ~/ 2);
      // Content oy = floor((1920-1024)/2)=448 → even; band = 1920-448-1024 = 448.
      expect(p.y, 448 + 1024 + (448 - 56) ~/ 2);
      expect(p.y + 56, lessThanOrEqualTo(1920));
      expect(p.y, greaterThanOrEqualTo(448 + 1024), reason: 'never over the pixels');
    });

    test('square art in the square preset: band too tight → skip', () {
      // 1024² in 1080²: bands are 28 px — under wmH+16.
      final p = wordmarkPlacement(
          contentW: 1024, contentH: 1024, outW: 1080, outH: 1080, wmW: 392, wmH: 56);
      expect(p, isNull);
    });

    test('wide mark never overflows', () {
      final p = wordmarkPlacement(
          contentW: 512, contentH: 512, outW: 1080, outH: 1920, wmW: 2000, wmH: 56);
      expect(p, isNull);
    });
  });
}
