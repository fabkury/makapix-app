import 'post.dart';

/// A small badge shown under a user's handle (`tag_badges`).
class TagBadge {
  final String badge;
  final String label;
  final String? iconUrl16;
  const TagBadge({required this.badge, required this.label, this.iconUrl16});

  factory TagBadge.fromJson(Map<String, dynamic> j) => TagBadge(
        badge: (j['badge'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        iconUrl16: j['icon_url_16'] as String?,
      );
}

class ProfileStats {
  final int totalPosts;
  final int totalReactionsReceived;
  final int totalViews;
  final int followerCount;
  const ProfileStats({
    this.totalPosts = 0,
    this.totalReactionsReceived = 0,
    this.totalViews = 0,
    this.followerCount = 0,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> j) => ProfileStats(
        totalPosts: (j['total_posts'] as num?)?.toInt() ?? 0,
        totalReactionsReceived: (j['total_reactions_received'] as num?)?.toInt() ?? 0,
        totalViews: (j['total_views'] as num?)?.toInt() ?? 0,
        followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
      );

  ProfileStats copyWith({int? followerCount}) => ProfileStats(
        totalPosts: totalPosts,
        totalReactionsReceived: totalReactionsReceived,
        totalViews: totalViews,
        followerCount: followerCount ?? this.followerCount,
      );
}

/// `GET /user/u/{sqid}/profile` (UserProfileEnhanced).
class UserProfile {
  final String userKey;
  final String sqid;
  final String handle;
  final String? bio;
  final String? tagline;
  final String? website;
  final String? avatarUrl;
  final int reputation;
  final List<TagBadge> tagBadges;
  final ProfileStats stats;
  final bool isFollowing;
  final bool isOwnProfile;
  final List<Post> highlights;

  UserProfile({
    required this.userKey,
    required this.sqid,
    required this.handle,
    required this.bio,
    required this.tagline,
    required this.website,
    required this.avatarUrl,
    required this.reputation,
    required this.tagBadges,
    required this.stats,
    required this.isFollowing,
    required this.isOwnProfile,
    required this.highlights,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userKey: (j['user_key'] ?? '').toString(),
        sqid: (j['public_sqid'] ?? '').toString(),
        handle: (j['handle'] ?? 'unknown').toString(),
        bio: j['bio'] as String?,
        tagline: j['tagline'] as String?,
        website: j['website'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        reputation: (j['reputation'] as num?)?.toInt() ?? 0,
        tagBadges: (j['tag_badges'] as List?)
                ?.map((e) => TagBadge.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        stats: ProfileStats.fromJson((j['stats'] as Map?)?.cast<String, dynamic>() ?? const {}),
        isFollowing: j['is_following'] == true,
        isOwnProfile: j['is_own_profile'] == true,
        highlights: (j['highlights'] as List?)
                ?.map((e) => Post.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
      );

  UserProfile copyWith({bool? isFollowing, ProfileStats? stats}) => UserProfile(
        userKey: userKey,
        sqid: sqid,
        handle: handle,
        bio: bio,
        tagline: tagline,
        website: website,
        avatarUrl: avatarUrl,
        reputation: reputation,
        tagBadges: tagBadges,
        stats: stats ?? this.stats,
        isFollowing: isFollowing ?? this.isFollowing,
        isOwnProfile: isOwnProfile,
        highlights: highlights,
      );
}
