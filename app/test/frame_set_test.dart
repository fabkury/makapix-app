// Frame-set helpers (frames/frame_set.dart): wire and human forms, the Range entry parser,
// Every Nth, the shift clamp, the post-batch selection formulas, and the pre-checks. Pure Dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:makapix_club/editor/frames/frame_model.dart';
import 'package:makapix_club/editor/frames/frame_set.dart';

void main() {
  group('formatting', () {
    test('canonical wire form coalesces, sorts, and dedups', () {
      expect(formatFrameSet([40, 12, 13, 14, 13, 15]), '12-15 40');
      expect(formatFrameSet([3]), '3');
      expect(formatFrameSet([0, 1, 2, 3]), '0-3');
      expect(formatFrameSet([5, 3, 1]), '1 3 5');
      expect(formatFrameSet(const []), '');
    });

    test('human form is 1-based with en-dash ranges', () {
      expect(formatFrameSetHuman([12, 13, 14, 40]), '13–15, 41');
      expect(formatFrameSetHuman([0]), '1');
    });

    test('frameSetDsl renders the verb line, args and commas in names included', () {
      expect(frameSetDsl('RemoveFrames', [12, 13, 40]), 'RemoveFrames(12-13 40)');
      expect(frameSetDsl('ShiftFrames', [1, 3], ['-2']), 'ShiftFrames(1 3, -2)');
      expect(frameSetDsl('SetLayersVisibleNamed', [0, 1, 2], ['0', 'Sky, dawn']), 'SetLayersVisibleNamed(0-2, 0, Sky, dawn)');
    });

    test('sanitizeLayerName strips statement breaks and keeps commas', () {
      expect(sanitizeLayerName(' Sky;\ndawn, v2 '), 'Sky  dawn, v2');
    });
  });

  group('parseFrameRangeEntry', () {
    test('1-based numbers and ranges, mixed separators, reversed swapped, overlap merged', () {
      final r = parseFrameRangeEntry('1-3, 20 5-4 2', frameCount: 40);
      expect(r.error, isNull);
      expect(r.indices, [0, 1, 2, 3, 4, 19]);
    });

    test('en dashes are accepted', () {
      expect(parseFrameRangeEntry('2–3', frameCount: 10).indices, [1, 2]);
    });

    test('errors: empty, garbage, zero, beyond the roll', () {
      expect(parseFrameRangeEntry('   ', frameCount: 10).error, isNotNull);
      expect(parseFrameRangeEntry('1-x', frameCount: 10).error, isNotNull);
      expect(parseFrameRangeEntry('0-3', frameCount: 10).error, 'Frames start at 1');
      expect(parseFrameRangeEntry('4-50', frameCount: 40).error, 'Frame 50 is beyond the last frame (40)');
      expect(parseFrameRangeEntry('4-50', frameCount: 40).indices, isNull);
    });
  });

  group('everyNth', () {
    test('within a base list with offsets', () {
      const base = [0, 1, 2, 3, 4, 5, 6];
      expect(everyNth(base, n: 2, offset: 0), [0, 2, 4, 6]);
      expect(everyNth(base, n: 2, offset: 1), [1, 3, 5]);
      expect(everyNth(base, n: 3, offset: 2), [2, 5]);
      expect(everyNth(base, n: 1, offset: 0), base);
      expect(everyNth(base, n: 0, offset: 9), base, reason: 'n clamps to 1, offset to 0');
      expect(everyNth(const [], n: 2, offset: 0), isEmpty);
    });
  });

  group('shift and post-batch selection', () {
    test('clampShift keeps every member inside the roll', () {
      expect(clampShift([1, 3], 2, 8), 2);
      expect(clampShift([1, 3], 10, 8), 4);
      expect(clampShift([1, 3], -5, 8), -1);
      expect(clampShift([0, 1], -3, 4), 0);
      expect(clampShift([3], 1, 4), 0);
      expect(clampShift(const [], 1, 4), 0);
    });

    test('duplicate and repeat result indices', () {
      expect(duplicateResultIndices([3, 5]), [4, 7]);
      expect(duplicateResultIndices([0, 1, 2]), [1, 3, 5]);
      expect(repeatResultIndices([2, 5, 7]), [8, 9, 10]);
      expect(repeatResultIndices(const []), isEmpty);
    });
  });

  group('pre-checks', () {
    final frames = [
      const FrameInfo(id: 1, durationUs: 20000, layers: [LayerInfo(name: 'Sky', presentTiles: 3), LayerInfo(name: 'Ink', presentTiles: 1)]),
      const FrameInfo(id: 2, durationUs: 100000, layers: [LayerInfo(name: 'Ink', presentTiles: 2)]),
      const FrameInfo(id: 3, durationUs: 900000, layers: [LayerInfo(name: 'Sky'), LayerInfo(name: 'Sky', presentTiles: 4)]),
    ];

    test('pinned counts for a set and for a scale', () {
      expect(pinnedCountForSet([0, 1, 2], 16600), 3, reason: '16.6 ms pins at the 16.667 ms floor');
      expect(pinnedCountForSet([0, 1, 2], 100000), 0);
      expect(pinnedCountForScale(frames, [0, 1, 2], 500), 1, reason: '20 ms × 0.5 pins; the others do not');
      expect(pinnedCountForScale(frames, [0, 1, 2], 2000), 1, reason: '900 ms × 2 pins at the ceiling');
      expect(pinnedCountForScale(frames, [1], 1000), 0);
    });

    test('retained payload sums present tiles', () {
      expect(retainedPayloadBytes(frames, [0, 2]), (3 + 1 + 0 + 4) * kTileBytes);
      expect(retainedPayloadBytes(frames, [1, 9]), 2 * kTileBytes, reason: 'unknown indices are skipped');
    });

    test('layer name hits count one per frame, most common first', () {
      final hits = layerNameHits(frames, [0, 1, 2]);
      expect(hits.map((h) => h.name).toList(), ['Ink', 'Sky']);
      expect(hits.map((h) => h.hits).toList(), [2, 2], reason: 'Sky twice in frame 3 is one hit; ties sort by name');
      expect(layerNameHits(frames, [1]), [(name: 'Ink', hits: 1)]);
    });
  });

  group('parseFrameDetail', () {
    test('reads ids, durations, layers; tolerates junk', () {
      final frames = parseFrameDetail([
        {
          'i': 0,
          'id': 7,
          'duration_us': 40000,
          'active_layer': 1,
          'layers': [
            {'name': 'A', 'visible': true, 'locked': false, 'opacity': 255, 'present_tiles': 2},
            {'name': 'B', 'visible': false, 'locked': true, 'opacity': 255, 'blend': 'Multiply', 'present_tiles': 0},
          ],
        },
        'junk',
        {'id': 9},
      ]);
      expect(frames.length, 3);
      expect(frames[0].id, 7);
      expect(frames[0].durationMs, 40.0);
      expect(frames[0].activeLayer, 1);
      expect(frames[0].layers[1].visible, isFalse);
      expect(frames[0].layers[1].locked, isTrue);
      expect(frames[0].payloadBytes, 2 * kTileBytes);
      expect(frames[1].id, 1, reason: 'a junk entry falls back to its index');
      expect(frames[2].durationUs, kDefaultDurationUs);
      expect(parseFrameDetail(null), isEmpty);
      expect(clampDurationUs(5), kMinDurationUs);
      expect(clampDurationUs(5000000), kMaxDurationUs);
    });
  });
}
