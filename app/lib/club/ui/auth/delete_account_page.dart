import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/club_error.dart';
import '../../state/auth_controller.dart';

/// Settings → Account → Danger zone: permanently delete the signed-in account
/// (App Store guideline 5.1.1(v)). Explains what deletion means, requires the
/// user to type DELETE, then calls `POST /user/delete-account` (202 — the
/// server deactivates immediately and erases data asynchronously), confirms,
/// signs out locally, and returns to the root (signed-out welcome).
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});
  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _confirm = TextEditingController();
  bool _busy = false;

  /// The exact word that arms the delete button.
  static const kConfirmWord = 'DELETE';

  bool get _armed => _confirm.text.trim() == kConfirmWord;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(clubApiClientProvider).requestAccountDeletion();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Account deleted'),
          content: const Text(
              'Your account has been deactivated and your data is being '
              'permanently deleted. Thank you for having been part of '
              'Makapix Club.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (!mounted) return;
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ClubError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handle = ref.watch(authControllerProvider).me?.user.handle;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: CenteredContent(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF2A1518),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text('This is permanent',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.redAccent)),
                  ]),
                  const SizedBox(height: 12),
                  _bullet('Your profile${handle != null ? ' (@$handle)' : ''}, posts, '
                      'comments, reactions, followers, and settings will be '
                      'permanently deleted.'),
                  _bullet('Comments that other users have replied to are '
                      'replaced with an anonymous "[deleted comment]" '
                      'placeholder so their replies stay readable.'),
                  _bullet('Deletion cannot be undone. Deleted content is not '
                      'recoverable.'),
                  _bullet('You will be signed out immediately and your account '
                      'deactivated. Data removal completes on our servers '
                      'shortly afterwards.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('To confirm, type $kConfirmWord below.',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type $kConfirmWord to confirm',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.red.shade700.withValues(alpha: 0.25),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _armed && !_busy ? _delete : null,
            icon: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.delete_forever),
            label: const Text('Delete my account'),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      )),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(color: Colors.white70)),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
          ],
        ),
      );
}
