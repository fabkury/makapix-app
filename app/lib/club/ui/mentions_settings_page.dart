import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/club_user.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';

/// Settings → Mentions: who may mention this user (`users.mention_policy`,
/// server message 0004/0002 §4).
///
/// The `following` option is the one users read backwards, so the copy states
/// the direction twice: in the option label ("People I follow") and in its
/// description. Saving is immediate on pick, like a radio setting should be —
/// there is nothing to lose by mistapping, since the value is one tap back.
class MentionsSettingsPage extends ConsumerStatefulWidget {
  const MentionsSettingsPage({super.key});

  @override
  ConsumerState<MentionsSettingsPage> createState() => _MentionsSettingsPageState();
}

class _MentionsSettingsPageState extends ConsumerState<MentionsSettingsPage> {
  late MentionPolicy _policy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _policy = ref.read(authControllerProvider).me?.user.mentionPolicy ??
        MentionPolicy.everyone;
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save(MentionPolicy next) async {
    if (next == _policy || _saving) return;
    final userKey = ref.read(authControllerProvider).me?.user.userKey ?? '';
    if (userKey.isEmpty) {
      _toast('Could not determine your account id.');
      return;
    }
    final previous = _policy;
    setState(() {
      _policy = next;
      _saving = true;
    });
    try {
      final applied =
          await ref.read(settingsApiProvider).setMentionPolicy(userKey, next);
      ref.read(authControllerProvider.notifier).updateMentionPolicy(applied);
      if (!mounted) return;
      setState(() {
        _policy = applied;
        _saving = false;
      });
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() {
        _policy = previous;
        _saving = false;
      });
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _policy = previous;
        _saving = false;
      });
      _toast('Could not save that setting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mentions')),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'When someone mentions you in a comment or in an artwork '
              'description, your handle becomes a link to your profile and you '
              'get a notification.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text('Who can mention me',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            RadioGroup<MentionPolicy>(
              groupValue: _policy,
              onChanged: (v) {
                if (_saving || v == null) return;
                _save(v);
              },
              child: Column(children: [
                for (final option in MentionPolicy.values)
                  RadioListTile<MentionPolicy>(
                    contentPadding: EdgeInsets.zero,
                    value: option,
                    title: Text(option.label),
                    subtitle: Text(option.description,
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            if (_saving)
              const Row(children: [
                SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Saving…', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            const Divider(height: 32),
            const Text(
              'Blocking still applies on top of this: a member you have blocked '
              'can never mention you, whatever this is set to.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
