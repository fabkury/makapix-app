import '../models/club_notification.dart';
import '../models/page.dart';
import 'club_api_client.dart';

/// Social notifications (polling in C1; real-time MQTT arrives in C5).
class NotificationsApi {
  final ClubApiClient client;
  NotificationsApi(this.client);

  Future<Page<ClubNotification>> list({String? cursor, bool unreadOnly = false, int limit = 30}) {
    final q = <String, dynamic>{'unread_only': unreadOnly, 'limit': limit};
    if (cursor != null) q['cursor'] = cursor;
    return client.guard(() async {
      final resp = await client.dio.get('/social-notifications/', queryParameters: q);
      return Page<ClubNotification>.fromJson(
          (resp.data as Map).cast<String, dynamic>(), ClubNotification.fromJson);
    });
  }

  Future<int> unreadCount() => client.guard(() async {
        final resp = await client.dio.get('/social-notifications/unread-count');
        return ((resp.data as Map?)?['unread_count'] as num?)?.toInt() ?? 0;
      });

  Future<void> markRead(List<String> ids) =>
      client.guard(() => client.dio.post('/social-notifications/mark-read', data: ids));

  Future<void> markAllRead() =>
      client.guard(() => client.dio.post('/social-notifications/mark-all-read'));
}
