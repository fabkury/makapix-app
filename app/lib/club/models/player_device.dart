/// A player device (a physical pixel display) owned by the signed-in user, as returned by
/// `GET /api/u/{sqid}/player`. Hand-written `fromJson`, mirroring `models/post.dart`.
class PlayerDevice {
  final String id;
  final String playerKey;
  final String? name;
  final String? deviceModel;
  final String? firmwareVersion;
  final String connectionStatus; // "online" | "offline"
  final int? currentPostId;
  final PlayerCapabilities capabilities;
  final bool? isPaused;
  final int? brightness;
  final int? rotation;
  final String? mirror;

  const PlayerDevice({
    required this.id,
    required this.playerKey,
    this.name,
    this.deviceModel,
    this.firmwareVersion,
    required this.connectionStatus,
    this.currentPostId,
    required this.capabilities,
    this.isPaused,
    this.brightness,
    this.rotation,
    this.mirror,
  });

  bool get isOnline => connectionStatus == 'online';

  /// User-given name, else the device model, else a generic fallback.
  String get displayName {
    final n = name;
    if (n != null && n.trim().isNotEmpty) return n.trim();
    final m = deviceModel;
    if (m != null && m.trim().isNotEmpty) return m.trim();
    return 'Player';
  }

  factory PlayerDevice.fromJson(Map<String, dynamic> j) => PlayerDevice(
        id: (j['id'] ?? '').toString(),
        playerKey: (j['player_key'] ?? '').toString(),
        name: j['name'] as String?,
        deviceModel: j['device_model'] as String?,
        firmwareVersion: j['firmware_version'] as String?,
        connectionStatus: (j['connection_status'] ?? 'offline').toString(),
        currentPostId: (j['current_post_id'] as num?)?.toInt(),
        capabilities: PlayerCapabilities.fromJson(
          j['capabilities'] is Map
              ? (j['capabilities'] as Map).cast<String, dynamic>()
              : const {},
        ),
        isPaused: j['is_paused'] as bool?,
        brightness: (j['brightness'] as num?)?.toInt(),
        rotation: (j['rotation'] as num?)?.toInt(),
        mirror: j['mirror'] as String?,
      );
}

/// Brightness control spec declared by a device.
class BrightnessSpec {
  final int min;
  final int max;
  final int step;
  const BrightnessSpec({required this.min, required this.max, required this.step});
}

/// Parsed capability declaration. Absent features become `pause=false`, `brightness=null`,
/// and empty lists, so the UI can gate purely on these without re-checking the raw dict.
class PlayerCapabilities {
  final bool pause;
  final BrightnessSpec? brightness;
  final List<int> rotation;
  final List<String> mirror;

  const PlayerCapabilities({
    this.pause = false,
    this.brightness,
    this.rotation = const [],
    this.mirror = const [],
  });

  bool get hasAdjustments =>
      brightness != null || rotation.isNotEmpty || mirror.isNotEmpty;

  factory PlayerCapabilities.fromJson(Map<String, dynamic> j) {
    BrightnessSpec? b;
    final bj = j['brightness'];
    if (bj is Map) {
      b = BrightnessSpec(
        min: (bj['min'] as num?)?.toInt() ?? 0,
        max: (bj['max'] as num?)?.toInt() ?? 100,
        step: (bj['step'] as num?)?.toInt() ?? 1,
      );
    }
    final rj = j['rotation'];
    final rotation = rj is Map && rj['values'] is List
        ? (rj['values'] as List).map((e) => (e as num).toInt()).toList()
        : const <int>[];
    final mj = j['mirror'];
    final mirror = mj is Map && mj['values'] is List
        ? (mj['values'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    return PlayerCapabilities(
      // `pause` is declared as an empty dict (`{}`) when supported, absent otherwise.
      pause: j['pause'] != null,
      brightness: b,
      rotation: rotation,
      mirror: mirror,
    );
  }
}
