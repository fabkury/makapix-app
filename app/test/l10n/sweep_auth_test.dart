// T4 sweeps: sign-in, account creation, password reset, email verification, onboarding,
// account management, and the signed-out landing pages (batch C2).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/state/account_providers.dart';
import 'package:makapix_club/club/state/auth_controller.dart';
import 'package:makapix_club/club/state/password_reset_controller.dart';
import 'package:makapix_club/club/state/registration_controller.dart';
import 'package:makapix_club/club/state/verify_email_controller.dart';
import 'package:makapix_club/club/ui/auth/account_management_page.dart';
import 'package:makapix_club/club/ui/auth/create_account_page.dart';
import 'package:makapix_club/club/ui/auth/delete_account_page.dart';
import 'package:makapix_club/club/ui/auth/forgot_password_page.dart';
import 'package:makapix_club/club/ui/auth/onboarding_wizard.dart';
import 'package:makapix_club/club/ui/auth/verify_email_page.dart';
import 'package:makapix_club/club/ui/club_account_page.dart';
import 'package:makapix_club/club/ui/club_resolving_page.dart';
import 'package:makapix_club/club/ui/club_welcome_page.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'club_fixtures.dart';
import 'sweep.dart';

/// Controllers pinned to one step of their flow, with the notice that step shows — the same
/// messages the real controller produces, read in the language under test.
class _Registration extends RegistrationController {
  _Registration(super.ref, RegistrationState s) {
    state = s;
  }
}

class _Reset extends PasswordResetController {
  _Reset(super.ref, PasswordResetState s) {
    state = s;
  }
}

class _Verify extends VerifyEmailController {
  _Verify(super.ref, VerifyEmailState s) {
    state = s;
  }
}

Override _registration(RegistrationState Function() s) =>
    registrationControllerProvider.overrideWith((ref) => _Registration(ref, s()));

Override _reset(PasswordResetState Function() s) =>
    passwordResetControllerProvider.overrideWith((ref) => _Reset(ref, s()));

const _email = 'ada@example.com';

FakeBackend _accountBackend() => fixtureBackend()
  ..on('GET', r'/auth/providers', (_) => {
        'identities': [
          {'id': 'i1', 'provider': 'password', 'email': _email},
          {
            'id': 'i2',
            'provider': 'github',
            'provider_metadata': {'username': 'pixel_ada'},
          },
        ],
      })
  ..on('GET', r'/feed/promoted', (_) => {'items': const []});

void main() {
  sweepScreen(
    'Sign-in form',
    build: () => const ClubAccountPage(),
    overrides: (b) => clubOverrides(signedIn: false),
  );

  sweepScreen(
    'Sign-in form, failed sign-in with an unverified email',
    build: () => const ClubAccountPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      authControllerProvider.overrideWith((ref) =>
          FakeAuth(AuthState.failure(appL10n.commonUnexpectedError, code: 'email_not_verified'))),
    ],
  );

  sweepScreen(
    'Account page, signed in',
    build: () => const ClubAccountPage(),
    overrides: (b) => clubOverrides(
        me: fixtureMe(
      roles: const ['moderator', 'owner'],
      quotas: const {
        'storage': {'used_bytes': 5452595, 'limit_bytes': 104857600},
        'uploads': {'remaining': 7, 'limit': 10},
      },
    )),
  );

  sweepScreen(
    'Create account, details',
    build: () => const CreateAccountPage(),
    overrides: (b) => clubOverrides(signedIn: false),
  );

  sweepScreen(
    'Create account, an account already exists',
    build: () => const CreateAccountPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _registration(() => RegistrationState(error: appL10n.authEmailExists)),
    ],
  );

  sweepScreen(
    'Create account, code',
    build: () => const CreateAccountPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _registration(() => RegistrationState(
          step: RegStep.code, email: _email, notice: appL10n.authCodeSent(_email))),
    ],
  );

  sweepScreen(
    'Create account, temporary password',
    build: () => const CreateAccountPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _registration(() => RegistrationState(
          step: RegStep.signIn, email: _email, notice: appL10n.authVerifiedEnterTemp)),
    ],
  );

  sweepScreen(
    'Reset password, request',
    build: () => const ForgotPasswordPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _reset(() => PasswordResetState(error: appL10n.authTooManyRequests)),
    ],
  );

  sweepScreen(
    'Reset password, code and new password',
    build: () => const ForgotPasswordPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _reset(() => PasswordResetState(
          step: ResetStep.confirm, email: _email, notice: appL10n.resetCodeSentNotice)),
    ],
  );

  sweepScreen(
    'Reset password, done',
    build: () => const ForgotPasswordPage(),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      _reset(() => const PasswordResetState(step: ResetStep.done, email: _email)),
    ],
  );

  sweepScreen(
    'Verify email',
    build: () => const VerifyEmailPage(email: _email),
    overrides: (b) => [
      ...clubOverrides(signedIn: false),
      verifyEmailControllerProvider
          .overrideWith((ref) => _Verify(ref, VerifyEmailState(error: appL10n.authInvalidCode))),
    ],
  );

  sweepScreen(
    'Account management',
    build: () => const AccountManagementPage(),
    backend: _accountBackend,
    overrides: (b) => clubOverrides(backend: b),
  );

  sweepScreen(
    'Account management, bottom (linked logins, danger zone)',
    build: () => const AccountManagementPage(),
    backend: _accountBackend,
    overrides: (b) => clubOverrides(backend: b),
    act: (tester) async {
      await tester.drag(find.byType(ListView), const Offset(0, -900));
    },
  );

  sweepScreen(
    'Delete account',
    build: () => const DeleteAccountPage(),
    overrides: (b) => clubOverrides(),
  );

  sweepScreen(
    'Onboarding, handle step',
    build: () => const OnboardingWizard(),
    overrides: (b) => clubOverrides(),
  );

  sweepScreen(
    'Onboarding, set-password step',
    build: () => const OnboardingWizard(),
    overrides: (b) => [
      ...clubOverrides(),
      pendingWelcomePasswordProvider.overrideWith((ref) => 'temp-1234'),
    ],
  );

  sweepScreen(
    'Onboarding, profile step',
    build: () => const OnboardingWizard(),
    overrides: (b) => clubOverrides(),
    // The handle is unchanged, so Continue advances without a request.
    act: (tester) => tester.tap(find.byType(FilledButton)),
  );

  sweepScreen(
    'Welcome page',
    build: () => const ClubWelcomePage(),
    backend: _accountBackend,
    overrides: (b) => clubOverrides(signedIn: false, backend: b),
  );

  sweepScreen(
    'Resolving page',
    build: () => const ClubResolvingPage(),
    overrides: (b) => clubOverrides(signedIn: false),
    // A spinner: nothing to settle, and the page is the same at every size but one.
  );
}
