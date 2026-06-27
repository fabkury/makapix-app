# C1 — Read & Discover (`app/lib/club/`)

**Phase:** C1 of the Makapix Club social pillar (SPEC-CLUB §28).
**Status:** 🟡 in progress — see [Progress](#progress).
**Depends on:** C0 (config, `ClubApiClient` with bearer + refresh, Riverpod, models/error). **Last updated:** 2026-06-26.

---

## 1. Goal & acceptance

Let a signed-in (or, where the server allows, signed-out) user **browse and engage** with Club content from the
app:

- **Feeds:** Recent, Recommended (promoted), Following, by-hashtag, plus a filtered browse.
- **Artwork detail:** the viewer + metadata + license + owner, with **view registration**, **download/share**.
- **Reactions:** the curated 5-emoji set, totals + who-reacted, optimistic add/remove (≤5/user).
- **Comments:** threaded (depth ≤2) with replies, likes, create/edit/delete.
- **Profiles:** header (avatar/bio/tagline/badges/stats), follow/unfollow, gallery + favourites + highlights.
- **Search:** artworks / users / hashtags.
- **Notifications:** list + unread badge (polling), mark read.

**Acceptance:**
- **Tier-1 (Windows):** model parsing tested against the real JSON shapes (Post, Page cursor, reactions,
  comments, profile, notification); `flutter analyze` clean for `lib/club`.
- **Build:** `flutter build apk --debug` (JBR) green.
- **Device (user):** open Club → feeds load; open a post → react + comment; open a profile → follow; search;
  notifications.

**Non-goals (deferred):** real-time notifications (C5, MQTT); playlists/categories/dashboard/post-management
(C4); publishing/remix (C2/C3); offline cache beyond image caching; reporting UI (C4).

---

## 2. Endpoints (all `/api/v1`, confirmed live on dev)

- Feeds: `GET /post/recent`, `GET /feed/promoted`, `GET /feed/following` (auth), `GET /hashtags/{tag}/posts`,
  `GET /post` (filters: `owner_id`, `hashtag`, dimension/byte/frame/color ranges, `file_format[]`, `kind[]`,
  `base[]`,`size[]`, `sort`,`order`). All cursor-paginated → `{ items, next_cursor }`.
- Post: `GET /p/{sqid}`; `POST /post/{id}/view`; downloads `GET /d/{sqid}` · `/d/{sqid}.{ext}` · `/d/{sqid}/upscaled`.
- Reactions: `GET /post/{id}/reactions`; `PUT|DELETE /post/{id}/reactions/{emoji}`; `GET /post/{id}/reaction-users`.
- Comments: `GET /post/{id}/comments?view=tree|flat`; `POST /post/{id}/comments`;
  `PATCH|DELETE /post/comments/{cid}`; `PUT|DELETE /post/comments/{cid}/like`; `GET /post/comments/{cid}/like-users`.
- Profiles: `GET /user/u/{sqid}/profile`; `POST|DELETE /user/u/{sqid}/follow`; `GET …/followers`, `…/following`,
  `…/reacted-posts`, `…/highlights`; gallery via `GET /post?owner_id={user_key}`.
- Search: `GET /search?q&types[]`; `GET /user/browse?q&sort`; `GET /hashtags`, `/hashtags/stats`, `/hashtags/top`.
- Notifications: `GET /social-notifications/?cursor&unread_only`; `GET …/unread-count`; `POST …/mark-read`,
  `…/mark-all-read`; `DELETE …/{id}`.

**Confirmed Post shape** (from `GET /post/recent`): `id`(int), `storage_key`, `public_sqid`, `kind`, `title`,
`description?`, `hashtags[]`, **`art_url`** (full display URL — use directly), `width`,`height`,`frame_count`,
`unique_colors`, `transparency_actual`,`alpha_actual`, `created_at`, `promoted`,`promoted_category`,
**`owner`** {`user_key`,`public_sqid`,`handle`,`avatar_url`,`tagline`,`reputation`,`badges[]`},
**`reaction_count`**, **`comment_count`**, **`user_has_liked`**, **`files`** [{format,file_bytes,is_native}],
`license`{identifier,title,canonical_url,badge_path}. Page carries opaque `next_cursor`.

---

## 3. Modules

### models/ (`lib/club/models/`)
- `page.dart` — `Page<T> { List<T> items; String? nextCursor }` + `Page.fromJson(json, T Function(Map) item)`.
- `post.dart` — `Post`, `PostOwner`, `PostFile`, `License`. Display image = `art_url`. `vaultUpscaledUrl` helper
  → `{apiBase}/d/{sqid}/upscaled` for crisp static display (fallback to `art_url`).
- `reactions.dart` — `ReactionTotals { Map<String,int> totals; Set<String> mine; ... }`; `kReactionEmojis`
  const = `['👍','❤️','🔥','😊','💎']` (the curated set; SPEC-CLUB §12).
- `comment.dart` — `Comment {...}`; helper to assemble a flat list into a depth-≤2 tree.
- `user_profile.dart` — `UserProfile` (user + tagBadges + stats + isFollowing + highlights).
- `club_notification.dart` — `ClubNotification` (type, read, actor, content sqid/title/artUrl, emoji?, preview?).
- `search_results.dart` — tagged union (users/posts/playlists); `hashtag.dart` — `HashtagStat`.

### api/ (`lib/club/api/`) — domain classes over `ClubApiClient.dio`
- `feed_api.dart`, `post_api.dart`, `profile_api.dart`, `search_api.dart`, `notifications_api.dart`.
  Each maps `DioException`→`ClubError` and returns typed models.

### state/ (`lib/club/state/`) — Riverpod
- `paged.dart` — generic `PagedState<T>` + `PagedNotifier<T>` (refresh / loadMore via a `fetchPage(cursor)`
  callback; tracks `items`, `nextCursor`, `loading`, `error`, `atEnd`).
- `feed_providers.dart` — recent/promoted/following/hashtag/owner feeds as `PagedNotifier<Post>`.
- `post_providers.dart` — `postDetailProvider(sqid)` (FutureProvider.family); `reactionsProvider(postId)`
  (StateNotifier, optimistic); `commentsProvider(postId)`.
- `profile_providers.dart` — `profileProvider(sqid)`; follow toggle (optimistic on the profile + a refresh).
- `notifications_providers.dart` — `unreadCountProvider` (polls every 60 s while foregrounded) + a
  `notificationsProvider` (paged).

### ui/ (`lib/club/ui/`)
- `club_home_page.dart` — the social hub: tabbed feeds (Recent/Recommended/Following) + actions (Search,
  Notifications w/ unread badge, Account). Entry from the editor AppBar.
- `widgets/feed_grid.dart` — paginated square grid (`Image.network(art_url)`, infinite scroll) → detail.
- `artwork_detail_page.dart` — viewer + counts + reactions bar + comments + owner/follow + download/share.
- `widgets/reactions_bar.dart`, `widgets/comments_section.dart`.
- `profile_page.dart` — header + Gallery/Favourites tabs + Highlights + follow.
- `search_page.dart` — Artworks/Users/Hashtags tabs.
- `notifications_page.dart` — list + mark-all-read.

### App wiring
- Editor AppBar: the C0 account icon becomes the **Club hub** entry (`Icons.public`) → `ClubHomePage`; account
  is reachable from the hub. (Keeps one entry point.)
- Image caching: rely on Flutter's default `Image.network` cache for v1 (a dedicated disk cache is a later
  optimization).

