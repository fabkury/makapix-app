import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/player_api.dart';
import '../models/club_error.dart';
import '../models/player_device.dart';
import 'api_providers.dart';
import 'auth_controller.dart';

/// One of the four optimistically-controllable fields.
enum PlayerField { isPaused, brightness, rotation, mirror }

/// An optimistic overlay for a single device: values the user just commanded that the device
/// hasn't confirmed yet. A field is non-null while pending, then cleared once a poll reports the
/// device matching it (or after a timeout / on failure).
class PendingPatch {
  final bool? isPaused;
  final int? brightness;
  final int? rotation;
  final String? mirror;
  const PendingPatch({this.isPaused, this.brightness, this.rotation, this.mirror});

  bool get isEmpty =>
      isPaused == null && brightness == null && rotation == null && mirror == null;

  PendingPatch mergeWith(PendingPatch o) => PendingPatch(
        isPaused: o.isPaused ?? isPaused,
        brightness: o.brightness ?? brightness,
        rotation: o.rotation ?? rotation,
        mirror: o.mirror ?? mirror,
      );

  PendingPatch clear(PlayerField f) => PendingPatch(
        isPaused: f == PlayerField.isPaused ? null : isPaused,
        brightness: f == PlayerField.brightness ? null : brightness,
        rotation: f == PlayerField.rotation ? null : rotation,
        mirror: f == PlayerField.mirror ? null : mirror,
      );
}

/// What "Send to Player" should send, set by the page the user is browsing (the app's analogue
/// of the website's `selectedArtwork` / `currentChannel`).
sealed class PlayerSendTarget {
  const PlayerSendTarget();
  String get label;
}

class ArtworkTarget extends PlayerSendTarget {
  final int postId;
  final String title;
  const ArtworkTarget({required this.postId, required this.title});
  @override
  String get label => title.trim().isEmpty ? 'Artwork' : title.trim();

  @override
  bool operator ==(Object other) =>
      other is ArtworkTarget && other.postId == postId && other.title == title;
  @override
  int get hashCode => Object.hash(postId, title);
}

class ChannelTarget extends PlayerSendTarget {
  final String displayName;
  final String? channelName; // promoted | all | by_user | hashtag | reactions
  final String? hashtag;
  final String? userSqid;
  final String? userHandle;
  const ChannelTarget({
    required this.displayName,
    this.channelName,
    this.hashtag,
    this.userSqid,
    this.userHandle,
  });
  @override
  String get label => displayName;

  PlayerCommand toCommand() => PlayerCommand(
        commandType: 'play_channel',
        // Mirror the website: explicit channel, else infer `by_user` from a user sqid, else leave
        // it out (a hashtag channel is identified by its `hashtag` field alone).
        channelName: channelName ?? (userSqid != null ? 'by_user' : null),
        hashtag: hashtag,
        userSqid: userSqid,
        userHandle: userHandle,
      );

  @override
  bool operator ==(Object other) =>
      other is ChannelTarget &&
      other.displayName == displayName &&
      other.channelName == channelName &&
      other.hashtag == hashtag &&
      other.userSqid == userSqid &&
      other.userHandle == userHandle;
  @override
  int get hashCode => Object.hash(displayName, channelName, hashtag, userSqid, userHandle);
}

/// Immutable Player Bar state.
class PlayerState {
  final List<PlayerDevice> players;
  final String? activePlayerId;
  final Map<String, PendingPatch> pending;
  final bool loading;

  const PlayerState({
    this.players = const [],
    this.activePlayerId,
    this.pending = const {},
    this.loading = false,
  });

  List<PlayerDevice> get onlinePlayers =>
      players.where((p) => p.isOnline).toList(growable: false);
  bool get hasOnlinePlayer => players.any((p) => p.isOnline);

  /// The device commands target: the chosen active player if still online, else the first
  /// online one, else null.
  PlayerDevice? get activePlayer {
    final online = onlinePlayers;
    for (final p in online) {
      if (p.id == activePlayerId) return p;
    }
    return online.isNotEmpty ? online.first : null;
  }

  PendingPatch? pendingFor(String playerId) => pending[playerId];

