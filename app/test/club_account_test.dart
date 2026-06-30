import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/auth/account_validators.dart';
import 'package:makapix_club/club/api/auth_api.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/account.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/state/api_providers.dart';
import 'package:makapix_club/club/state/registration_controller.dart';
import 'package:makapix_club/club/state/verify_email_controller.dart';

/// A scriptable [AuthApi] that never touches the network — only the lifecycle
/// methods the [RegistrationController] uses are overridden.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi() : super(const ClubConfig(ClubEnvironment.dev));

  ClubError? registerError;
  ClubError? verifyError;
  VerifyEmailResult verifyResult =
      const VerifyEmailResult(verified: true, handle: 'makapix-user-1', needsWelcome: true);

  /// The verification_method register returns: "otp" (A2) or "link" (legacy).
  String method = 'otp';

  bool registered = false;
  String? registeredPassword;
  int otpRequests = 0;

  @override
  Future<RegisterResult> register(String email, {String? password}) async {
    if (registerError != null) throw registerError!;
    registered = true;
    registeredPassword = password;
    return RegisterResult(
        userId: 1, email: email, handle: 'makapix-user-1', verificationMethod: method);
  }

  @override
  Future<void> requestEmailOtp(String email) async => otpRequests++;

  @override
  Future<VerifyEmailResult> verifyEmailOtp(String email, String code) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }
}

/// Build a container wired to [fake]; keeps the autoDispose controller alive.
ProviderContainer _container(_FakeAuthApi fake) {
  final c = ProviderContainer(overrides: [authApiProvider.overrideWithValue(fake)]);
  c.listen(registrationControllerProvider, (_, _) {});
  addTearDown(c.dispose);
  return c;
}

