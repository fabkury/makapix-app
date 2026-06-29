import 'package:dio/dio.dart';

import '../auth/club_session.dart';
import '../config/club_config.dart';
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
}
