import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../api/club_api_client.dart';
import '../models/club_error.dart';
import 'club_session.dart';
import 'restore_credentials.dart';

/// Zero-Tap Sign-In orchestration: registers a Restore Credential after sign-in, and attempts a
/// silent assertion on the first launch after a device migration.
///
/// Google Play requires this from April 2027. Without it, a migrating user lands signed out —
/// measured, not assumed: artwork restores intact but the token store cannot (its Keystore key is
/// non-exportable). See docs/zero-tap-signin/DESIGN.md.
///
/// **Every path here is best-effort and silent.** Zero-Tap is an enhancement layered on top of the
/// normal flow; it must never block sign-in, never surface an error, and never keep the user on
/// the launch spinner. Failures degrade to exactly today's behavior.
class RestoreCredentialService {
  final ClubSession session;
  final ClubApiClient api;
  final RestoreCredentialsChannel channel;

  /// Android-only feature. Injectable so tests can exercise the logic off-device.
  final bool enabled;

  /// Hard ceiling on the cold-start attempt. This runs while the UI shows the launch spinner, so
  /// an unresponsive Credential Manager or a hung network call must not be able to strand the app
  /// there — on expiry we simply carry on to the signed-out screen.
  static const attemptTimeout = Duration(seconds: 8);

  RestoreCredentialService({
    required this.session,
    required this.api,
    this.channel = const RestoreCredentialsChannel(),
    bool? enabled,
  }) : enabled = enabled ?? Platform.isAndroid;

  /// Register this device's restore credential. Call **once per interactive sign-in**, wired via
  /// [ClubSession.onInteractiveSignIn].
  ///
  /// Fire-and-forget: callers should not await this on the sign-in path.
  ///
  /// Do **not** call it on every launch. Credential Manager mints a *new* credential each time, so
  /// `credential_id` differs on every call and the server's upsert-on-`credential_id` never fires —
  /// it inserts. Android keeps only one restore key per app per device, so every extra call
  /// permanently orphans the previous row (server message 0007 observed exactly that). The
  /// `E2eeUnavailableException` retry below is the one legitimate double-registration.
  Future<void> register() async {
    if (!enabled) return;
    try {
      final options = await api.restoreOptions();
      String? response;
      try {
        response = await channel.create(options);
      } on RestoreCredentialsException catch (e) {
        if (!e.isE2eeUnavailable) rethrow;
        // No screen lock, or backup is off, so the key can't be cloud-escrowed. Retry local-only:
        // the credential then rides direct device-to-device transfer but not a cloud restore.
        // Needs a fresh challenge — the first one was consumed by the failed attempt.
        response = await channel.create(await api.restoreOptions(), allowCloud: false);
      }
      if (response == null) return; // not Android after all
      await api.restoreRegister(response);
    } catch (e) {
      // Swallowed by design: a user who can't register a restore credential simply doesn't get
      // Zero-Tap on their next device. Nothing about the current session is affected.
      debugPrint('[zero-tap] register skipped: $e');
    }
  }

  /// Attempt a silent sign-in from a restore credential. Returns true only if tokens were minted.
  ///
  /// Called on cold start when the token store is empty — overwhelmingly a clean install, where
  /// the platform reports no credential and this costs one round trip.
  Future<bool> tryRestore() async {
    if (!enabled) return false;
    try {
      return await _attempt().timeout(attemptTimeout, onTimeout: () {
        debugPrint('[zero-tap] restore timed out after $attemptTimeout');
        return false;
      });
    } catch (e) {
      debugPrint('[zero-tap] restore skipped: $e');
      return false;
    }
  }

  Future<bool> _attempt() async {
    final challenge = await session.restoreChallenge();
    final assertion = await channel.get(challenge);
    // The ordinary case on a clean install: nothing to restore. Not an error, not logged as one.
    if (assertion == null) return false;
    try {
      await session.loginRestoreCredential(assertion);
      return true;
    } on ClubError catch (e) {
      // The server doesn't know this credential (e.g. it was revoked, or it belongs to the other
      // environment's RP). An ordinary signed-out start.
      if (e.code == 'restore_credential_unknown') return false;
      rethrow;
    }
  }

  /// Drop the local credential on explicit sign-out.
  ///
  /// Deliberately **not** wired to [ClubSession.clear], which also fires on involuntary clears
  /// (corrupt secure storage, a 401 on `/auth/me`, a failed refresh). Those are recoverable
  /// conditions where destroying the credential would cost the user their next silent sign-in for
  /// no security benefit. Explicit logout is the user saying "forget me on this device".
  Future<void> clear() async {
    if (!enabled) return;
    await channel.clear();
  }
}
