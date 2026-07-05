import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/auth_api.dart';
import '../api/edit_api.dart';
import '../api/feed_api.dart';
import '../api/mkpx_api.dart';
import '../api/moderation_api.dart';
import '../api/notifications_api.dart';
import '../api/player_api.dart';
import '../api/post_api.dart';
import '../api/profile_api.dart';
import '../api/search_api.dart';
import '../api/pmd_api.dart';
import '../api/settings_api.dart';
import '../api/stats_api.dart';
import 'auth_controller.dart' show clubApiClientProvider, clubConfigProvider;

/// The unauthenticated account-lifecycle client (register / OTP / handle-check).
final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(clubConfigProvider)));

final feedApiProvider = Provider<FeedApi>((ref) => FeedApi(ref.watch(clubApiClientProvider)));
final postApiProvider = Provider<PostApi>((ref) => PostApi(ref.watch(clubApiClientProvider)));
final profileApiProvider = Provider<ProfileApi>((ref) => ProfileApi(ref.watch(clubApiClientProvider)));
final searchApiProvider = Provider<SearchApi>((ref) => SearchApi(ref.watch(clubApiClientProvider)));
final notificationsApiProvider =
    Provider<NotificationsApi>((ref) => NotificationsApi(ref.watch(clubApiClientProvider)));
final playerApiProvider = Provider<PlayerApi>((ref) => PlayerApi(ref.watch(clubApiClientProvider)));
final editApiProvider = Provider<EditApi>((ref) => EditApi());
final mkpxApiProvider = Provider<MkpxApi>((ref) => MkpxApi(ref.watch(clubApiClientProvider)));
final settingsApiProvider =
    Provider<SettingsApi>((ref) => SettingsApi(ref.watch(clubApiClientProvider)));
final statsApiProvider =
    Provider<StatsApi>((ref) => StatsApi(ref.watch(clubApiClientProvider)));
final pmdApiProvider = Provider<PmdApi>((ref) => PmdApi(ref.watch(clubApiClientProvider)));
final moderationApiProvider =
    Provider<ModerationApi>((ref) => ModerationApi(ref.watch(clubApiClientProvider)));
