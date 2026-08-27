import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/api/club_api_client.dart';
import 'package:makapix_club/club/auth/club_session.dart';
import 'package:makapix_club/club/auth/restore_credential_service.dart';
import 'package:makapix_club/club/auth/restore_credentials.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/auth_tokens.dart';
import 'package:makapix_club/club/models/club_error.dart';

/// Zero-Tap Sign-In (Android Restore Credentials) — see docs/zero-tap-signin/DESIGN.md.
///
/// Runs entirely off-device: the service's `enabled` flag is injected rather than read from
/// Platform.isAndroid, and every collaborator is a hand-written fake (the repo has no mocking
/// framework). No engine binary and no network, per the Club test rule.

const _options = '{"rp":{"id":"makapix.club"},"challenge":"opt"}';
const _challenge = '{"challenge":"chal","rpId":"makapix.club","allowCredentials":[]}';
const _assertion = '{"id":"cred-1","response":{"signature":"sig"}}';

class _FakeSession extends ClubSession {
  _FakeSession() : super(config: ClubConfig.defaultConfig);

  int challengeCalls = 0;
  Object? challengeError;
  String? assertionSent;
  Object? grantError;

  @override
  Future<String> restoreChallenge() async {
    challengeCalls++;
    if (challengeError != null) throw challengeError!;
    return _challenge;
  }

