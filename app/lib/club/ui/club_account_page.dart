import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../cache/artwork_cache.dart';
import '../config/club_config.dart';
import '../models/club_error.dart';
import '../models/club_user.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import 'auth/account_management_page.dart';
import 'auth/create_account_page.dart';
import 'auth/forgot_password_page.dart';
import 'auth/verify_email_page.dart';
import 'edit_profile_page.dart';
import 'my_players_page.dart';

/// Reachable from the editor AppBar. Renders the sign-in form or the signed-in
/// account view based on [authControllerProvider]. The app is not login-gated;
/// this is the entry point into the Club social layer.
class ClubAccountPage extends ConsumerWidget {
  const ClubAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When this page is used as a sign-in funnel (pushed from the welcome screen
    // or the sign-in form), a *fresh* sign-in should drop the user back on the
    // Club home (Recent feed), not leave them on the signed-in account view. Only
    // fire on the transition into signed-in, so opening Account from the ☰ menu
    // (already signed in) still shows the account view. `canPop` avoids touching
    // the root; `context.mounted` keeps it safe if a child page popped first.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.isSignedIn &&
          !(prev?.isSignedIn ?? false) &&
          context.mounted &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Makapix Club')),
      body: switch (auth.status) {
        AuthStatus.loading => const Center(child: CircularProgressIndicator()),
        AuthStatus.signedIn => _AccountView(me: auth.me!),
        _ => const _SignInForm(),
      },
    );
  }
}

class _SignInForm extends ConsumerStatefulWidget {
  const _SignInForm();
  @override
  ConsumerState<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<_SignInForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final ctrl = ref.read(authControllerProvider.notifier);
    final busy = auth.isBusy;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign in to Makapix Club',
                  style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              const Text('Discover art, react, comment, follow, and publish your own.',
                  style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (auth.status == AuthStatus.error && auth.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x33F44336),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x80FF5252)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(auth.error!, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              // An unverified-email login is a dead end without this — route the
              // user to enter the OTP they have (or resend one), carrying the
              // password they just typed so a successful verify signs them in.
              if (auth.isUnverified)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => VerifyEmailPage(
                                    email: _email.text.trim(), password: _password.text))),
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Verify your email'),
                  ),
                ),
              TextField(
                controller: _email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !busy,
                obscureText: _obscure,
                onSubmitted: (_) {
                  if (!busy) ctrl.loginPassword(_email.text, _password.text);
                },
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : () => ctrl.loginPassword(_email.text, _password.text),
                child: busy
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
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
                onPressed: busy ? null : () => ctrl.loginGithub(),
                icon: const Icon(Icons.code),
                label: const Text('Continue with GitHub'),
              ),
              // Sign in with Apple (iOS, guideline 4.8). Renders only when the feature
              // flag is on AND the native flow is available (iOS 13+); a no-op otherwise.
              if (ClubConfig.kAppleSignInEnabled) ...[
                const SizedBox(height: 8),
                _AppleSignInButton(busy: busy),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
                child: const Text('Forgot password?'),
              ),
              const Divider(height: 24),
              Text('New to Makapix Club?',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CreateAccountPage())),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Apple's official Sign in with Apple button, shown only where the native flow is
/// available (iOS 13+). Reached solely through the `kAppleSignInEnabled` gate, so on
/// non-Apple platforms and iOS < 13 it collapses to nothing.
class _AppleSignInButton extends ConsumerWidget {
  final bool busy;
  const _AppleSignInButton({required this.busy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(appleOAuthProvider).isAvailable(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        final ctrl = ref.read(authControllerProvider.notifier);
        return SignInWithAppleButton(
          onPressed: busy ? () {} : () => ctrl.loginApple(),
          style: SignInWithAppleButtonStyle.whiteOutlined,
          height: 40,
        );
      },
    );
  }
}

class _AccountView extends ConsumerWidget {
  final ClubMe me;
  const _AccountView({required this.me});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(authControllerProvider.notifier);
    final u = me.user;
    final hasAvatar = u.avatarUrl != null && u.avatarUrl!.isNotEmpty;
    final storage = me.quotas['storage'];
    final uploads = me.quotas['uploads'];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF2A2D31),
            backgroundImage: hasAvatar ? CachedNetworkImageProvider(u.avatarUrl!, cacheManager: avatarImageCache) : null,
            child: hasAvatar
                ? null
                : Text(u.handle.isNotEmpty ? u.handle[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 28)),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(u.handle, style: Theme.of(context).textTheme.titleLarge)),
        if (u.email != null)
          Center(child: Text(u.email!, style: const TextStyle(color: Colors.white54, fontSize: 12))),
        const SizedBox(height: 4),
        Center(
          child: Text('Signed in • ${me.roles.isEmpty ? 'user' : me.roles.join(', ')}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        const SizedBox(height: 24),
        _kv('Public ID', u.sub),
        if (storage is Map) _kv('Storage', _storageLine(storage)),
        if (uploads is Map) _kv('Uploads', _uploadsLine(uploads)),
        _kv('Can post publicly',
            me.capabilities['can_post_public'] == true ? 'Yes' : 'Pending approval'),
        const SizedBox(height: 24),
        _EditProfileButton(sqid: u.sub),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AccountManagementPage())),
          icon: const Icon(Icons.manage_accounts_outlined),
          label: const Text('Manage account'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const MyPlayersPage())),
          icon: const Icon(Icons.cast_outlined),
          label: const Text('My Players'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => ctrl.logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 140,
              child: Text(k, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]),
      );

  String _storageLine(Map s) {
    final used = (s['used_bytes'] as num?)?.toDouble() ?? 0;
    final limit = (s['limit_bytes'] as num?)?.toDouble() ?? 0;
    String mib(double b) => '${(b / (1024 * 1024)).toStringAsFixed(1)} MiB';
    return limit > 0 ? '${mib(used)} / ${mib(limit)}' : mib(used);
  }

  String _uploadsLine(Map u) {
    final remaining = u['remaining'], limit = u['limit'], window = u['window'];
    if (remaining != null && limit != null) {
      return '$remaining of $limit left${window != null ? ' / $window' : ''}';
    }
    return '—';
  }
}

/// Fetches the full profile (this page only holds a [ClubMe]) and opens
/// [EditProfilePage]. Stateful for the busy flag during the fetch.
class _EditProfileButton extends ConsumerStatefulWidget {
  final String sqid;
  const _EditProfileButton({required this.sqid});
  @override
  ConsumerState<_EditProfileButton> createState() => _EditProfileButtonState();
}

class _EditProfileButtonState extends ConsumerState<_EditProfileButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final profile = await ref.read(profileApiProvider).profile(widget.sqid);
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => EditProfilePage(profile: profile)));
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not load your profile.')));
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: _busy ? null : _open,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.edit_outlined),
        label: const Text('Edit profile'),
      );
}
