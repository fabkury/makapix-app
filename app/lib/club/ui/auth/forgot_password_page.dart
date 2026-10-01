import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../../state/password_reset_controller.dart';
import 'auth_shared.dart';

/// OTP-based password reset, reached from the sign-in screen. Steps: enter email
/// → enter the 6-digit code + a new password → back to sign-in.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(passwordResetControllerProvider);
    final ctrl = ref.read(passwordResetControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.resetTitle)),
      body: AuthFormShell(
        children: switch (st.step) {
          ResetStep.request => _requestStep(st, ctrl),
          ResetStep.confirm => _confirmStep(st, ctrl),
          ResetStep.done => _doneStep(st),
        },
      ),
    );
  }

  Widget _spinnerOr(String label, bool busy) => busy
      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(label);

  List<Widget> _requestStep(PasswordResetState st, PasswordResetController ctrl) {
    final banner = authBanner(error: st.error, notice: st.notice);
    final l10n = context.l10n;
    return [
      Text(l10n.resetHeading,
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(l10n.resetIntro,
          style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ?banner,
      TextField(
        controller: _email,
        enabled: !st.busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(labelText: l10n.authEmail, border: const OutlineInputBorder()),
        onSubmitted: (_) => st.busy ? null : ctrl.requestCode(_email.text),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: st.busy ? null : () => ctrl.requestCode(_email.text),
        child: _spinnerOr(l10n.resetSendCode, st.busy),
      ),
    ];
  }

  List<Widget> _confirmStep(PasswordResetState st, PasswordResetController ctrl) {
    final banner = authBanner(error: st.error, notice: st.notice);
    final l10n = context.l10n;
    return [
      Text(l10n.resetEnterCodeHeading,
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(l10n.resetEnterCodeBody(st.email),
          style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ?banner,
      TextField(
        controller: _code,
        enabled: !st.busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: InputDecoration(
            labelText: l10n.authCode6, border: const OutlineInputBorder(), counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        enabled: !st.busy,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: l10n.authNewPassword,
          border: const OutlineInputBorder(),
          helperText: l10n.authPasswordHelper,
          helperMaxLines: 2,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: st.busy ? null : () => ctrl.confirm(_code.text, _password.text),
        child: _spinnerOr(l10n.resetSetPassword, st.busy),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: st.busy ? null : ctrl.resendCode, child: Text(l10n.authResendCode)),
    ];
  }

  List<Widget> _doneStep(PasswordResetState st) => [
        const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 48),
        const SizedBox(height: 12),
        Text(context.l10n.resetDoneHeading,
            style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(context.l10n.resetDoneBody,
            style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.authBackToSignIn),
        ),
      ];
}
