import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/feed_api.dart';
import '../api/notifications_api.dart';
import '../api/post_api.dart';
import '../api/profile_api.dart';
import '../api/search_api.dart';
import 'auth_controller.dart' show clubApiClientProvider;

final feedApiProvider = Provider<FeedApi>((ref) => FeedApi(ref.watch(clubApiClientProvider)));
final postApiProvider = Provider<PostApi>((ref) => PostApi(ref.watch(clubApiClientProvider)));
final profileApiProvider = Provider<ProfileApi>((ref) => ProfileApi(ref.watch(clubApiClientProvider)));
final searchApiProvider = Provider<SearchApi>((ref) => SearchApi(ref.watch(clubApiClientProvider)));
final notificationsApiProvider =
    Provider<NotificationsApi>((ref) => NotificationsApi(ref.watch(clubApiClientProvider)));
