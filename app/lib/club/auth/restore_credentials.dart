import 'package:flutter/services.dart';

/// A failure from the Android Restore Credentials bridge. [code] is the platform-channel error
/// code set by `RestoreCredentials.kt`: `e2ee_unavailable`, `create_failed`, `get_failed`,
/// `clear_failed`, or `bad_args`.
class RestoreCredentialsException implements Exception {
  final String code;
  final String? message;
  const RestoreCredentialsException(this.code, [this.message]);

  /// The device can't hold a cloud-backed restore key (no screen lock, or backup disabled).
  /// The documented remedy is to retry with cloud backup off — see [RestoreCredentialsChannel.create].
  bool get isE2eeUnavailable => code == 'e2ee_unavailable';

  @override
  String toString() => 'RestoreCredentialsException($code): ${message ?? ''}';
}

/// Thin Dart side of the `club.makapix.app/restore_credentials` channel.
///
/// Carries opaque WebAuthn JSON in both directions and never parses it — the server owns the
/// contents, including the RP ID, which is how dev and prod differ with no branching here.
/// See `RestoreCredentials.kt` and docs/zero-tap-signin/DESIGN.md.
///
/// Android-only. On other platforms the channel is absent and every call raises
/// [MissingPluginException], which is mapped to the same "nothing to do" answers as a device
/// with no credential — so callers need no platform checks of their own.
class RestoreCredentialsChannel {
  static const _channel = MethodChannel('club.makapix.app/restore_credentials');

  final MethodChannel _ch;
  const RestoreCredentialsChannel([MethodChannel? channel]) : _ch = channel ?? _channel;

  /// Register a restore credential. [requestJson] is the server's creation options, passed
  /// through verbatim. Returns the registration response JSON to hand back to the server.
  ///
  /// Set [allowCloud] false only as the retry after [RestoreCredentialsException.isE2eeUnavailable];
  /// the credential then rides direct device-to-device transfer but not cloud backup.
  Future<String?> create(String requestJson, {bool allowCloud = true}) async {
    try {
      return await _ch.invokeMethod<String>(
        'create',
        {'requestJson': requestJson, 'allowCloud': allowCloud},
      );
    } on MissingPluginException {
      return null; // not Android — nothing to register
    } on PlatformException catch (e) {
      throw RestoreCredentialsException(e.code, e.message);
    }
  }

  /// Attempt a silent assertion. Returns the authentication response JSON, or **null** when
  /// there is no credential to restore — the ordinary case on a clean install, not an error.
  Future<String?> get(String requestJson) async {
    try {
      return await _ch.invokeMethod<String>('get', {'requestJson': requestJson});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      throw RestoreCredentialsException(e.code, e.message);
    }
  }

  /// Drop the local restore credential. Best-effort: never throws, because it runs during
  /// sign-out and must not be able to block it.
  Future<void> clear() async {
    try {
      await _ch.invokeMethod<void>('clear');
    } on MissingPluginException {
      // not Android
    } on PlatformException {
      // Nothing useful to do — the tokens are gone either way.
    }
  }
}
