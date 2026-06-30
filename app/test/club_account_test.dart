import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/auth/account_validators.dart';
import 'package:makapix_club/club/api/auth_api.dart';
import 'package:makapix_club/club/config/club_config.dart';
import 'package:makapix_club/club/models/account.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/state/api_providers.dart';
import 'package:makapix_club/club/state/registration_controller.dart';

/// A scriptable [AuthApi] that never touches the network — only the lifecycle
/// methods the [RegistrationController] uses are overridden.
class _FakeAuthApi extends AuthApi {
  _FakeAuthApi() : super(const ClubConfig(ClubEnvironment.dev));

  ClubError? registerError;
  ClubError? verifyError;
  VerifyEmailResult verifyResult =
      const VerifyEmailResult(verified: true, handle: 'makapix-user-1', needsWelcome: true);

  bool registered = false;
  int otpRequests = 0;

  @override
  Future<RegisterResult> register(String email) async {
    if (registerError != null) throw registerError!;
    registered = true;
    return RegisterResult(userId: 1, email: email, handle: 'makapix-user-1');
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

void main() {
  group('account validators', () {
    test('password rules mirror the server (>=8, letter, digit)', () {
      expect(validatePasswordError('short1'), isNotNull);
      expect(validatePasswordError('12345678'), isNotNull); // no letter
      expect(validatePasswordError('abcdefgh'), isNotNull); // no digit
      expect(validatePasswordError('abcd1234'), isNull);
      expect(validatePasswordError('Sup3rPass'), isNull);
    });

    test('handle rules: length, charset, edges', () {
      expect(validateHandleError('ab'), isNotNull); // too short
      expect(validateHandleError('a' * 33), isNotNull); // too long
      expect(validateHandleError('has space'), isNotNull);
      expect(validateHandleError('has.dot'), isNotNull);
      expect(validateHandleError('-lead'), isNotNull);
      expect(validateHandleError('trail_'), isNotNull);
      expect(validateHandleError('pixel_artist-7'), isNull);
      expect(validateHandleError('abc'), isNull);
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
      final r = RegisterResult.fromJson({'user_id': 7, 'email': 'a@b.co', 'handle': 'makapix-user-7'});
      expect(r.userId, 7);
      expect(r.handle, 'makapix-user-7');

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
    test('email step → register + request code → code step', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitEmail('New@Example.com ');

      final st = c.read(registrationControllerProvider);
      expect(fake.registered, isTrue);
      expect(fake.otpRequests, 1);
      expect(st.step, RegStep.code);
      expect(st.email, 'new@example.com'); // trimmed + lowercased
      expect(st.error, isNull);
    });

    test('invalid email is rejected before any call', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitEmail('not-an-email');

      expect(fake.registered, isFalse);
      expect(c.read(registrationControllerProvider).step, RegStep.email);
      expect(c.read(registrationControllerProvider).error, isNotNull);
    });

    test('pending_verification jumps straight to the code step', () async {
      final fake = _FakeAuthApi()
        ..registerError = ClubError(status: 409, code: 'error', message: 'pending_verification');
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      await ctrl.submitEmail('a@b.co');

      final st = c.read(registrationControllerProvider);
      expect(st.step, RegStep.code);
      expect(fake.otpRequests, 1);
      expect(st.error, isNull);
    });

    test('already-exists stays on email and signals the caller', () async {
      final fake = _FakeAuthApi()
        ..registerError = ClubError(
            status: 409, code: 'error', message: 'An account with this email already exists');
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);

      var signalled = false;
      await ctrl.submitEmail('a@b.co', onAlreadyExists: () => signalled = true);

      final st = c.read(registrationControllerProvider);
      expect(st.step, RegStep.email);
      expect(st.error, isNotNull);
      expect(signalled, isTrue);
      expect(fake.otpRequests, 0);
    });

    test('verify a 6-digit code advances to the sign-in step', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitEmail('a@b.co');

      await ctrl.submitCode('123456');
      expect(c.read(registrationControllerProvider).step, RegStep.signIn);
    });

    test('a malformed code is rejected without a call', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitEmail('a@b.co');

      await ctrl.submitCode('12'); // too short
      expect(c.read(registrationControllerProvider).step, RegStep.code);
      expect(c.read(registrationControllerProvider).error, isNotNull);
    });

    test('resendCode requests another OTP', () async {
      final fake = _FakeAuthApi();
      final c = _container(fake);
      final ctrl = c.read(registrationControllerProvider.notifier);
      await ctrl.submitEmail('a@b.co');
      expect(fake.otpRequests, 1);

      await ctrl.resendCode();
      expect(fake.otpRequests, 2);
      expect(c.read(registrationControllerProvider).notice, 'New code sent.');
    });
  });
}