  @override
  Future<AuthTokens> loginRestoreCredential(String assertionJson) async {
    assertionSent = assertionJson;
    if (grantError != null) throw grantError!;
    return AuthTokens(
      accessToken: 'a',
      tokenType: 'Bearer',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}

class _FakeApi extends ClubApiClient {
  _FakeApi(super.session);

  int optionsCalls = 0;
  String? registered;
  Object? optionsError;

  @override
  Future<String> restoreOptions() async {
    optionsCalls++;
    if (optionsError != null) throw optionsError!;
    return _options;
  }

  @override
  Future<void> restoreRegister(String responseJson) async => registered = responseJson;
}

class _FakeChannel extends RestoreCredentialsChannel {
  _FakeChannel();

  String? assertionToReturn;
  String? createResult = '{"registration":"ok"}';
  Object? createError;
  Object? getError;
  int createCalls = 0;
  int clearCalls = 0;
  final allowCloudSeen = <bool>[];
  Duration? getDelay;

  @override
  Future<String?> create(String requestJson, {bool allowCloud = true}) async {
    createCalls++;
    allowCloudSeen.add(allowCloud);
    // Only the first attempt fails, so the E2EE retry can succeed.
    if (createError != null && createCalls == 1) throw createError!;
    return createResult;
  }

  @override
  Future<String?> get(String requestJson) async {
    if (getDelay != null) await Future<void>.delayed(getDelay!);
    if (getError != null) throw getError!;
    return assertionToReturn;
  }

  @override
  Future<void> clear() async => clearCalls++;
}

({_FakeSession session, _FakeApi api, _FakeChannel channel, RestoreCredentialService svc}) _make({
  bool enabled = true,
}) {
  final session = _FakeSession();
  final api = _FakeApi(session);
  final channel = _FakeChannel();
  return (
    session: session,
    api: api,
    channel: channel,
    svc: RestoreCredentialService(
      session: session,
      api: api,
      channel: channel,
      enabled: enabled,
    ),
  );
}

void main() {
  // Required before touching the mock binary messenger in the channel group below.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tryRestore', () {
    test('clean install: platform reports no credential, so no grant is attempted', () async {
      final f = _make();
      f.channel.assertionToReturn = null;

      expect(await f.svc.tryRestore(), isFalse);
      expect(f.session.challengeCalls, 1);
      expect(f.session.assertionSent, isNull, reason: 'nothing to assert with');
    });

    test('migrated device: the assertion is exchanged for a session', () async {
      final f = _make();
      f.channel.assertionToReturn = _assertion;

      expect(await f.svc.tryRestore(), isTrue);
      expect(f.session.assertionSent, _assertion,
          reason: 'the platform JSON must reach the grant untouched');
    });

    test('restore_credential_unknown is an ordinary signed-out start, not an error', () async {
      final f = _make();
      f.channel.assertionToReturn = _assertion;
      f.session.grantError = ClubError(code: 'restore_credential_unknown', message: 'nope');

      expect(await f.svc.tryRestore(), isFalse);
    });

    test('a failing challenge call degrades to signed-out instead of throwing', () async {
      final f = _make();
      f.session.challengeError = ClubError(code: 'server_error', message: 'boom');

      expect(await f.svc.tryRestore(), isFalse);
    });

    test('a platform failure degrades to signed-out instead of throwing', () async {
      final f = _make();
      f.channel.getError = const RestoreCredentialsException('get_failed');

      expect(await f.svc.tryRestore(), isFalse);
    });

    test('disabled off-Android: no network call at all', () async {
      final f = _make(enabled: false);
      f.channel.assertionToReturn = _assertion;

      expect(await f.svc.tryRestore(), isFalse);
      expect(f.session.challengeCalls, 0, reason: 'must not cost a round trip on Windows/iOS');
    });

    test('a hung platform call cannot strand the launch spinner', () async {
      final f = _make();
      f.channel.assertionToReturn = _assertion;
      f.channel.getDelay = RestoreCredentialService.attemptTimeout * 2;

      expect(
        await f.svc.tryRestore().timeout(RestoreCredentialService.attemptTimeout * 1.5),
        isFalse,
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('register', () {
    test('registers the platform response against the account', () async {
      final f = _make();

      await f.svc.register();
      expect(f.api.optionsCalls, 1);
      expect(f.channel.allowCloudSeen, [true]);
      expect(f.api.registered, '{"registration":"ok"}');
    });

    test('E2eeUnavailable retries local-only with a FRESH challenge', () async {
      final f = _make();
      f.channel.createError = const RestoreCredentialsException('e2ee_unavailable');

      await f.svc.register();
      expect(f.channel.allowCloudSeen, [true, false], reason: 'second attempt drops cloud backup');
      expect(f.api.optionsCalls, 2,
          reason: 'the first challenge was consumed; reusing it would fail single-use');
      expect(f.api.registered, isNotNull);
    });

    test('other create failures are swallowed — sign-in is never affected', () async {
      final f = _make();
      f.channel.createError = const RestoreCredentialsException('create_failed');
      f.channel.createResult = null;

      await f.svc.register();
      expect(f.api.registered, isNull);
    });

    test('a failing options call is swallowed', () async {
      final f = _make();
      f.api.optionsError = ClubError(code: 'server_error', message: 'boom');

      await f.svc.register();
      expect(f.channel.createCalls, 0);
    });

    test('disabled off-Android: nothing happens', () async {
      final f = _make(enabled: false);

      await f.svc.register();
      expect(f.api.optionsCalls, 0);
    });
  });

  group('clear', () {
    test('drops the credential when enabled', () async {
      final f = _make();
      await f.svc.clear();
      expect(f.channel.clearCalls, 1);
    });

    test('no-ops off-Android', () async {
      final f = _make(enabled: false);
      await f.svc.clear();
      expect(f.channel.clearCalls, 0);
    });
  });

  group('channel wrapper', () {
    const channel = MethodChannel('club.makapix.app/restore_credentials');
    // Safe at group-declaration time only because main() calls ensureInitialized() first.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('get returns null when the platform has no credential', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await const RestoreCredentialsChannel().get('{}'), isNull);
    });

    test('create passes requestJson and allowCloud through', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return 'resp';
      });

      final out = await const RestoreCredentialsChannel().create('REQ', allowCloud: false);
      expect(out, 'resp');
      expect(seen!.method, 'create');
      expect((seen!.arguments as Map)['requestJson'], 'REQ');
      expect((seen!.arguments as Map)['allowCloud'], isFalse);
    });

    test('a PlatformException becomes a typed exception, e2ee flagged', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'e2ee_unavailable'),
      );

      await expectLater(
        const RestoreCredentialsChannel().create('{}'),
        throwsA(isA<RestoreCredentialsException>()
            .having((e) => e.isE2eeUnavailable, 'isE2eeUnavailable', isTrue)),
      );
    });

    test('clear never throws — it runs during sign-out', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'clear_failed'),
      );
      await expectLater(const RestoreCredentialsChannel().clear(), completes);
    });

    test('off-Android the channel is absent and every call is a quiet no-op', () async {
      // No mock handler registered -> MissingPluginException, which the wrapper maps to
      // "nothing to do" so callers need no platform checks.
      expect(await const RestoreCredentialsChannel().get('{}'), isNull);
      expect(await const RestoreCredentialsChannel().create('{}'), isNull);
      await expectLater(const RestoreCredentialsChannel().clear(), completes);
    });
  });
}
