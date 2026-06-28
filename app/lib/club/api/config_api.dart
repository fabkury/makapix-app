import '../models/server_config.dart';
import 'club_api_client.dart';

/// `GET /api/v1/config` — server-authoritative upload rules + limits (public).
class ConfigApi {
  final ClubApiClient client;
  ConfigApi(this.client);

  Future<ClubServerConfig> fetch() => client.guard(() async {
        final resp = await client.dio.get('/config');
        return ClubServerConfig.fromJson((resp.data as Map).cast<String, dynamic>());
      });
}