---

## 4. Build order (commit per step)

1. Plan (this file) + self-review.
2. `models/` + parsing tests (Page cursor, Post, reactions, comment tree, profile, notification).
3. `api/` domain classes + Riverpod providers wiring.
4. `state/` paged notifier + feed/detail/reactions/comments/profile/notifications providers.
5. `ui/`: ClubHomePage + feed grid + nav from the editor.
6. `ui/`: artwork detail + reactions bar + comments section.
7. `ui/`: profile + search + notifications.
8. analyze + test + Android build; plan update; final C1 commit.

## 5. Tests (Tier-1)

- `page_test` — `Page.fromJson` parses items + `next_cursor`; null cursor → `atEnd`.
- `post_test` — parse the real recent-feed JSON fixture; owner/files/license; counts; `user_has_liked`.
- `reactions_test` — totals + `mine`; the curated emoji set.
- `comment_tree_test` — flat→tree assembly (depth ≤2; deleted-with-children kept as placeholders).
- `paged_notifier_test` — loadMore appends + advances cursor; `atEnd` when cursor null; refresh resets.
- `club_notification_test` — type/read/actor/content parsing.

## 6. Risks / decisions

- **Display images:** use `art_url` directly (the server returns a full URL; Flutter renders animated WebP/GIF).
  For large hi-dpi static display the `/d/{sqid}/upscaled` WebP is an optional enhancement; not required for C1.
