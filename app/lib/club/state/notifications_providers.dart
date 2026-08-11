import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_notification.dart';
import 'api_providers.dart';
import 'auth_controller.dart' show authControllerProvider, currentUserSubProvider;
import 'notifications_sse.dart';
import 'paged.dart';

/// Unread badge count. The SSE stream ([notificationsSseProvider]) is the live
/// source while foregrounded — its `connected` greeting calls [reconcile] and
/// each unread `notification` event calls [bump]. The 60 s poll stays as the
/// fallback and simply skips ticks while the stream is connected.
class UnreadCountNotifier extends StateNotifier<int> {
  final Ref ref;
  Timer? _timer;
  UnreadCountNotifier(this.ref) : super(0) {
    ref.read(notificationsSseProvider); // arm the live channel alongside the poll
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (ref.read(notificationsSseProvider)) return; // SSE connected — no poll
      refresh();
    });
  }

  Future<void> refresh() async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      state = 0;
      return;
    }
    try {
      state = await ref.read(notificationsApiProvider).unreadCount();
    } catch (_) {
      // keep last known count on transient failure
    }
  }

  /// Authoritative server count (the SSE `connected` greeting).
  void reconcile(int count) => state = count;

  /// One new unread notification arrived on the stream.
  void bump() => state = state + 1;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final unreadCountProvider = StateNotifierProvider<UnreadCountNotifier, int>((ref) {
  // Rebuild on account switch so user B doesn't briefly see user A's badge count.
  ref.watch(currentUserSubProvider);
  return UnreadCountNotifier(ref);
});

/// The notifications list (paged). Watches the signed-in identity: notifications are the
/// viewer's own, so an account switch must drop and refetch the list.
final notificationsFeedProvider =
    StateNotifierProvider<PagedNotifier<ClubNotification>, PagedState<ClubNotification>>((ref) {
  ref.watch(currentUserSubProvider);
  final api = ref.watch(notificationsApiProvider);
  final n = PagedNotifier<ClubNotification>((cursor) => api.list(cursor: cursor));
  n.loadInitial();
  return n;
});
