import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_notification.dart';
import 'api_providers.dart';
import 'auth_controller.dart' show authControllerProvider;
import 'paged.dart';

/// Unread badge count, polled every 60 s while signed in (real-time MQTT in C5).
class UnreadCountNotifier extends StateNotifier<int> {
  final Ref ref;
  Timer? _timer;
  UnreadCountNotifier(this.ref) : super(0) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final unreadCountProvider =
    StateNotifierProvider<UnreadCountNotifier, int>((ref) => UnreadCountNotifier(ref));

/// The notifications list (paged).
final notificationsFeedProvider =
    StateNotifierProvider<PagedNotifier<ClubNotification>, PagedState<ClubNotification>>((ref) {
  final api = ref.watch(notificationsApiProvider);
  final n = PagedNotifier<ClubNotification>((cursor) => api.list(cursor: cursor));
  n.loadInitial();
  return n;
});