  /// copyWith for the non-ambiguous fields. `activePlayerId` is set by building [PlayerState]
  /// directly (so passing null can mean "clear", not "keep").
  PlayerState copyWith({
    List<PlayerDevice>? players,
    Map<String, PendingPatch>? pending,
    bool? loading,
  }) =>
      PlayerState(
        players: players ?? this.players,
        activePlayerId: activePlayerId,
        pending: pending ?? this.pending,
        loading: loading ?? this.loading,
      );
}

/// Polls the player list (~every 15 s while signed in) and owns command + optimistic-overlay
/// logic. Modeled on `UnreadCountNotifier` (a `Timer.periodic` gated on `isSignedIn`).
class PlayerController extends StateNotifier<PlayerState> {
  final Ref ref;
  Timer? _timer;
  String? _sqid;
  final Map<String, int> _pendingTokens = {};

  PlayerController(this.ref) : super(const PlayerState(loading: true)) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
  }

  PlayerApi get _api => ref.read(playerApiProvider);

  Future<void> refresh() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isSignedIn) {
      _sqid = null;
      if (state.players.isNotEmpty || state.loading || state.activePlayerId != null) {
        state = const PlayerState();
      }
      return;
    }
    final sqid = auth.me?.user.sub;
    if (sqid == null || sqid.isEmpty) return;
    if (sqid != _sqid) {
      _sqid = sqid;
      await _restoreActive(sqid); // restore each account's last pick
    }
    try {
      _applyPlayers(await _api.list(sqid));
    } catch (_) {
      // Keep the last-known list on a transient failure; just drop the initial spinner.
      if (state.loading) state = state.copyWith(loading: false);
    }
  }

  void _applyPlayers(List<PlayerDevice> players) {
    // Reconcile pending overlays the device now confirms.
    final pending = Map<String, PendingPatch>.from(state.pending);
    for (final p in players) {
      var pp = pending[p.id];
      if (pp == null) continue;
      if (pp.isPaused != null && pp.isPaused == p.isPaused) pp = pp.clear(PlayerField.isPaused);
      if (pp.brightness != null && pp.brightness == p.brightness) {
        pp = pp.clear(PlayerField.brightness);
      }
      if (pp.rotation != null && pp.rotation == p.rotation) pp = pp.clear(PlayerField.rotation);
      if (pp.mirror != null && pp.mirror == p.mirror) pp = pp.clear(PlayerField.mirror);
      if (pp.isEmpty) {
        pending.remove(p.id);
      } else {
        pending[p.id] = pp;
      }
    }

    // Auto-pick / auto-replace the active player as the online set changes.
    final online = players.where((p) => p.isOnline).toList();
    String? active = state.activePlayerId;
    if (online.isEmpty) {
      active = null;
    } else if (active == null || !online.any((p) => p.id == active)) {
      active = online.first.id;
    }

    state = PlayerState(
      players: players,
      activePlayerId: active,
      pending: pending,
      loading: false,
    );
  }

  String _prefKey(String sqid) => 'player_bar.active_player_id.$sqid';

  Future<void> _restoreActive(String sqid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey(sqid));
      state = PlayerState(
        players: state.players,
        activePlayerId: saved,
        pending: state.pending,
        loading: state.loading,
      );
    } catch (_) {/* ignore — defaults to auto-pick */}
  }

  Future<void> setActivePlayer(String? id) async {
    state = PlayerState(
      players: state.players,
      activePlayerId: id,
      pending: state.pending,
      loading: state.loading,
    );
    final sqid = _sqid;
    if (sqid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id != null) {
        await prefs.setString(_prefKey(sqid), id);
      } else {
        await prefs.remove(_prefKey(sqid));
      }
    } catch (_) {/* ignore */}
  }

  // ---- Main commands. Return null on success, else a user-facing error message. ----

  Future<String?> send(String playerId, PlayerSendTarget target) {
    return switch (target) {
      ArtworkTarget(:final postId) => _command(playerId, PlayerCommand.showArtwork(postId)),
      ChannelTarget() => _command(playerId, target.toCommand()),
    };
  }

  Future<String?> swapNext(String playerId) =>
      _command(playerId, const PlayerCommand.swapNext());
  Future<String?> swapBack(String playerId) =>
      _command(playerId, const PlayerCommand.swapBack());

  Future<String?> _command(String playerId, PlayerCommand cmd) async {
    final sqid = _sqid;
    if (sqid == null) return 'Not signed in.';
    try {
      await _api.command(sqid, playerId, cmd);
      return null;
    } on ClubError catch (e) {
      return e.message;
    }
  }

  // ---- Lifecycle: register / rename / remove. Read the sqid fresh from auth, since the
  // My Players screen can be opened before the first poll sets `_sqid` (e.g. no device online,
  // so the Player Bar never mounted). Each returns null on success, else an error message. ----

  Future<String?> register({required String code, required String name}) async {
    if (!ref.read(authControllerProvider).isSignedIn) return 'Not signed in.';
    try {
      await _api.register(code: code, name: name);
      await refresh(); // pull the newly-registered device into the list
      return null;
    } on ClubError catch (e) {
      return e.message;
    }
  }

  Future<String?> rename(String playerId, String name) async {
    final sqid = ref.read(authControllerProvider).me?.user.sub;
    if (sqid == null || sqid.isEmpty) return 'Not signed in.';
    try {
      final updated = await _api.updateName(sqid, playerId, name);
      _applyPlayers([
        for (final p in state.players)
          if (p.id == playerId) updated else p,
      ]);
      return null;
    } on ClubError catch (e) {
      return e.message;
    }
  }

  Future<String?> remove(String playerId) async {
    final sqid = ref.read(authControllerProvider).me?.user.sub;
    if (sqid == null || sqid.isEmpty) return 'Not signed in.';
    try {
      await _api.delete(sqid, playerId);
      // Drop any optimistic overlay for the gone device, then re-run the auto-pick.
      final pending = Map<String, PendingPatch>.from(state.pending)..remove(playerId);
      state = state.copyWith(pending: pending);
      _applyPlayers(state.players.where((p) => p.id != playerId).toList());
      return null;
    } on ClubError catch (e) {
      return e.message;
    }
  }

  // ---- Optional (optimistic) commands. ----

  Future<void> setPaused(String playerId, bool paused) => _optimistic(
        playerId,
        PlayerField.isPaused,
        PendingPatch(isPaused: paused),
        () => _api.setPause(_sqid!, playerId, paused),
      );

  Future<void> setBrightness(String playerId, int value) => _optimistic(
        playerId,
        PlayerField.brightness,
        PendingPatch(brightness: value),
        () => _api.setBrightness(_sqid!, playerId, value),
      );

  Future<void> setRotation(String playerId, int value) => _optimistic(
        playerId,
        PlayerField.rotation,
        PendingPatch(rotation: value),
        () => _api.setRotation(_sqid!, playerId, value),
      );

  Future<void> setMirror(String playerId, String value) => _optimistic(
        playerId,
        PlayerField.mirror,
        PendingPatch(mirror: value),
        () => _api.setMirror(_sqid!, playerId, value),
      );

  Future<void> _optimistic(
    String playerId,
    PlayerField field,
    PendingPatch patch,
    Future<void> Function() call,
  ) async {
    if (_sqid == null) return;
    _setPending(playerId, patch);
    final key = '$playerId:${field.name}';
    final token = (_pendingTokens[key] ?? 0) + 1;
    _pendingTokens[key] = token;
    // Revert if the device never confirms within the window.
    Timer(const Duration(seconds: 5), () {
      if (_pendingTokens[key] == token) _clearPending(playerId, field);
    });
    try {
      await call();
    } on ClubError catch (_) {
      if (_pendingTokens[key] == token) _clearPending(playerId, field);
    }
  }

  void _setPending(String playerId, PendingPatch patch) {
    final pending = Map<String, PendingPatch>.from(state.pending);
    pending[playerId] = (pending[playerId] ?? const PendingPatch()).mergeWith(patch);
    state = state.copyWith(pending: pending);
  }

  void _clearPending(String playerId, PlayerField field) {
    final cur = state.pending[playerId];
    if (cur == null) return;
    final pending = Map<String, PendingPatch>.from(state.pending);
    final next = cur.clear(field);
    if (next.isEmpty) {
      pending.remove(playerId);
    } else {
      pending[playerId] = next;
    }
    state = state.copyWith(pending: pending);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Kept warm for the app lifetime (NOT autoDispose) so the bar reappears instantly when the user
/// returns to the Club pillar from the editor.
final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerState>((ref) => PlayerController(ref));

/// The artwork/channel the current Club page offers to "Send to Player". Null hides/disables send.
final playerSendTargetProvider = StateProvider<PlayerSendTarget?>((_) => null);
