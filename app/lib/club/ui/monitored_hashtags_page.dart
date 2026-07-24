import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/monitored_hashtags.dart';
import '../models/club_error.dart';
import '../state/api_providers.dart';
import '../state/auth_controller.dart';
import '../state/feed_providers.dart';

/// Settings → Monitored hashtags: the monitored-hashtag content filter
/// (`SPEC-CLUB.md` §21). Opt in to seeing posts tagged
/// `#politics/#nsfw/#explicit/#13plus/#violence` (all hidden by default).
/// Mirrors the website's `/u/{sqid}/settings`.
class MonitoredHashtagsPage extends ConsumerStatefulWidget {
  const MonitoredHashtagsPage({super.key});
  @override
  ConsumerState<MonitoredHashtagsPage> createState() => _MonitoredHashtagsPageState();
}

class _MonitoredHashtagsPageState extends ConsumerState<MonitoredHashtagsPage> {
  late Set<String> _selected;
  late Set<String> _initial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final approved = ref.read(authControllerProvider).me?.user.approvedHashtags ?? const [];
    // Keep only currently-monitored tags (a since-removed tag would be unmappable).
    final valid = approved.where(kMonitoredHashtagTags.contains).toSet();
    _selected = {...valid};
    _initial = {...valid};
  }

  bool get _dirty =>
      _selected.length != _initial.length || !_selected.containsAll(_initial);

  Future<void> _save() async {
    final userKey = ref.read(authControllerProvider).me?.user.userKey ?? '';
    if (userKey.isEmpty) {
      _toast('Could not determine your account id.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result =
          await ref.read(settingsApiProvider).setApprovedHashtags(userKey, _selected.toList());
      final applied = result.where(kMonitoredHashtagTags.contains).toSet();
      ref.read(authControllerProvider.notifier).updateApprovedHashtags(applied.toList());
      // Feeds are filtered server-side from approved_hashtags — re-fetch so the
      // change is visible immediately.
      ref.invalidate(feedProvider);
      if (!mounted) return;
      setState(() {
        _selected = {...applied};
        _initial = {...applied};
        _saving = false;
      });
      _toast('Saved.');
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save settings.');
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monitored hashtags')),
      body: CenteredContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Posts tagged with these are hidden by default. Tick a tag to opt in to '
              'seeing it across feeds, search and notifications.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            for (final h in kMonitoredHashtags) _tagTile(h),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: (!_dirty || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagTile(MonitoredHashtag h) {
    final cs = Theme.of(context).colorScheme;
    final on = _selected.contains(h.tag);
    return CheckboxListTile(
      value: on,
      onChanged: _saving
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _selected.add(h.tag);
                } else {
                  _selected.remove(h.tag);
                }
              }),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Row(children: [
        Text(h.label,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        _badge(on ? 'Shown' : 'Hidden', on ? cs.primary : Colors.white38),
      ]),
      subtitle: Text(h.description, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );
}
