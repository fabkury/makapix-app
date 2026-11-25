// Pulse: the timeline of what members do (likes, new artworks, comments, …), grouped by the
// server into one card per member, kind, and burst of activity (messages/0008-pulse/).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/pulse_api.dart';
import '../cache/artwork_cache.dart';
import '../models/club_error.dart';
import '../models/page.dart';
import '../models/pulse_card.dart';
import 'auth_controller.dart' show clubApiClientProvider, currentUserSubProvider;
import 'paged.dart';

final pulseApiProvider = Provider<PulseApi>((ref) => PulseApi(ref.watch(clubApiClientProvider)));

/// The filter chips above the timeline. Each narrows it to some card kinds; [all] asks for
/// everything, including kinds a later server adds.
enum PulseFilter {
  all({}),
  artworks({PulseKind.posts, PulseKind.remixes}),
  reactions({PulseKind.likes}),
  comments({PulseKind.comments}),
  recommended({PulseKind.promoted}),
  players({PulseKind.player}),
  badges({PulseKind.badge}),
  reputation({PulseKind.reputation});

  final Set<PulseKind> kinds;
  const PulseFilter(this.kinds);
}

/// The chosen filter. Session-only, like the feeds' filters.
final pulseFilterProvider = StateProvider<PulseFilter>((_) => PulseFilter.all);

/// Whether the server has Pulse: null until the first answer, false after a 404 (a server from
/// before the rollout), true after any page arrived.
final pulseAvailableProvider = StateProvider<bool?>((_) => null);

/// When the timeline's first page last arrived; null before that. Drives the quiet refresh on
/// return ([refreshPulseIfStale]).
final pulseFetchedAtProvider = StateProvider<DateTime?>((_) => null);

/// Whether the Club home opens on Pulse: true once this install has seen the server answer
/// `GET /pulse`. Read from preferences in `main()` before the first frame and never changed
/// mid-run — the launch path does not wait on the network (ADR 0035), so it goes by what the
/// last session learned. Until then the home opens on Recent, as it did before Pulse.
final pulseLandingProvider = Provider<bool>((_) => false);

/// The remembered "this server has Pulse" bit behind [pulseLandingProvider].
class PulseLandingMemory {
  PulseLandingMemory._();

  static const String key = 'club.pulse_live_v1';

  /// Never throws and never waits long: a preferences failure means "not seen yet".
  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint('[pulse] landing read skipped: $e');
      return false;
    }
  }

  /// Fire-and-forget: a failed write only costs the landing page of the next launch.
  static Future<void> write(bool live) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == live) return;
      await prefs.setBool(key, live);
    } catch (e) {
      debugPrint('[pulse] landing write skipped: $e');
    }
  }
}

/// The timeline: an auto-loading paged list of cards. Keep-alive like the home feeds, and
/// viewer-scoped like them (blocks and monitored hashtags are applied server-side), so an
/// account switch refetches it. Watching [pulseFilterProvider] makes a new filter refetch too.
final pulseProvider =
    StateNotifierProvider<PagedNotifier<PulseCard>, PagedState<PulseCard>>((ref) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(pulseApiProvider);
  final filter = ref.watch(pulseFilterProvider);
  var alive = true;
  ref.onDispose(() => alive = false);

  // The providers below are written after an await, so never while a widget builds.
  void learned(bool available, {required bool firstPage}) {
    if (!alive) return;
    ref.read(pulseAvailableProvider.notifier).state = available;
    if (firstPage) ref.read(pulseFetchedAtProvider.notifier).state = DateTime.now();
    PulseLandingMemory.write(available);
  }

  final n = PagedNotifier<PulseCard>((cursor) async {
    try {
      final page = await api.cards(cursor: cursor, kinds: filter.kinds);
      learned(true, firstPage: cursor == null);
      return page;
    } on ClubError catch (e) {
      // A server from before Pulse: not an error to show, just nothing to list yet.
      if (e.status != 404) rethrow;
      learned(false, firstPage: cursor == null);
      return const Page<PulseCard>(items: []);
    }
  }, onPage: (cards) => precacheArtworks([for (final c in cards) ...c.posts]));
  n.loadInitial();
  return n;
});

/// How old the timeline may be before coming back to it refetches it. The server's own data
/// is up to a minute stale, so asking more often shows nothing new.
const Duration kPulseStaleAfter = Duration(minutes: 1);

/// Refetch the timeline if its first page is older than [kPulseStaleAfter]. Called when the
/// user comes back to Pulse: from another home page, from a pushed route, from the background.
/// The cards stay on screen while it loads. [now] is injectable for tests.
void refreshPulseIfStale(WidgetRef ref, {DateTime? now}) {
  final at = ref.read(pulseFetchedAtProvider);
  if (at == null || ref.read(pulseProvider).loading) return;
  if ((now ?? DateTime.now()).difference(at) < kPulseStaleAfter) return;
  ref.read(pulseProvider.notifier).refresh();
}
