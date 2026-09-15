// Which pillar a cold start mounts: the last one used, if that was recent (ADR 0035).
//
// The app is Club-first by identity, but someone who left in the editor a few hours ago is
// almost certainly coming back to draw — and the editor needs no account and no network, so
// landing there costs nothing and, offline, spares them the Club's connecting state entirely.
// A time decay keeps the memory honest: after [LaunchPillarMemory.window] without the editor,
// the Club is the landing again, so the social half of the app never quietly disappears.
//
// Only the pillar and a timestamp are stored (shared preferences); the choice is read once in
// `main()` before the first frame — never mid-run — and published through [launchPillarProvider].
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../club/state/edit_bridge.dart';

export '../club/state/edit_bridge.dart' show AppPillar, launchPillarProvider;

class LaunchPillarMemory {
  LaunchPillarMemory._();

  /// How long a last editor session keeps the editor as the landing pillar.
  static const Duration window = Duration(hours: 24);

  static const String pillarKey = 'shell.last_pillar_v1';
  static const String stampKey = 'shell.last_pillar_at_v1'; // epoch ms

  /// The pillar to mount first. Never throws and never waits long: a preferences failure or a
  /// slow store means the default (Club). [now] is injectable for tests.
  static Future<AppPillar> read({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      return decide(
        pillar: prefs.getString(pillarKey),
        stampMs: prefs.getInt(stampKey),
        now: now ?? DateTime.now(),
      );
    } catch (e) {
      debugPrint('[launch-pillar] read skipped: $e');
      return AppPillar.club;
    }
  }

  /// The pure rule: editor iff the stored pillar is the editor and its stamp is within [window]
  /// (a stamp in the future — clock rollback — counts as recent; it decays like any other).
  @visibleForTesting
  static AppPillar decide({required String? pillar, required int? stampMs, required DateTime now}) {
    if (pillar != AppPillar.editor.name || stampMs == null) return AppPillar.club;
    final at = DateTime.fromMillisecondsSinceEpoch(stampMs);
    return now.difference(at) <= window ? AppPillar.editor : AppPillar.club;
  }

  /// Record [pillar] as the current one, now. Fire-and-forget: a failed write only costs the
  /// memory for the next launch.
  static Future<void> stamp(AppPillar pillar, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(pillarKey, pillar.name);
      await prefs.setInt(stampKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[launch-pillar] stamp skipped: $e');
    }
  }
}
