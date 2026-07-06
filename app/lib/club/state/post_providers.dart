import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/club_error.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/reactions.dart';
import 'api_providers.dart';
import 'auth_controller.dart';

/// Full post by sqid; also fires a (debounced, server-side) view registration.
// autoDispose: one entry per opened post; released when the detail page closes. [audit F-19]
final postDetailProvider = FutureProvider.autoDispose.family<Post, String>((ref, sqid) async {
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
      var totals = await ref.read(postApiProvider).reactions(postId);
      // If the viewer just liked/unliked this post on the grid, reflect that 👍 here even when the
      // server read raced ahead of that still-in-flight write — the grid override is the intent.
      final override = ref.read(gridLikesProvider)[postId];
      if (override != null && override.liked != totals.hasMine('👍')) {
        totals = totals.withLocal(emoji: '👍', add: override.liked);
      }
      state = AsyncValue.data(totals);
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
      _syncGrid(); // keep the grid tile's 👍 like + count in step with the detail
      return null;
    } on ClubError catch (e) {
      state = AsyncValue.data(cur); // rollback
      return e.isBlocked ? kBlockedInteractionMessage : e.message;
    } catch (_) {
      state = AsyncValue.data(cur);
      return 'Could not update reaction.';
    }
  }

  /// Push the current 👍 state and total reaction count into the grid override so the feed tile
  /// stays consistent with what the user just did on the detail page.
  void _syncGrid() {
    if (!mounted) return;
    final t = state.value;
    if (t == null) return;
    final total = t.totals.values.fold<int>(0, (a, b) => a + b);
    ref.read(gridLikesProvider.notifier).set(postId, GridLikeState(t.hasMine('👍'), total));
  }
}

final reactionsProvider =
    StateNotifierProvider.autoDispose.family<ReactionsController, AsyncValue<ReactionTotals>, int>(
        (ref, postId) => ReactionsController(ref, postId)); // [audit F-19]

/// The list of authenticated reactors for a post, backing the Reactions page. One-shot fetch
/// (the endpoint is capped at 200, unpaginated), so a plain FutureProvider suffices.
// autoDispose: released when the Reactions page closes. [audit F-19]
final reactionUsersProvider = FutureProvider.autoDispose.family<List<ReactionUser>, int>(
    (ref, postId) => ref.read(postApiProvider).reactionUsers(postId));

// ---- Grid "like" (👍) toggle ----
//
// The feed grid shows a single 👍 like affordance per tile. Fetching per-tile reaction totals
// would be a request storm while scrolling, so tiles display the post's own `userHasLiked` /
// `reactionCount` from the feed payload, and this controller keeps an optimistic per-post override
// for likes the user toggles on the grid. Keyed by post id so it survives tile recycling on scroll.

/// Displayed like-state of a grid tile: whether the viewer likes it, and the reaction count shown.
class GridLikeState {
  final bool liked;
  final int count;
  const GridLikeState(this.liked, this.count);
}

class GridLikesController extends StateNotifier<Map<int, GridLikeState>> {
  final Ref ref;
  GridLikesController(this.ref) : super(const {});

  /// The state to show for [post]: a local override if the user toggled it, else the feed values.
  GridLikeState resolve(Post post) => state[post.id] ?? GridLikeState(post.userHasLiked, post.reactionCount);

  /// Set the override for a post (used by the detail page to keep the grid in step).
  void set(int postId, GridLikeState s) => state = {...state, postId: s};

