import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/monitored_hashtags.dart';
import '../../edit/mod_hashtag_edit.dart';
import '../../models/club_error.dart';
import '../../models/post.dart';
import '../../state/api_providers.dart';
import '../../state/post_providers.dart';

/// Moderator-only "Edit moderator hashtags" sheet (mod-hashtags contract v1).
/// Full-replace semantics: Save PUTs the whole working set. Callers gate on
/// `ClubServerConfig.modHashtagsEnabled` + `ClubMe.canModerate`.
Future<void> showModHashtagsSheet(BuildContext context,
    {required Post post, required int cap}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ModHashtagsSheet(post: post, cap: cap),
  );
}

class _ModHashtagsSheet extends ConsumerStatefulWidget {
  final Post post;
  final int cap;
  const _ModHashtagsSheet({required this.post, required this.cap});

  @override
  ConsumerState<_ModHashtagsSheet> createState() => _ModHashtagsSheetState();
}

class _ModHashtagsSheetState extends ConsumerState<_ModHashtagsSheet> {
  late final ModHashtagEdit _edit;
  final _tagField = TextEditingController();
  final _noteField = TextEditingController();
  bool _saving = false;
  String? _inlineError; // add-field rejections
  String? _saveError; // PUT failures, shown above the actions

  @override
  void initState() {
    super.initState();
    _edit = ModHashtagEdit(initial: widget.post.modHashtags, cap: widget.cap);
  }

  @override
  void dispose() {
    _tagField.dispose();
    _noteField.dispose();
    super.dispose();
  }

  void _tryAdd(String raw) {
    if (raw.trim().isEmpty) return;
    setState(() {
      if (_edit.add(raw)) {
        _tagField.clear();
        _inlineError = null;
      } else {
        _inlineError = _edit.lastRejection;
      }
    });
  }

  // Comma submits the pending tag (Enter goes through onSubmitted). Always
  // setState: the Save button's enablement also tracks the pending text.
  void _onChanged(String value) {
    if (value.endsWith(',')) {
      _tryAdd(value.substring(0, value.length - 1));
    } else {
      setState(() => _inlineError = null);
    }
  }

  Future<void> _save() async {
    // Commit any tag left typed-but-unsubmitted in the field first.
    final pending = _tagField.text.trim();
    if (pending.isNotEmpty) {
      _tryAdd(pending);
      if (_inlineError != null) return; // rejection shown; let the mod decide
    }
    // Removing a monitored tag re-exposes the post to everyone — confirm.
    final removed = _edit.removedMonitored;
    if (removed.isNotEmpty) {
      final tags = removed.map((t) => '#$t').join(', ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove monitored hashtag?'),
          content: Text('Removing $tags will make this post visible to everyone again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final note = _noteField.text.trim();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(moderationApiProvider)
          .setModHashtags(widget.post.id, _edit.tags, note: note.isEmpty ? null : note);
      ref.invalidate(postDetailProvider(widget.post.sqid));
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Moderator hashtags updated.')));
    } on ClubError catch (e) {
      if (!mounted) return;
      if (e.status == 404) {
        // Deleted (or turned playlist) under us — the sheet has no subject left.
        nav.pop();
        ref.invalidate(postDetailProvider(widget.post.sqid));
        messenger.showSnackBar(const SnackBar(
            content: Text("This post can't be tagged — it may have been deleted.")));
        return;
      }
      setState(() {
        _saving = false;
        _saveError = switch (e.code) {
          'forbidden' => 'Only moderators can edit these hashtags.',
          'validation_error' => e.message,
          _ => e.isAuth
              ? 'Your session expired — sign in again to edit moderator hashtags.'
              : 'Could not save — check your connection and try again.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save — check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monitored = _edit.tags.toSet().intersection(kMonitoredHashtagTags);
    return Padding(
      // Keep the add-tag field above the soft keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.shield, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('Edit moderator hashtags', style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(
              'Only moderators can add or remove these. They behave like regular '
              'hashtags, including monitored ones.',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 16),
            const Text('Quick add', style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final m in kMonitoredHashtags)
                FilterChip(
                  label: Text(m.label),
                  tooltip: m.description,
                  selected: _edit.contains(m.tag),
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                            final wasIn = _edit.contains(m.tag);
                            _edit.toggle(m.tag);
                            // A remove can't fail; only surface a rejection
                            // when the chip actually tried to add (cap).
                            _inlineError = wasIn ? null : _edit.lastRejection;
                          }),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('On this post', style: TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 6),
            if (_edit.tags.isEmpty)
              const Text('No moderator hashtags on this post.',
                  style: TextStyle(fontSize: 13, color: Colors.white38))
            else
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final tag in _edit.tags)
                  InputChip(
                    label: Text('#$tag'),
                    // Monitored tags carry the shield + primary tint so a
                    // typo'd near-monitored tag ("nswf") is visibly NOT one.
                    avatar: monitored.contains(tag)
                        ? Icon(Icons.shield, size: 16, color: theme.colorScheme.primary)
                        : null,
                    onDeleted: _saving ? null : () => setState(() => _edit.remove(tag)),
                  ),
              ]),
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: TextField(
                  controller: _tagField,
                  enabled: !_saving,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Add tag',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    counterText: '${_edit.tags.length}/${widget.cap}',
                  ),
                  onChanged: _onChanged,
                  onSubmitted: _tryAdd,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add',
                onPressed: _saving ? null : () => _tryAdd(_tagField.text),
              ),
            ]),
            if (_inlineError != null) ...[
              const SizedBox(height: 6),
              Text(_inlineError!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteField,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Note (for the audit log)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Text(_saveError!,
                  style: TextStyle(fontSize: 13, color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_saving || !_edit.changed && _tagField.text.trim().isEmpty)
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
