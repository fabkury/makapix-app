import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/editor/replay/timelapse_plan.dart';

void main() {
  group('samplePositions', () {
    test('count, monotonic, last == actionCount', () {
      final s = samplePositions(150000, 450);
      expect(s.length, 450);
      expect(s.last, 150000);
      for (var i = 1; i < s.length; i++) {
        expect(s[i], greaterThanOrEqualTo(s[i - 1]));
      }
    });

    test('short journals repeat positions (legal duplicates)', () {
      final s = samplePositions(10, 30);
      expect(s.length, 30);
      expect(s.last, 10);
      expect(s.toSet().length, lessThanOrEqualTo(11));
    });

    test('zero samples → empty', () {
      expect(samplePositions(100, 0), isEmpty);
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
          actionCount: 9000, seconds: 15, frameDurationsUs: durations);
      final progress = plan.where((e) => !e.isFinale).toList();
      final finale = plan.where((e) => e.isFinale).toList();
      expect(progress.length, 450);
      expect(progress.every((e) => e.durationUs == kProgressFrameUs), isTrue);
      expect(finale.length, 10);
      expect(totalDurationUs(plan), 450 * kProgressFrameUs + 10 * 100000);
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
