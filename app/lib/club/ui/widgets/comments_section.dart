import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/comment.dart';
import '../../state/auth_controller.dart';
import '../../state/post_providers.dart';
import '../club_account_page.dart';
import 'common.dart';

/// Threaded comments (depth ≤2) with a composer, likes, reply, and delete-own.
class CommentsSection extends ConsumerStatefulWidget {
  final int postId;
  const CommentsSection({super.key, required this.postId});
  @override
  ConsumerState<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends ConsumerState<CommentsSection> {
  final _field = TextEditingController();
  String? _replyTo;
  String? _replyToHandle;
  bool _sending = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _field.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    final err = await ref.read(commentsProvider(widget.postId).notifier).add(body, parentId: _replyTo);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (err == null) {
        _field.clear();
        _replyTo = null;
        _replyToHandle = null;
      }
    });
    if (err != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(commentsProvider(widget.postId));
    final auth = ref.watch(authControllerProvider);
    final mySub = auth.me?.user.sub;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Comments', style: TextStyle(fontWeight: FontWeight.bold))),
      async.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => const Padding(
            padding: EdgeInsets.all(8), child: Text('Could not load comments.', style: TextStyle(color: Colors.white54))),
        data: (tree) => tree.isEmpty
            ? const Padding(padding: EdgeInsets.all(12), child: Text('No comments yet.', style: TextStyle(color: Colors.white38)))
            : Column(children: [for (final c in tree) _tile(c, mySub, depth: 0)]),
      ),
      const SizedBox(height: 8),
      if (auth.isSignedIn) _composer() else _signInRow(),
    ]);
  }

  Widget _signInRow() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubAccountPage())),
          icon: const Icon(Icons.login),
          label: const Text('Sign in to comment'),
        ),
      );

  Widget _composer() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_replyToHandle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text('Replying to @$_replyToHandle', style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const Spacer(),
              IconButton(
                iconSize: 16,
                onPressed: () => setState(() {
                  _replyTo = null;
                  _replyToHandle = null;
                }),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _field,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                  hintText: 'Add a comment…', border: OutlineInputBorder(), counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          _sending
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(onPressed: _send, icon: const Icon(Icons.send)),
        ]),
      ]);

  Widget _tile(Comment c, String? mySub, {required int depth}) {
    final isOwn = c.author?.sqid != null && c.author!.sqid == mySub;
    final notifier = ref.read(commentsProvider(widget.postId).notifier);
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, top: 6, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HandleAvatar(url: c.author?.avatarUrl, handle: c.author?.handle ?? '?', radius: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(c.author?.handle ?? 'guest',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 6),
                Text(timeAgo(c.createdAt), style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ]),
              Text(c.deleted ? '[deleted]' : c.body,
                  style: TextStyle(fontSize: 13, color: c.deleted ? Colors.white38 : Colors.white)),
              Row(children: [
                _miniBtn(c.likedByMe ? Icons.favorite : Icons.favorite_border,
                    c.likeCount > 0 ? '${c.likeCount}' : 'Like',
                    onTap: () => notifier.toggleLike(c), active: c.likedByMe),
                if (depth == 0)
                  _miniBtn(Icons.reply, 'Reply', onTap: () => setState(() {
                        _replyTo = c.id;
                        _replyToHandle = c.author?.handle ?? 'guest';
                      })),
                if (isOwn) _miniBtn(Icons.delete_outline, 'Delete', onTap: () => notifier.delete(c.id)),
              ]),
            ]),
          ),
        ]),
        for (final r in c.replies) _tile(r, mySub, depth: depth + 1),
      ]),
    );
  }

  Widget _miniBtn(IconData icon, String label, {required VoidCallback onTap, bool active = false}) =>
      TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 14, color: active ? Colors.redAccent : Colors.white54),
        label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.redAccent : Colors.white54)),
      );
}
