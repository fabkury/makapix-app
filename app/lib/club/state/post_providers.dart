import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/reactions.dart';
import 'api_providers.dart';

/// Full post by sqid; also fires a (debounced, server-side) view registration.
final postDetailProvider = FutureProvider.family<Post, String>((ref, sqid) async {
  final api = ref.watch(postApiProvider);
  final post = await api.getBySqid(sqid);
  api.registerView(post.id, channel: 'artwork');
  return post;
});

// ---- Reactions (optimistic add/remove, ≤5/user) ----

class ReactionsController extends StateNotifier<AsyncValue<ReactionTotals>> {
  final Ref ref;
  final int postId;
  ReactionsController(this.ref, this.postId) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = AsyncValue.data(await ref.read(postApiProvider).reactions(postId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Toggle one emoji. Returns a user-facing message on failure (else null).
  Future<String?> toggle(String emoji) async {
    final cur = state.value;
    if (cur == null) return null;
    final add = !cur.hasMine(emoji);
    if (add && cur.mineCount >= 5) return 'You can add up to 5 reactions per post.';
    state = AsyncValue.data(cur.withLocal(emoji: emoji, add: add));
    try {
      final api = ref.read(postApiProvider);
      if (add) {
        await api.addReaction(postId, emoji);
      } else {
        await api.removeReaction(postId, emoji);
      }
      return null;
    } on ClubError catch (e) {
      state = AsyncValue.data(cur); // rollback
      return e.message;
    } catch (_) {
      state = AsyncValue.data(cur);
      return 'Could not update reaction.';
    }
  }
}

final reactionsProvider =
    StateNotifierProvider.family<ReactionsController, AsyncValue<ReactionTotals>, int>(
        (ref, postId) => ReactionsController(ref, postId));

// ---- Comments ----

class CommentsController extends StateNotifier<AsyncValue<List<Comment>>> {
  final Ref ref;
  final int postId;
  CommentsController(this.ref, this.postId) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await ref.read(postApiProvider).comments(postId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<String?> add(String body, {String? parentId}) async {
    try {
      await ref.read(postApiProvider).addComment(postId, body, parentId: parentId);
      await load();
      return null;
    } on ClubError catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not post comment.';
    }
  }

  Future<void> delete(String commentId) async {
    try {
      await ref.read(postApiProvider).deleteComment(commentId);
      await load();
    } catch (_) {}
  }

  Future<void> toggleLike(Comment c) async {
    try {
      final api = ref.read(postApiProvider);
      if (c.likedByMe) {
        await api.unlikeComment(c.id);
      } else {
        await api.likeComment(c.id);
      }
      await load();
    } catch (_) {}
  }
}

final commentsProvider =
    StateNotifierProvider.family<CommentsController, AsyncValue<List<Comment>>, int>(
        (ref, postId) => CommentsController(ref, postId));
