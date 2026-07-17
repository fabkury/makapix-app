import '../models/player_device.dart';
import 'club_api_client.dart';

/// Normalize typed registration-code input to the server's alphabet: upper-case, keep only
/// `[A-Z0-9]`, and cap at 6 characters. The server upper-cases too and generates codes from an
/// alphabet excluding ambiguous `0 O I 1 L`. Shared by the register UI's input formatter and
/// exercised in tests.
String normalizeRegistrationCode(String input) {
  var t = input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (t.length > 6) t = t.substring(0, 6);
  return t;
}

/// A main command for `POST /api/u/{sqid}/player/{playerId}/command`. `toJson` drops null
/// fields (like `FeedApi._posts`), so only the keys a command needs are sent.
class PlayerCommand {
  final String commandType; // swap_next | swap_back | show_artwork | play_channel
  final int? postId;
  final String? channelName;
  final String? hashtag;
  final String? userSqid;
  final String? userHandle;

  const PlayerCommand({
    required this.commandType,
    this.postId,
    this.channelName,
    this.hashtag,
    this.userSqid,
    this.userHandle,
  });

  const PlayerCommand.swapNext() : this(commandType: 'swap_next');
  const PlayerCommand.swapBack() : this(commandType: 'swap_back');
  const PlayerCommand.showArtwork(int postId)
      : this(commandType: 'show_artwork', postId: postId);

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'command_type': commandType,
      'post_id': postId,
      'channel_name': channelName,
      'hashtag': hashtag,
      'user_sqid': userSqid,
      'user_handle': userHandle,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}

/// Typed REST client for player listing + control.
///
/// Player routes are mounted at the API root (`/api/u/{sqid}/player...`), NOT under the
/// versioned `/api/v1` base every other Club API uses — so this client builds absolute URLs
/// off `config.baseUrl` rather than relying on the Dio `baseUrl`. The bearer header is still
/// attached by the shared `ClubApiClient` interceptor.
class PlayerApi {
  final ClubApiClient client;
  PlayerApi(this.client);

  String _base(String sqid) =>
      '${client.session.config.baseUrl}/api/u/${Uri.encodeComponent(sqid)}/player';

  Future<List<PlayerDevice>> list(String sqid) => client.guard(() async {
        final resp = await client.dio.get(_base(sqid));
        final data = (resp.data as Map).cast<String, dynamic>();
        final items = (data['items'] as List?) ?? const [];
        return items
            .map((e) => PlayerDevice.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Register (claim) a player to the signed-in user via the 6-char code shown on the device.
  /// Unlike the other routes this one is mounted at the API root (`/api/player/register`), not
  /// under `/u/{sqid}`. Returns the newly-registered device.
  Future<PlayerDevice> register({required String code, required String name}) =>
      client.guard(() async {
        final resp = await client.dio.post(
          '${client.session.config.baseUrl}/api/player/register',
          data: {'registration_code': code, 'name': name},
        );
        return PlayerDevice.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// Rename a registered player. Returns the updated device.
  Future<PlayerDevice> updateName(String sqid, String playerId, String name) =>
      client.guard(() async {
        final resp =
            await client.dio.patch('${_base(sqid)}/$playerId', data: {'name': name});
        return PlayerDevice.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  /// Remove a player registration (server tears down its cert + MQTT access).
  Future<void> delete(String sqid, String playerId) =>
      client.guard(() => client.dio.delete('${_base(sqid)}/$playerId'));

  Future<void> command(String sqid, String playerId, PlayerCommand cmd) => client
      .guard(() => client.dio.post('${_base(sqid)}/$playerId/command', data: cmd.toJson()));

  Future<void> setPause(String sqid, String playerId, bool paused) => client.guard(
      () => client.dio.post('${_base(sqid)}/$playerId/pause', data: {'paused': paused}));

  Future<void> setBrightness(String sqid, String playerId, int value) => client.guard(
      () => client.dio.post('${_base(sqid)}/$playerId/brightness', data: {'value': value}));

  Future<void> setRotation(String sqid, String playerId, int value) => client.guard(
      () => client.dio.post('${_base(sqid)}/$playerId/rotation', data: {'value': value}));

  Future<void> setMirror(String sqid, String playerId, String value) => client.guard(
      () => client.dio.post('${_base(sqid)}/$playerId/mirror', data: {'value': value}));
}
