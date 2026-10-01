import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:makapix_club/l10n/l10n.dart';

import '../../state/auth_controller.dart';
import '../../state/verify_email_controller.dart';
import 'auth_shared.dart';

/// Standalone "verify your email" screen, reached from the sign-in form when a
/// login fails with `email_not_verified`. Lets the user enter the 6-digit code
/// they already have, or resend a fresh one. If a [password] is passed (the one
/// just typed on the sign-in form), a successful verify signs them straight in
/// and pops back to the Club root.
class VerifyEmailPage extends ConsumerStatefulWidget {
  final String email;
  final String? password;
  const VerifyEmailPage({super.key, required this.email, this.password});

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If the verify-then-sign-in path flips the global auth state, leave the flow.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.isSignedIn && mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });

    final st = ref.watch(verifyEmailControllerProvider);
    final ctrl = ref.read(verifyEmailControllerProvider.notifier);
    final banner = authBanner(error: st.error, notice: st.notice);
    // Verified but not signed in (no/!wrong password) → offer a way back to sign-in.
    final verifiedNoSession = st.verified && !ref.watch(authControllerProvider).isSignedIn;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.authVerifyEmailTitle)),
      body: AuthFormShell(
        children: [
          Text(l10n.authVerifyEmailTitle,
              style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(l10n.authVerifyEmailBody(widget.email),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ?banner,
          if (!verifiedNoSession) ...[
            TextField(
              controller: _code,
              enabled: !st.busy,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                  labelText: l10n.authCode6, border: const OutlineInputBorder(), counterText: ''),
              onSubmitted: (_) => st.busy
                  ? null
                  : ctrl.submitCode(widget.email, _code.text, password: widget.password),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: st.busy
                  ? null
                  : () => ctrl.submitCode(widget.email, _code.text, password: widget.password),
              child: st.busy
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.authVerify),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: st.busy ? null : () => ctrl.resend(widget.email),
              child: Text(l10n.authResendCode),
            ),
          ] else
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.authBackToSignIn),
            ),
        ],
      ),
    );
  }
}
