import 'package:flutter/material.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/post.dart';
import '../state/api_providers.dart';
import '../state/feed_providers.dart';
import '../state/pmd_providers.dart';
import '../state/post_providers.dart';

/// Owner-only metadata editor for an existing post (`PATCH /post/{id}`):
/// title, description, and the artist-controlled hashtags. Moderator-owned
/// tags are shown read-only and never submitted — the server re-merges them
/// regardless of what the artist sends (docs/mod-hashtags D10).
class EditPostDetailsPage extends ConsumerStatefulWidget {
  final Post post;
  const EditPostDetailsPage({super.key, required this.post});

  /// Comma-separated input → normalized tag list, mirroring the website and
  /// the server's `normalize_hashtags`: trim, lowercase, strip a leading `#`,
  /// drop empties and duplicates.
  static List<String> parseHashtags(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (var t in raw.split(',')) {
      t = t.trim().toLowerCase();
      if (t.startsWith('#')) t = t.substring(1);
      if (t.isEmpty || !seen.add(t)) continue;
      out.add(t);
    }
    return out;
  }

  @override
  ConsumerState<EditPostDetailsPage> createState() => _EditPostDetailsPageState();
}

class _EditPostDetailsPageState extends ConsumerState<EditPostDetailsPage> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _hashtags;

  // Dirty baseline (the artist-controlled tag list, normalized).
  late final String _baseTitle;
  late final String _baseDescription;
  late final List<String> _baseTags;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _baseTitle = p.title;
    _baseDescription = p.description ?? '';
    // Only artist-controlled tags are editable; mod-owned ones stay chips.
    _baseTags = p.hashtags.where((t) => !p.isModTag(t)).toList();
    _title = TextEditingController(text: _baseTitle);
    _description = TextEditingController(text: _baseDescription);
    _hashtags = TextEditingController(text: _baseTags.join(', '));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _hashtags.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool get _dirty {
    if (_title.text.trim() != _baseTitle) return true;
    if (_description.text != _baseDescription) return true;
    final tags = EditPostDetailsPage.parseHashtags(_hashtags.text);
    if (tags.length != _baseTags.length) return true;
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != _baseTags[i]) return true;
    }
    return false;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return _toast('The title cannot be empty.');
    setState(() => _saving = true);
    try {
      await ref.read(postApiProvider).update(
            widget.post.id,
            title: title,
            description: _description.text,
            hashtags: EditPostDetailsPage.parseHashtags(_hashtags.text),
          );
      if (!mounted) return;
      // The detail page refetches; feeds/PMD re-list so titles stay in step.
      ref.invalidate(postDetailProvider(widget.post.sqid));
      ref.invalidate(feedProvider);
      ref.invalidate(ownerFeedProvider);
      ref.invalidate(hashtagFeedProvider);
      ref.invalidate(pmdListProvider);
      Navigator.of(context).pop(true);
    } on ClubError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save the changes.');
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this post have not been saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final modTags = widget.post.modHashtags;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit details')),
        body: CenteredContent(
            child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _title,
              maxLength: 128,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 6,
              maxLength: 5000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hashtags,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Hashtags',
                hintText: 'pixelart, animation, fantasy',
                helperText: 'Separate with commas.',
                border: OutlineInputBorder(),
              ),
            ),
            if (modTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in modTags)
                  Chip(
                    avatar: const Icon(Icons.shield, size: 14),
                    label: Text('#$t'),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
              const SizedBox(height: 4),
              const Text('Tagged by a moderator — these tags cannot be edited.',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (_dirty && !_saving) ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        )),
      ),
    );
  }
}