  /// Toggle the 👍 like for [post]. Optimistic; rolls back and returns a message on failure.
  Future<String?> toggle(Post post) async {
    final cur = resolve(post);
    final add = !cur.liked;
    final raw = cur.count + (add ? 1 : -1);
    state = {...state, post.id: GridLikeState(add, raw < 0 ? 0 : raw)};
    try {
      final api = ref.read(postApiProvider);
      if (add) {
        await api.addReaction(post.id, '👍');
      } else {
        await api.removeReaction(post.id, '👍');
      }
      // Drop any cached detail reactions for this post so it reloads (and reconciles with this
      // override) next time it's opened, instead of showing a pre-like snapshot.
      ref.invalidate(reactionsProvider(post.id));
      return null;
    } on ClubError catch (e) {
      state = {...state, post.id: cur}; // rollback
      return e.isBlocked ? kBlockedInteractionMessage : e.message;
    } catch (_) {
      state = {...state, post.id: cur};
      return 'Could not update reaction.';
    }
  }
}

final gridLikesProvider =
    StateNotifierProvider<GridLikesController, Map<int, GridLikeState>>((ref) {
  // Like overrides are the viewer's own; drop them all when the signed-in account changes.
  ref.watch(currentUserSubProvider);
  return GridLikesController(ref);
});

// ---- Comments ----

/// Live comment count for a thread: non-deleted comments across all depths (top-level + replies).
/// Mirrors what the server reports in `comment_count`, and tracks the optimistic add/delete edits
/// the controller applies so the detail header and the "Comments (N)" label stay in step.
int countComments(List<Comment> tree) {
  var n = 0;
  for (final c in tree) {
    if (!c.deleted) n++;
    n += countComments(c.replies);
  }
  return n;
}

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
    // Optimistically show the new comment (and bump the count) before the round-trip; `load()`
    // reconciles with the server copy afterwards.
    final cur = state.value;
    if (cur != null) {
      final me = ref.read(authControllerProvider).me?.user;
      final optimistic = Comment(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        parentId: parentId,
        depth: parentId == null ? 0 : 1,
        body: body,
        createdAt: DateTime.now(),
        author: me == null ? null : CommentAuthor(handle: me.handle, sqid: me.sub, avatarUrl: me.avatarUrl),
        likeCount: 0,
        likedByMe: false,
        deleted: false,
      );
      state = AsyncValue.data(_withAppended(cur, optimistic, parentId));
    }
    try {
      await ref.read(postApiProvider).addComment(postId, body, parentId: parentId);
      await load();
      return null;
    } on ClubError catch (e) {
      await load(); // drop the optimistic comment
      return e.isBlocked ? kBlockedInteractionMessage : e.message;
    } catch (_) {
      await load();
      return 'Could not post comment.';
    }
  }

  Future<void> delete(String commentId) async {
    // Optimistically mark it deleted so the count drops at once; reconcile on reload.
    final cur = state.value;
    if (cur != null) state = AsyncValue.data(_withDeleted(cur, commentId));
    try {
      await ref.read(postApiProvider).deleteComment(commentId);
      await load();
    } catch (_) {
      await load();
    }
  }

  static List<Comment> _withAppended(List<Comment> tree, Comment c, String? parentId) {
    if (parentId == null) return [...tree, c];
    return [for (final t in tree) t.id == parentId ? t.withReplies([...t.replies, c]) : t];
  }

  static List<Comment> _withDeleted(List<Comment> tree, String id) =>
      [for (final c in tree) c.id == id ? c.markDeleted() : c.withReplies(_withDeleted(c.replies, id))];

  /// Returns [kBlockedInteractionMessage] when refused by a block, else null.
  /// Other errors stay silent (fire-and-forget, as before).
  Future<String?> toggleLike(Comment c) async {
    try {
      final api = ref.read(postApiProvider);
      if (c.likedByMe) {
        await api.unlikeComment(c.id);
      } else {
        await api.likeComment(c.id);
      }
      await load();
      return null;
    } on ClubError catch (e) {
      return e.isBlocked ? kBlockedInteractionMessage : null;
    } catch (_) {
      return null;
    }
  }
}

final commentsProvider =
    StateNotifierProvider.autoDispose.family<CommentsController, AsyncValue<List<Comment>>, int>(
        (ref, postId) => CommentsController(ref, postId)); // [audit F-19]
