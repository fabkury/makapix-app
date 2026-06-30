import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/auth_controller.dart';
import '../../state/registration_controller.dart';
import 'auth_shared.dart';
import 'forgot_password_page.dart';

/// The in-app "create account" flow, hosted in **one** route so a successful
/// sign-in pops cleanly back to the Club root (where the `needs_welcome` gate
/// then shows the onboarding wizard). Steps: email → 6-digit code → first
/// sign-in with the emailed temporary password.
class CreateAccountPage extends ConsumerStatefulWidget {
  const CreateAccountPage({super.key});
  @override
  ConsumerState<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends ConsumerState<CreateAccountPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _temp = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _temp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Either path to a session (email+temp-password OR "Sign up with GitHub")
    // flips the global auth state — when it does, leave the flow.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.isSignedIn && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });

    final reg = ref.watch(registrationControllerProvider);
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final githubBusy = ref.watch(authControllerProvider).isBusy;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: AuthFormShell(
        children: switch (reg.step) {
          RegStep.email => _emailStep(reg, ctrl, githubBusy),
          RegStep.code => _codeStep(reg, ctrl),
          RegStep.signIn => _signInStep(reg, ctrl),
          RegStep.done => const [Center(child: CircularProgressIndicator())],
        },
      ),
    );
  }

  List<Widget> _header(String title, String subtitle) => [
        Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
      ];

  Widget _spinnerOr(String label, bool busy) => busy
      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(label);

  // ---- step 1: email ----
  List<Widget> _emailStep(RegistrationState reg, RegistrationController ctrl, bool githubBusy) {
    final busy = reg.busy || githubBusy;
    final banner = authBanner(error: reg.error, notice: reg.notice);
    return [
      ..._header('Create your account',
          'Sign up with your email — we\'ll send a 6-digit code to verify it.'),
      ?banner,
      TextField(
        controller: _email,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        onSubmitted: (_) => busy ? null : ctrl.submitEmail(_email.text),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : () => ctrl.submitEmail(_email.text),
        child: _spinnerOr('Create account', reg.busy),
      ),
      const SizedBox(height: 12),
      const Row(children: [
        Expanded(child: Divider()),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('or', style: TextStyle(color: Colors.white38))),
        Expanded(child: Divider()),
      ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).loginGithub(),
        icon: const Icon(Icons.code),
        label: const Text('Sign up with GitHub'),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Already have an account? Sign in'),
      ),
    ];
  }

  // ---- step 2: verification code ----
  List<Widget> _codeStep(RegistrationState reg, RegistrationController ctrl) {
    final banner = authBanner(error: reg.error, notice: reg.notice);
    return [
      ..._header('Verify your email',
          'Enter the 6-digit code we emailed to ${reg.email}. You\'ll also receive a '
              'temporary password — keep that email for the next step.'),
      ?banner,
      TextField(
        controller: _code,
        enabled: !reg.busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
            labelText: '6-digit code', border: OutlineInputBorder(), counterText: ''),
        onSubmitted: (_) => reg.busy ? null : ctrl.submitCode(_code.text),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: reg.busy ? null : () => ctrl.submitCode(_code.text),
        child: _spinnerOr('Verify', reg.busy),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton(onPressed: reg.busy ? null : ctrl.resendCode, child: const Text('Resend code')),
        TextButton(onPressed: reg.busy ? null : ctrl.editEmail, child: const Text('Change email')),
      ]),
    ];
  }

  // ---- step 3: first sign-in with the emailed temporary password ----
  List<Widget> _signInStep(RegistrationState reg, RegistrationController ctrl) {
    final banner = authBanner(error: reg.error, notice: reg.notice);
    return [
      ..._header('Almost there',
          'Enter the temporary password from your email to finish. You can choose your own '
              'password in the next step.'),
      ?banner,
      TextField(
        controller: _temp,
        enabled: !reg.busy,
        obscureText: true,
        decoration:
            const InputDecoration(labelText: 'Temporary password', border: OutlineInputBorder()),
        onSubmitted: (_) => reg.busy ? null : ctrl.firstSignIn(_temp.text),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: reg.busy ? null : () => ctrl.firstSignIn(_temp.text),
        child: _spinnerOr('Finish & sign in', reg.busy),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: reg.busy
            ? null
            : () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
        child: const Text('Lost the temporary password? Reset it'),
      ),
    ];
  }
}
