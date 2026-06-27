import 'package:dio/dio.dart';

import '../models/club_error.dart';
import '../models/club_notification.dart';
import '../models/page.dart';
import 'club_api_client.dart';

/// Social notifications (polling in C1; real-time MQTT arrives in C5).
class NotificationsApi {
  final ClubApiClient client;
  NotificationsApi(this.client);

  Future<Page<ClubNotification>> list({String? cursor, bool unreadOnly = false, int limit = 30}) async {
    final q = <String, dynamic>{'unread_only': unreadOnly, 'limit': limit};
    if (cursor != null) q['cursor'] = cursor;
    try {
      final resp = await client.dio.get('/social-notifications/', queryParameters: q);
      return Page<ClubNotification>.fromJson(
          (resp.data as Map).cast<String, dynamic>(), ClubNotification.fromJson);
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  Future<int> unreadCount() async {
    try {
      final resp = await client.dio.get('/social-notifications/unread-count');
      return ((resp.data as Map?)?['unread_count'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  Future<void> markRead(List<String> ids) => _ed(() =>
      client.dio.post('/social-notifications/mark-read', data: ids));

  Future<void> markAllRead() =>
      _ed(() => client.dio.post('/social-notifications/mark-all-read'));

  Future<void> _ed(Future<Response> Function() call) async {
    try {
      await call();
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }
}
