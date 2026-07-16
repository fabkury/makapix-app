import 'package:dio/dio.dart';

import '../auth/club_session.dart';
import '../config/club_config.dart';
import '../models/account.dart';
import '../models/club_error.dart';

/// Authenticated Dio for all Club endpoints. Attaches the bearer token and, on
/// 401, performs a single-flight refresh (via [ClubSession]) and retries the
/// original request once.
///
/// Two clients share that behaviour: [dio] (the versioned `/api/v1` base, used by
/// almost everything) and [dioRoot] (the unversioned `/api` base, used by the Post
/// Management Dashboard `/pmd/*`, which the server mounts outside `/v1`).
class ClubApiClient {
  final ClubSession session;
  late final Dio dio;
  late final Dio dioRoot;

  ClubApiClient(this.session) {
    dio = _build(session.config.apiBase);
    dioRoot = _build(session.config.apiRoot);
  }

  Dio _build(String baseUrl) {
    final client = Dio(BaseOptions(
      baseUrl: baseUrl,
      contentType: 'application/json',
      connectTimeout: ClubConfig.connectTimeout, // [audit F-7]
      receiveTimeout: ClubConfig.ioTimeout,
      sendTimeout: ClubConfig.ioTimeout,
    ));
    client.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final tok = session.accessToken;
        if (tok != null) options.headers['Authorization'] = 'Bearer $tok';
        handler.next(options);
      },
      onError: (e, handler) async {
        final retried = e.requestOptions.extra['__retried'] == true;
        final canRefresh = e.response?.statusCode == 401 &&
            !retried &&
            session.tokens?.refreshToken != null;
        if (canRefresh) {
          final ok = await session.refresh();
          if (ok) {
            final opts = e.requestOptions;
            opts.extra['__retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${session.accessToken}';
            try {
              return handler.resolve(await client.fetch(opts));
            } on DioException catch (e2) {
              return handler.next(e2);
            }
          }
        }
        handler.next(e);
      },
    ));
    return client;
  }

  /// Run a Dio call and normalize any [DioException] to a [ClubError] — the single place that
  /// mapping lives, instead of the same try/catch repeated in every API method. [audit F-22]
  Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// `GET /auth/me` as raw JSON (caller maps to [ClubMe]).
  Future<Map<String, dynamic>> me() => guard(() async {
        final resp = await dio.get('/auth/me');
        return (resp.data as Map).cast<String, dynamic>();
      });

  // ---- account management (authenticated; SPEC-CLUB §6 / C0b) ----

  /// `POST /auth/change-password`. Also the wizard's "set your password" step
  /// (where `current` is the server-emailed temporary password).
  Future<void> changePassword(String current, String next) => guard(() async {
        await dio.post('/auth/change-password',
            data: {'current_password': current, 'new_password': next});
      });

  /// `POST /auth/check-handle-availability` (authed → excludes the caller's own
  /// handle, so re-saving an unchanged handle reads as available).
  Future<HandleAvailability> checkHandle(String handle) => guard(() async {
        final resp = await dio.post('/auth/check-handle-availability', data: {'handle': handle});
        return HandleAvailability.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// `POST /auth/change-handle` → the server's resulting handle.
  Future<String> changeHandle(String newHandle) => guard(() async {
        final resp = await dio.post('/auth/change-handle', data: {'new_handle': newHandle});
        return ((resp.data as Map?)?['handle'] ?? newHandle).toString();
      });

  /// `POST /auth/complete-welcome` — finishes onboarding (flips `needs_welcome`).
  Future<void> completeWelcome() => guard(() async {
        await dio.post('/auth/complete-welcome');
      });

  /// `GET /auth/providers` — the user's linked authentication methods.
  Future<List<AuthIdentity>> listProviders() => guard(() async {
        final resp = await dio.get('/auth/providers');
        final list = (resp.data as Map?)?['identities'] as List? ?? const [];
        return list
            .map((e) => AuthIdentity.fromJson((e as Map).cast<String, dynamic>()))
            .toList(growable: false);
      });

  /// `DELETE /auth/providers/{provider}/{identity_id}` — unlink a method
  /// (server rejects unlinking the last one with 400).
  Future<void> unlinkProvider(String provider, String identityId) => guard(() async {
        await dio.delete(
            '/auth/providers/${Uri.encodeComponent(provider)}/${Uri.encodeComponent(identityId)}');
      });

  /// `PATCH /user/{user_key}` (path resolves by UUID only). Only non-null
  /// arguments are sent; `''` clears a field server-side (stored as an empty
  /// string, not NULL), while an omitted field is left unchanged.
  Future<void> updateProfile(String userKey, {String? bio, String? tagline}) => guard(() async {
        await dio.patch('/user/${Uri.encodeComponent(userKey)}',
            data: {'bio': ?bio, 'tagline': ?tagline});
      });

  /// `POST /user/{user_key}/avatar` (multipart) → the new avatar URL, if returned.
  Future<String?> uploadAvatar(String userKey, List<int> bytes, String filename) =>
      guard(() async {
        final form = FormData.fromMap(
            {'image': MultipartFile.fromBytes(bytes, filename: filename)});
        final resp = await dio.post('/user/${Uri.encodeComponent(userKey)}/avatar', data: form);
        return (resp.data as Map?)?['avatar_url'] as String?;
      });

  /// `DELETE /user/{user_key}/avatar` — clears the avatar (server also
  /// best-effort deletes the stored file).
  Future<void> deleteAvatar(String userKey) => guard(() async {
        await dio.delete('/user/${Uri.encodeComponent(userKey)}/avatar');
      });

  /// `POST /user/delete-account` → 202 — request permanent deletion of the
  /// signed-in account. The server deactivates the account immediately (login
  /// stops working) and deletes all user data asynchronously; owner-role
  /// accounts are refused. App Store guideline 5.1.1(v).
  Future<void> requestAccountDeletion() => guard(() async {
        await dio.post('/user/delete-account');
      });
}