- **Signed-out browsing:** Recent/promoted/detail are public; the app shows them signed-out but routes
  engagement (react/comment/follow) to sign-in. `/feed/following`, `/search`, notifications require auth.
- **`/feed/following` & comments pagination:** server may return `next_cursor: null` (not yet implemented) →
  `PagedNotifier` treats null as `atEnd` (single page). No client breakage.
- **Reactions are add/remove (not toggle), ≤5/user:** optimistic UI reflects the user's `mine` set; a 409
  (`reaction_cap_reached`) rolls back with a toast.
- **View registration** is fire-and-forget, debounced (server limit 1/3 s); never blocks the UI.
- **Notifications real-time** is deferred to C5; C1 polls `unread-count` (60 s) — documented as interim.
- **`owner_id` for gallery** uses the owner's `user_key` (UUID), while profiles use `public_sqid` — both come
  from the profile/post payloads; don't confuse them.

---

## Progress

- [x] Plan written + self-reviewed (response shapes confirmed via curl)
- [x] models/ + parsing tests (Page, Post, ReactionTotals, Comment tree, ClubNotification, UserProfile)
- [x] api/ domain classes (feed/post/profile/search/notifications) + api_providers
- [x] state/ paged notifier + providers (feeds, post detail/reactions/comments, profile, notifications)
- [x] ui/ hub + feed grid + nav (ClubHomePage tabs; FeedGrid; editor AppBar → hub)
- [x] ui/ artwork detail + reactions + comments (+ hashtag feed page; share=copy link)
- [x] ui/ profile + search + notifications
- [x] analyze + test + Android build green — **C1 code-complete**; live device smoke remains (user)

> Deferred polish within C1 (functional without them): profile Favourites/Highlights tabs
> (gallery shipped), inline follow on the detail page (follow lives on the profile), and
> richer downloads/share (copy-link shipped; byte download is C2-adjacent).

### Notes / findings
- **Verification:** `flutter analyze` clean for lib/club; **23 tests** pass (models + paged notifier);
  `flutter build apk --debug` (JBR 21) green. Live device smoke is the user's step.
- Confirmed shapes (curl, dev): `reactions` = `{totals:{emoji:n}, authenticated_totals, anonymous_totals,
  mine:[emoji]}`; `comments` = `Page` `{items, next_cursor}`; `profile` = user fields + `tag_badges`
  [{badge,label,icon_url_16}] + `stats` {total_posts, total_reactions_received, total_views, follower_count}
  + `is_following` + `is_own_profile` + `highlights` (list of Post).
- `Post.art_url` is a full URL (dev → `vault-dev.makapix.club/...`); render directly. No env URL building needed.
- `/search` is auth+trigram (shape not cur`l`-able without a token) → modeled defensively; verify on device.