ProviderContainer _verifyContainer(_FakeAuthApi fake) {
  final c = ProviderContainer(overrides: [authApiProvider.overrideWithValue(fake)]);
  c.listen(verifyEmailControllerProvider, (_, _) {});
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('account validators', () {
    test('password rules mirror the server (>=8, letter, digit)', () {
      expect(validatePasswordError('short1'), isNotNull);
      expect(validatePasswordError('12345678'), isNotNull); // no letter
      expect(validatePasswordError('abcdefgh'), isNotNull); // no digit
      expect(validatePasswordError('abcd1234'), isNull);
      expect(validatePasswordError('Sup3rPass'), isNull);
    });

    test('handle rules mirror the server: 3–32, letters/digits/marks/-/_, no edge symbol', () {
      // Empty / whitespace-only / length bounds (3–32 code points after stripping).
      expect(validateHandleError(''), isNotNull);
      expect(validateHandleError('   '), isNotNull);
      expect(validateHandleError('ab'), isNotNull); // < 3
      expect(validateHandleError('a' * 33), isNotNull); // > 32
      // Valid: ASCII with inner -/_, and letters of any script.
      expect(validateHandleError('pixel'), isNull);
      expect(validateHandleError('pixel_artist-7'), isNull);
      expect(validateHandleError('  pixel  '), isNull); // surrounding whitespace stripped
      expect(validateHandleError('Пиксель'), isNull); // Cyrillic letters
      expect(validateHandleError('ピクセル'), isNull); // Japanese (Lo)
      expect(validateHandleError('café'), isNull); // accented letter / combining mark
      // Rejected: whitespace within, punctuation, symbols, emoji, control chars.
      expect(validateHandleError('has space'), isNotNull);
      expect(validateHandleError('has.dot'), isNotNull);
      expect(validateHandleError('emoji😀here'), isNotNull);
      expect(validateHandleError('😀' * 5), isNotNull);
      expect(validateHandleError('bad\u{7}name'), isNotNull); // U+0007 bell
      // No leading/trailing hyphen or underscore.
      expect(validateHandleError('-lead'), isNotNull);
      expect(validateHandleError('trail_'), isNotNull);
      // Must contain at least one letter or digit (here: only combining acute marks).
      expect(validateHandleError('\u{301}\u{301}\u{301}'), isNotNull);
    });

    test('email shape', () {
      expect(isValidEmail('a@b.co'), isTrue);
      expect(isValidEmail('a@b'), isFalse);
      expect(isValidEmail('no-at.example.com'), isFalse);
      expect(isValidEmail('  spaced@x.com  '), isTrue); // trimmed
    });
  });

  group('ClubError branching for the account flow', () {
    test('register 409 pending_verification (FastAPI detail envelope)', () {
      final e = ClubError.fromBody(409, {'detail': 'pending_verification'});
      expect(e.status, 409);
      expect(e.message.toLowerCase(), contains('pending_verification'));
    });

    test('register 409 already-exists', () {
      final e = ClubError.fromBody(409, {'detail': 'An account with this email already exists'});
      expect(e.status, 409);
      expect(e.message, contains('already exists'));
    });

    test('OTP error uses the stable-code envelope', () {
      final e = ClubError.fromBody(
          400, {'error': {'code': 'token_invalid', 'message': 'Invalid or expired code.'}});
      expect(e.code, 'token_invalid');
      expect(e.status, 400);
    });
  });

  group('account models parse', () {
    test('RegisterResult / VerifyEmailResult / HandleAvailability', () {
      final r = RegisterResult.fromJson(
          {'user_id': 7, 'email': 'a@b.co', 'handle': 'makapix-user-7', 'verification_method': 'otp'});
      expect(r.userId, 7);
      expect(r.handle, 'makapix-user-7');
      expect(r.isOtp, isTrue);
      // Defaults to the legacy "link" path when the server omits the field.
      expect(RegisterResult.fromJson({'user_id': 1}).verificationMethod, 'link');

      final v = VerifyEmailResult.fromJson(
          {'verified': true, 'handle': 'pixel', 'needs_welcome': true, 'public_sqid': 'k5fNx'});
      expect(v.verified, isTrue);
      expect(v.needsWelcome, isTrue);
      expect(v.publicSqid, 'k5fNx');

      final h = HandleAvailability.fromJson(
          {'handle': 'pixel', 'available': false, 'message': 'This handle is already taken'});
      expect(h.available, isFalse);
    });

    test('AuthIdentity label reflects provider + github username', () {
      final pw = AuthIdentity.fromJson(
          {'id': 'i1', 'provider': 'password', 'email': 'a@b.co', 'created_at': '2026-01-01T00:00:00Z'});
      expect(pw.isPassword, isTrue);
      expect(pw.label, 'Email & password');

      final gh = AuthIdentity.fromJson({
        'id': 'i2',
        'provider': 'github',
        'provider_metadata': {'username': 'octocat'},
      });
      expect(gh.isGithub, isTrue);
      expect(gh.label, 'GitHub (octocat)');
    });
  });

  group('RegistrationController', () {
    test('A2: chosen password → OTP path, no separate email-otp/request', () async {
      final fake = _FakeAuthApi(); // method defaults to "otp"
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitDetails('New@Example.com ', 'abcd1234');

      final st = c.read(registrationControllerProvider);
      expect(fake.registered, isTrue);
      expect(fake.registeredPassword, 'abcd1234'); // chosen password sent
      expect(fake.otpRequests, 0); // A2 server already emailed the code
      expect(st.step, RegStep.code);
      expect(st.email, 'new@example.com'); // trimmed + lowercased
      expect(ctrl.isLegacy, isFalse);
      expect(st.error, isNull);
    });

    test('legacy server (verification_method: "link") falls back to requesting an OTP', () async {
      final fake = _FakeAuthApi()..method = 'link';
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitDetails('a@b.co', 'abcd1234');

      final st = c.read(registrationControllerProvider);
      expect(st.step, RegStep.code);
      expect(fake.otpRequests, 1);
      expect(ctrl.isLegacy, isTrue);
    });

    test('invalid email is rejected before any call', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitDetails('not-an-email', 'abcd1234');

      expect(fake.registered, isFalse);
      expect(c.read(registrationControllerProvider).step, RegStep.details);
      expect(c.read(registrationControllerProvider).error, isNotNull);
    });

    test('weak password is rejected before any call', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitDetails('a@b.co', 'short'); // < 8, no digit

      expect(fake.registered, isFalse);
      expect(c.read(registrationControllerProvider).step, RegStep.details);
      expect(c.read(registrationControllerProvider).error, isNotNull);
    });

    test('pending_verification (non-A2 server) falls back to the code step', () async {
      final fake = _FakeAuthApi()
        ..registerError = ClubError(status: 409, code: 'error', message: 'pending_verification');
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitDetails('a@b.co', 'abcd1234');

      final st = c.read(registrationControllerProvider);
      expect(st.step, RegStep.code);
      expect(fake.otpRequests, 1);
      expect(ctrl.isLegacy, isTrue);
      expect(st.error, isNull);
    });

    test('already-exists stays on details and signals the caller', () async {
      final fake = _FakeAuthApi()
        ..registerError = ClubError(
            status: 409, code: 'error', message: 'An account with this email already exists');
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      var signalled = false;
      await ctrl.submitDetails('a@b.co', 'abcd1234', onAlreadyExists: () => signalled = true);

      final st = c.read(registrationControllerProvider);
      expect(st.step, RegStep.details);
      expect(st.error, isNotNull);
      expect(signalled, isTrue);
      expect(fake.otpRequests, 0);
    });

    test('legacy: verifying the code advances to the temp-password sign-in step', () async {
      final fake = _FakeAuthApi()..method = 'link';
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitDetails('a@b.co', 'abcd1234');

      await ctrl.submitCode('123456');
      expect(c.read(registrationControllerProvider).step, RegStep.signIn);
    });

    test('a malformed code is rejected without a call', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitDetails('a@b.co', 'abcd1234');

      await ctrl.submitCode('12'); // too short
      expect(c.read(registrationControllerProvider).step, RegStep.code);
      expect(c.read(registrationControllerProvider).error, isNotNull);
    });

    test('resendCode requests another OTP', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitDetails('a@b.co', 'abcd1234'); // otp path → 0 requests so far
      expect(fake.otpRequests, 0);

      await ctrl.resendCode();
      expect(fake.otpRequests, 1);
      expect(c.read(registrationControllerProvider).notice, 'New code sent.');
    });
  });

  group('VerifyEmailController (sign-in recovery path)', () {
    test('verifying without a stored password marks the email verified', () async {
      final fake = _FakeAuthApi();
      final c = _verifyContainer(fake);
      final ctrl = c.read(verifyEmailControllerProvider.notifier);

      await ctrl.submitCode('a@b.co', '123456'); // no password → no sign-in

      final st = c.read(verifyEmailControllerProvider);
      expect(st.verified, isTrue);
      expect(st.error, isNull);
    });

    test('a malformed code is rejected without a call', () async {
      final fake = _FakeAuthApi();
      final c = _verifyContainer(fake);
      final ctrl = c.read(verifyEmailControllerProvider.notifier);

      await ctrl.submitCode('a@b.co', '12');

      expect(c.read(verifyEmailControllerProvider).verified, isFalse);
      expect(c.read(verifyEmailControllerProvider).error, isNotNull);
    });

    test('resend requests a fresh code', () async {
      final fake = _FakeAuthApi();
      final c = _verifyContainer(fake);

      await c.read(verifyEmailControllerProvider.notifier).resend('a@b.co');

      expect(fake.otpRequests, 1);
      expect(c.read(verifyEmailControllerProvider).notice, 'New code sent.');
    });
  });
}
