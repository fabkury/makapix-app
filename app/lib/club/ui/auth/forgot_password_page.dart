import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(title: const Text('Reset password')),
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
    return [
      Text('Forgot your password?',
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      const Text('Enter your email and we\'ll send a 6-digit reset code.',
          style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ?banner,
      TextField(
        controller: _email,
        enabled: !st.busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        onSubmitted: (_) => st.busy ? null : ctrl.requestCode(_email.text),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: st.busy ? null : () => ctrl.requestCode(_email.text),
        child: _spinnerOr('Send reset code', st.busy),
      ),
    ];
  }

  List<Widget> _confirmStep(PasswordResetState st, PasswordResetController ctrl) {
    final banner = authBanner(error: st.error, notice: st.notice);
    return [
      Text('Enter your code',
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text('We sent a 6-digit code to ${st.email}. Enter it with your new password.',
          style: const TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ?banner,
      TextField(
        controller: _code,
        enabled: !st.busy,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(
            labelText: '6-digit code', border: OutlineInputBorder(), counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        enabled: !st.busy,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'New password',
          border: const OutlineInputBorder(),
          helperText: 'At least 8 characters, with a letter and a number.',
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
        child: _spinnerOr('Set new password', st.busy),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: st.busy ? null : ctrl.resendCode, child: const Text('Resend code')),
    ];
  }

  List<Widget> _doneStep(PasswordResetState st) => [
        const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 48),
        const SizedBox(height: 12),
        Text('Password updated',
            style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        const Text('You can now sign in with your new password.',
            style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to sign in'),
        ),
      ];
}
