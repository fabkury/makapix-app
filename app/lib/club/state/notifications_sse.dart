import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/sse.dart';
import '../models/club_notification.dart';
import 'auth_controller.dart'
    show authControllerProvider, clubApiClientProvider, currentUserSubProvider;
import 'notifications_providers.dart';

/// The live notification channel: holds `GET /realtime/notifications` (SSE)
/// open while the app is foregrounded and a user is signed in. State is
/// "connected?" — [UnreadCountNotifier] skips its poll ticks while true.
///
/// Contract (server repo `docs/http-api/notifications.md`): the `connected`
/// greeting carries the authoritative unread count (reconcile the badge to it
/// on every (re)connect); `notification` events are new items deduped by `id`;
/// `timeout` announces the normal ~300 s bounded-lifetime close (reconnect
/// immediately). Unexpected errors back off exponentially and give up after a
/// few tries — the 60 s poll then keeps the badge honest, and the next
/// foreground resume or account switch re-arms the stream.
class NotificationsSse extends StateNotifier<bool> with WidgetsBindingObserver {
  final Ref ref;

  static const _maxAttempts = 5;
  static const _baseDelay = Duration(seconds: 1);

  /// Keepalive comments arrive ~every 15 s of silence; a 60 s gap between
  /// chunks means the link is dead. Dio applies [Options.receiveTimeout]
  /// per-chunk on streamed responses, so it doubles as our stale detector
  /// (the client's default 30 s ioTimeout would work too, but stay explicit).
  static const _staleAfter = Duration(seconds: 60);

  bool _foreground = true;
  bool _disposed = false;
  bool _connecting = false;
  int _attempts = 0;
  Timer? _retry;
  CancelToken? _cancel;

  NotificationsSse(this.ref) : super(false) {
    WidgetsBinding.instance.addObserver(this);
    final ls = WidgetsBinding.instance.lifecycleState;
    // Same foreground semantics as SyncFrameClock: `inactive` is mere focus
    // loss on desktop — keep the stream; drop it only when actually hidden.
    _foreground = ls == null ||
        ls == AppLifecycleState.resumed ||
        ls == AppLifecycleState.inactive;
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || !_foreground) return;
    if (!ref.read(authControllerProvider).isSignedIn) return;
    _connecting = true;
    final cancel = _cancel = CancelToken();
    var sawTimeout = false;
    try {
      final resp = await ref.read(clubApiClientProvider).dio.get<ResponseBody>(
            '/realtime/notifications',
            options: Options(
              responseType: ResponseType.stream,
              headers: {'Accept': 'text/event-stream'},
              receiveTimeout: _staleAfter,
            ),
            cancelToken: cancel,
          );
      _attempts = 0;
      if (!_disposed) state = true;
      final parser = SseParser();
      await for (final chunk in utf8.decoder.bind(resp.data!.stream)) {
        for (final event in parser.addChunk(chunk)) {
          if (event.event == 'timeout') sawTimeout = true;
          _handle(event);
        }
      }
      if (_disposed || cancel.isCancelled) return;
      if (mounted) state = false;
      // A close right after `timeout` is the normal bounded lifetime.
      _scheduleReconnect(immediate: sawTimeout);
    } catch (_) {
      if (_disposed || cancel.isCancelled) return;
      if (mounted) state = false;
      _scheduleReconnect(immediate: false);
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect({required bool immediate}) {
    if (_disposed || !_foreground) return;
    _retry?.cancel();
    if (immediate) {
      _retry = Timer(Duration.zero, _connect);
      return;
    }
    if (_attempts >= _maxAttempts) return; // give up until resume/account switch
    final delay = _baseDelay * (1 << _attempts);
    _attempts++;
    _retry = Timer(delay, _connect);
  }

  /// One event. Malformed data is dropped (never kills the stream); the next
  /// `connected` greeting reconciles any resulting badge drift.
  void _handle(SseEvent e) {
    try {
      switch (e.event) {
        case 'connected':
          final n = ((jsonDecode(e.data) as Map?)?['unread_count'] as num?)?.toInt();
          if (n != null) ref.read(unreadCountProvider.notifier).reconcile(n);
        case 'notification':
          final item = ClubNotification.fromJson(
              (jsonDecode(e.data) as Map).cast<String, dynamic>());
          ref
              .read(notificationsFeedProvider.notifier)
              .prepend(item, same: (a, b) => a.id == b.id);
          // Bump even if the list already held it — over-count self-corrects at
          // the next greeting, whereas a missed bump would sit stale for ~5 min.
          if (!item.isRead) ref.read(unreadCountProvider.notifier).bump();
        // 'timeout' is handled by the connect loop.
      }
    } catch (_) {/* drop malformed event */}
  }

  void _teardown() {
    _retry?.cancel();
    _retry = null;
    _cancel?.cancel();
    _cancel = null;
    if (!_disposed && mounted) state = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg =
        state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _attempts = 0; // fresh network conditions — re-arm the backoff budget
      _connect();
    } else {
      _teardown();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    super.dispose();
  }
}

/// Kept warm once created (NOT autoDispose); armed lazily by
/// [unreadCountProvider], so it lives wherever the badge lives. Watches the
/// signed-in identity so an account switch tears the stream down and
/// reconnects as the new user (and sign-out leaves it idle).
final notificationsSseProvider = StateNotifierProvider<NotificationsSse, bool>((ref) {
  ref.watch(currentUserSubProvider);
  return NotificationsSse(ref);
});
