import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../../state/auth_controller.dart';
import '../../state/registration_controller.dart';
import 'auth_shared.dart';
import 'forgot_password_page.dart';

/// The in-app "create account" flow, hosted in **one** route so a successful
/// sign-in pops cleanly back to the Club root (where the `needs_welcome` gate
/// then shows the onboarding wizard). Steps: email + chosen password → 6-digit
/// code → (legacy only) temp-password sign-in. On the A2 path the chosen password
/// is set at registration, so verifying the code signs the user straight in.
class CreateAccountPage extends ConsumerStatefulWidget {
  const CreateAccountPage({super.key});
  @override
  ConsumerState<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends ConsumerState<CreateAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _temp = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _temp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Either path to a session (email+password OR "Sign up with GitHub") flips the
    // global auth state — when it does, leave the flow.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.isSignedIn && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });

    final reg = ref.watch(registrationControllerProvider);
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final githubBusy = ref.watch(authControllerProvider).isBusy;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.authCreateAccount)),
      body: AuthFormShell(
        children: switch (reg.step) {
          RegStep.details => _detailsStep(reg, ctrl, githubBusy),
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

  // ---- step 1: email + chosen password ----
  List<Widget> _detailsStep(RegistrationState reg, RegistrationController ctrl, bool githubBusy) {
    final busy = reg.busy || githubBusy;
    final banner = authBanner(error: reg.error, notice: reg.notice);
    void submit() => ctrl.submitDetails(_email.text, _password.text);
    final l10n = context.l10n;
    return [
      ..._header(l10n.createAccountHeading, l10n.createAccountIntro),
      ?banner,
      TextField(
        controller: _email,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(labelText: l10n.authEmail, border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        enabled: !busy,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: l10n.authPassword,
          border: const OutlineInputBorder(),
          helperText: l10n.authPasswordHelper,
          helperMaxLines: 2,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (_) => busy ? null : submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : submit,
        child: _spinnerOr(l10n.authCreateAccount, reg.busy),
      ),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(child: Divider()),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(l10n.authOr, style: const TextStyle(color: Colors.white38))),
        const Expanded(child: Divider()),
      ]),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : () => ref.read(authControllerProvider.notifier).loginGithub(),
        icon: const Icon(Icons.code),
        label: Text(l10n.createAccountGithub),
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(l10n.createAccountHaveAccount),
      ),
    ];
  }

  // ---- step 2: verification code ----
  List<Widget> _codeStep(RegistrationState reg, RegistrationController ctrl) {
    final banner = authBanner(error: reg.error, notice: reg.notice);
    final l10n = context.l10n;
    return [
      ..._header(l10n.authVerifyEmailTitle, l10n.authVerifyEmailBody(reg.email)),
      ?banner,
      TextField(
        controller: _code,
        enabled: !reg.busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(
            labelText: l10n.authCode6, border: const OutlineInputBorder(), counterText: ''),
        onSubmitted: (_) => reg.busy ? null : ctrl.submitCode(_code.text),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: reg.busy ? null : () => ctrl.submitCode(_code.text),
        child: _spinnerOr(l10n.authVerify, reg.busy),
      ),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.spaceBetween, children: [
        TextButton(onPressed: reg.busy ? null : ctrl.resendCode, child: Text(l10n.authResendCode)),
        TextButton(
            onPressed: reg.busy ? null : ctrl.editEmail, child: Text(l10n.createAccountChangeEmail)),
      ]),
    ];
  }

  // ---- step 3 (legacy/non-A2 only): sign in with the emailed temp password ----
  List<Widget> _signInStep(RegistrationState reg, RegistrationController ctrl) {
    final banner = authBanner(error: reg.error, notice: reg.notice);
    final l10n = context.l10n;
    return [
      ..._header(l10n.createAccountAlmostThere, l10n.createAccountTempIntro),
      ?banner,
      TextField(
        controller: _temp,
        enabled: !reg.busy,
        obscureText: true,
        decoration: InputDecoration(
            labelText: l10n.createAccountTempPassword, border: const OutlineInputBorder()),
        onSubmitted: (_) => reg.busy ? null : ctrl.firstSignIn(_temp.text),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: reg.busy ? null : () => ctrl.firstSignIn(_temp.text),
        child: _spinnerOr(l10n.createAccountFinish, reg.busy),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: reg.busy
            ? null
            : () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
        child: Text(l10n.createAccountLostTemp),
      ),
    ];
  }
}
