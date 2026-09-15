// The launch-pillar memory (ADR 0035): a cold start mounts the editor iff the last pillar was
// the editor within the 24 h window; everything else — Club last, an old editor stamp, no
// memory, a missing or malformed value — lands on the Club. Pure rule + the preferences
// round trip, on the in-memory preferences store (no platform channel).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:makapix_club/shell/launch_pillar.dart';

void main() {
  final now = DateTime(2026, 9, 15, 12);
  int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

  group('decide (pure rule)', () {
    test('editor within the window → editor', () {
      expect(
        LaunchPillarMemory.decide(
            pillar: 'editor', stampMs: ago(const Duration(hours: 3)), now: now),
        AppPillar.editor,
      );
      expect(
        LaunchPillarMemory.decide(pillar: 'editor', stampMs: ago(LaunchPillarMemory.window), now: now),
        AppPillar.editor,
        reason: 'the boundary is inclusive',
      );
    });

    test('editor past the window → club (the decay)', () {
      expect(
        LaunchPillarMemory.decide(
            pillar: 'editor',
            stampMs: ago(LaunchPillarMemory.window + const Duration(minutes: 1)),
            now: now),
        AppPillar.club,
      );
    });

    test('club last, no memory, or garbage → club', () {
      expect(LaunchPillarMemory.decide(pillar: 'club', stampMs: ago(Duration.zero), now: now),
          AppPillar.club);
      expect(LaunchPillarMemory.decide(pillar: null, stampMs: null, now: now), AppPillar.club);
      expect(LaunchPillarMemory.decide(pillar: 'editor', stampMs: null, now: now), AppPillar.club);
      expect(LaunchPillarMemory.decide(pillar: 'sofa', stampMs: ago(Duration.zero), now: now),
          AppPillar.club);
    });

    test('a stamp from the future (clock rollback) counts as recent', () {
      expect(
        LaunchPillarMemory.decide(
            pillar: 'editor',
            stampMs: now.add(const Duration(days: 2)).millisecondsSinceEpoch,
            now: now),
        AppPillar.editor,
      );
    });
  });

  group('preferences round trip', () {
    test('stamp then read → the stamped pillar', () async {
      SharedPreferences.setMockInitialValues({});
      await LaunchPillarMemory.stamp(AppPillar.editor, now: now);
      expect(await LaunchPillarMemory.read(now: now), AppPillar.editor);
      expect(await LaunchPillarMemory.read(now: now.add(const Duration(days: 2))), AppPillar.club,
          reason: 'the same stamp decays');
      await LaunchPillarMemory.stamp(AppPillar.club, now: now);
      expect(await LaunchPillarMemory.read(now: now), AppPillar.club);
    });

    test('a fresh install reads as club', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LaunchPillarMemory.read(now: now), AppPillar.club);
    });
  });
}
