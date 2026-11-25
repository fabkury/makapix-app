import 'post.dart';

/// What a Pulse card is about. One card = one member + one kind + one burst of activity
/// (`GET /pulse`, messages/0008-pulse/0002 §3).
enum PulseKind {
  likes('likes'),
  posts('posts'),
  remixes('remixes'),
  comments('comments'),
  player('player'),
  badge('badge'),
  reputation('reputation'),
  promoted('promoted');

  /// The value on the wire, in `kind` and in the `kinds` query parameter.
  final String wire;
  const PulseKind(this.wire);

  static PulseKind? fromWire(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// The member a card is about.
class PulseActor {
  final String sqid;
  final String handle;
  final String? avatarUrl;
  const PulseActor({required this.sqid, required this.handle, this.avatarUrl});

  factory PulseActor.fromJson(Map<String, dynamic> j) => PulseActor(
        sqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? '').toString(),
        avatarUrl: j['avatar_url'] as String?,
      );
}

/// One comment inside a `comments` card: a plain-text preview and the post it is on.
class PulseComment {
  final String id;
  final String preview;
  final bool isReply;
  final DateTime? createdAt;
  final Post post;
  const PulseComment({
    required this.id,
    required this.preview,
    required this.isReply,
    required this.createdAt,
    required this.post,
  });

  static PulseComment? fromJson(Map<String, dynamic> j) {
    final post = j['post'];
    if (post is! Map) return null;
    return PulseComment(
      id: (j['id'] ?? '').toString(),
      preview: (j['preview'] ?? '').toString(),
      isReply: j['is_reply'] == true,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      post: Post.fromJson(post.cast<String, dynamic>()),
    );
  }
}

/// One badge inside a `badge` card. [label] is the server's English name; the UI prefers the
/// app's own translation for the slugs it knows (`badgeLabel`).
class PulseBadge {
  final String badge;
  final String label;
  final String iconUrl64;
  const PulseBadge({required this.badge, required this.label, required this.iconUrl64});

  factory PulseBadge.fromJson(Map<String, dynamic> j) => PulseBadge(
        badge: (j['badge'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        iconUrl64: (j['icon_url_64'] ?? '').toString(),
      );
}

/// One card of the Pulse timeline.
class PulseCard {
  /// Opaque and stable while the card grows at its newest end; the list keys on it.
  final String id;
  final PulseKind kind;
  final PulseActor actor;

  /// The card's newest event: its place in the timeline.
  final DateTime? updatedAt;

  /// Events in the card. May exceed what [posts] / [comments] carry (the server sends at most
  /// six posts and three comments); the UI shows the rest as "+N more".
  final int count;

  final List<Post> posts; // likes · posts · remixes · promoted
  final List<PulseComment> comments; // comments
  final String? playerModel; // player (nullable: the device may not report one)
  final List<PulseBadge> badges; // badge
  final int reputationDelta; // reputation: the sum over the card, always > 0
  final int? reputationTotal; // reputation: the member's total right after the card

  const PulseCard({
    required this.id,
    required this.kind,
    required this.actor,
    required this.updatedAt,
    required this.count,
    this.posts = const [],
    this.comments = const [],
    this.playerModel,
    this.badges = const [],
    this.reputationDelta = 0,
    this.reputationTotal,
  });

  /// Events the card counts beyond the ones it carries.
  int get more {
    final shown = switch (kind) {
      PulseKind.comments => comments.length,
      PulseKind.likes || PulseKind.posts || PulseKind.remixes || PulseKind.promoted => posts.length,
      _ => count,
    };
    return count > shown ? count - shown : 0;
  }

  /// Null for a card this build cannot show: a `kind` it does not know (the server may add
  /// kinds later), no actor, or a card whose own payload is missing.
  static PulseCard? fromJson(Map<String, dynamic> j) {
    final kind = PulseKind.fromWire(j['kind']?.toString());
    final actorJson = j['actor'];
    if (kind == null || actorJson is! Map) return null;
    final actor = PulseActor.fromJson(actorJson.cast<String, dynamic>());
    if (actor.sqid.isEmpty) return null;

    List<Map<String, dynamic>> maps(Object? raw) => [
          if (raw is List)
            for (final e in raw)
              if (e is Map) e.cast<String, dynamic>(),
        ];

    final posts = maps(j['posts']).map(Post.fromJson).toList();
    final comments = maps(j['comments']).map(PulseComment.fromJson).nonNulls.toList();
    final badges = maps(j['badges']).map(PulseBadge.fromJson).toList();
    final reputation = j['reputation'] is Map
        ? (j['reputation'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final delta = (reputation['delta'] as num?)?.toInt() ?? 0;

    final hasPayload = switch (kind) {
      PulseKind.likes || PulseKind.posts || PulseKind.remixes || PulseKind.promoted => posts.isNotEmpty,
      PulseKind.comments => comments.isNotEmpty,
      PulseKind.badge => badges.isNotEmpty,
      PulseKind.reputation => delta > 0,
      PulseKind.player => true,
    };
    if (!hasPayload) return null;

    final id = (j['id'] ?? '').toString();
    final count = (j['count'] as num?)?.toInt() ?? 0;
    return PulseCard(
      // An id is what keeps a card's place across a refresh; a card without one still shows.
      id: id.isNotEmpty ? id : '${kind.wire}:${actor.sqid}:${j['started_at']}', // l10n-ignore: key
      kind: kind,
      actor: actor,
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
      count: count < 1 ? 1 : count,
      posts: posts,
      comments: comments,
      playerModel: j['player'] is Map ? (j['player'] as Map)['device_model'] as String? : null,
      badges: badges,
      reputationDelta: delta,
      reputationTotal: (reputation['total'] as num?)?.toInt(),
    );
  }
}
