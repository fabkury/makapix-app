# Profile tabs: Reacted ⚡ (+ display-only Highlights 💎) — implementation plan

**Status: IMPLEMENTED (2026-07-07)** — data layer `5c63c1f`, UI + tests `22bb9a7`; 236 Dart tests
green, `flutter analyze` clean; on-device manual checklist pending. Revised same day after a fresh-eyes review
(11 findings, all incorporated; the pinned-sliver TabBar was replaced by the simpler
TabBar-in-body layout, killing the sliver-overlap problem outright).

Closes the "Reacted/favourites tab" gap (SPEC-CLUB §14, §29 row "Reacted/favourites tab"). The profile
page grows a Material TabBar with a collapsing header: **🖼 Gallery** (today's grid) · **⚡ Reacted**
(posts this user reacted to) · **💎 Highlights** (display-only, when present).

## Decisions (user preferences, 2026-07-07)

1. **Visibility:** the Reacted tab appears on **all profiles, but only when the viewer is signed in**.
   Signed-out viewers see Gallery (+ Highlights) only.
2. **Naming:** the tab is called **"Reacted"**, iconed ⚡. (Deviation from SPEC-CLUB §14's "Favourites"
   vocabulary — update §14/§29 wording when this ships.)
3. **UI shape:** **Material TabBar + swipeable `TabBarView`**, profile header collapsing on scroll
   (`NestedScrollView`).
4. **Scope bonus:** render the **Highlights** tab display-only from the already-parsed
   `UserProfile.highlights` — only when non-empty. Pin/unpin management stays in the C4 backlog.

## Server contract

- `GET /api/v1/user/u/{sqid}/reacted-posts` — already consumed by `ProfileApi.reactedPosts`
  (`api/profile_api.dart:29`), which tolerates either a `Page` envelope or a bare `{items:[...]}`.
- **Unknowns to tolerate, not assume:** whether the endpoint honors a `cursor` query param, and whether
  it 401s for anonymous callers. The plan sends `cursor` like the sibling `_people` helper does; a
  missing/ignored `next_cursor` simply lands as `atEnd` in `PagedNotifier` (`state/paged.dart:80`), so
  an unpaged server degrades gracefully to a single page. The signed-in-only UI gate sidesteps the
  anonymous-401 question entirely.
- Reacted items may include `kind == "playlist"` posts; tiles and the detail page already handle those.

## Changes

### 1. `api/profile_api.dart` — page-aware `reactedPosts`

Change `Future<List<Post>> reactedPosts(String sqid)` →
`Future<Page<Post>> reactedPosts(String sqid, {String? cursor})`, passing
`queryParameters: {'cursor': ?cursor}` (same idiom as `_people`). Keep the tolerant
`Page<Post>.fromJson` parse. No other callers exist today (the method is currently unused).

### 2. `state/profile_providers.dart` — `reactedFeedProvider`

```dart
/// Posts a user reacted to, keyed by the profile's public sqid. Signed-in-only by UI gate.
final reactedFeedProvider = StateNotifierProvider.autoDispose
    .family<PagedNotifier<Post>, PagedState<Post>, String>((ref, sqid) {
  ref.watch(currentUserSubProvider);   // account switch must refetch (audit 4e1ff81)
  final api = ref.watch(profileApiProvider);
  final n = PagedNotifier<Post>((cursor) => api.reactedPosts(sqid, cursor: cursor),
      onPage: precacheArtworks);
  n.loadInitial();
  return n;
});
```

Mirrors `ownerFeedProvider` (`state/feed_providers.dart:42`): autoDispose family, viewer-identity
watch, artwork precache. Placed in `profile_providers.dart` because it's keyed by profile sqid and
consumed only by the profile page. New imports needed there: `../models/post.dart`, `paged.dart`,
`../cache/artwork_cache.dart` (for `precacheArtworks`), and
`auth_controller.dart show currentUserSubProvider` (`profileApiProvider` is already imported).

**Also:** add a *silent* reload to `ProfileController` (`profile_providers.dart`) that refetches
without first flipping to `AsyncValue.loading()` — today `load()` does
(`profile_providers.dart:15`), which unmounts `_Body` into the full-screen spinner. Pull-to-refresh
and the Edit-profile return path (`profile_page.dart:283`) must use the silent variant, or the tab
selection and scroll offsets reset on every refresh/edit.

### 3. `ui/widgets/feed_grid.dart` — a `nested` mode

`FeedGrid` currently owns a `ScrollController` (load-more trigger) and wraps itself in
`RefreshIndicator`. Inside a `NestedScrollView` body the inner scrollable must instead use the
**inner** `PrimaryScrollController`, and pull-to-refresh must move to the outer edge. Add
`final bool nested;` (default `false` — zero change for the four existing call sites:
`club_home_page.dart:106`, `club_welcome_page.dart:67`, `hashtag_feed_page.dart:24`,
`profile_page.dart:188`). When `true`:

- `GridView.builder(primary: true, …)` — no own controller (`primary: true` also brings
  `AlwaysScrollableScrollPhysics`, so short-content pull-to-refresh works for free);
- load-more via `NotificationListener<ScrollNotification>` wrapping **only the grid** (so outer /
  PageView notifications never pass through it — they bubble from ancestors, not descendants),
  guarded with `n.depth == 0 && n.metrics.axis == Axis.vertical &&
  n.metrics.pixels > n.metrics.maxScrollExtent - 600`;
- skip the internal `RefreshIndicator` (both around the grid and around the empty-list `ListView`,
  which also becomes `primary: true`); the profile page owns refresh. In nested mode `onRefresh`
  (a `required` parameter) is simply unused — callers pass a no-op.

No sliver-overlap machinery is needed because nothing is pinned in the sliver header — see §4.

### 4. `ui/profile_page.dart` — the tab structure

Rework `_Body` (keeping `_header`, `_blockedBanner`, `_FollowButton`, and the
`SendTargetBinder(ChannelTarget(...))` wrapper exactly as they are):

- **Tab set** (a pure helper, unit-testable):
  `tabsFor({required bool signedIn, required bool hasHighlights})` →
  `[gallery, if (signedIn) reacted, if (hasHighlights) highlights]`.
- `DefaultTabController(length: tabs.length, key: ValueKey('$signedIn:$hasHighlights'))` — the key
  must be **value-equal across rebuilds** (a `ValueKey` on the freshly-built list would compare by
  identity and remount the whole scaffold — losing tab selection and scroll — on *every* rebuild,
  including token refreshes, since `_Body` watches `authControllerProvider`). It changes only when
  the tab set genuinely changes, rebuilding the controller cleanly (avoids the length-mismatch
  crash); losing tab selection at that moment is acceptable.
- `RefreshIndicator` around a `NestedScrollView`, with
  `notificationPredicate: (n) => n.depth == 2 || n.depth == 0` — the default `depth == 0` only sees
  the outer scrollable, so pulls on the grids (depth 2: outer → TabBarView PageView → grid) would
  never trigger refresh; keeping depth 0 lets pulls on the expanded header work too (the indicator's
  own axis check filters the horizontal PageView).
  - `headerSliverBuilder`: just `SliverToBoxAdapter(_header)` — **nothing pinned**. The `TabBar`
    lives in the body instead (below), which sidesteps the entire
    SliverOverlapAbsorber/Injector machinery a pinned sliver TabBar would force onto every tab's
    scrollable (without which the collapsed header hides the top ~48 px of each grid).
  - `body`: `Column(TabBar, Expanded(TabBarView))` — the TabBar is trivially always-visible while
    the header above it collapses, matching the chosen mockup. Tabs: 🖼 Gallery · ⚡ Reacted ·
    💎 Highlights. Each `TabBarView` child is its **own small `ConsumerWidget`** (with a
    `PageStorageKey` on its scrollable) that watches its own provider — so the reacted fetch fires
    only when the Reacted tab actually builds, not eagerly on every profile open:
    - **Gallery** — today's `FeedGrid(ownerFeedProvider(profile.userKey), nested: true)`; tap-through
      unchanged (`pagedArtworkSource(ownerFeedProvider(...), ...)`).
    - **Reacted** — `FeedGrid(reactedFeedProvider(profile.sqid), nested: true)`,
      `emptyMessage: 'No reactions yet.'`; tap-through
      `pagedArtworkSource(reactedFeedProvider(profile.sqid), reactedFeedProvider(profile.sqid).notifier)`.
    - **Highlights** — `FeedGrid` fed a synthetic
      `PagedState(items: profile.highlights, atEnd: true, initialized: true)` with no-op
      `onLoadMore`/`onRefresh`; tap-through `ArtworkFeedSource.fixed(profile.highlights)`.
  - **Refresh** = the **silent** profile reload (§2) + refresh of **only the active tab's**
    notifier, resolved via the TabController index (never `ref.read(...notifier)` on a tab that was
    never opened: on an autoDispose family that *creates* the provider — `loadInitial()` fires, then
    `refresh()` double-fetches, then the listener-less provider is disposed mid-flight, which
    asserts in debug when the notifier's state lands after dispose). Gallery refresh keeps working
    exactly as before from the user's point of view. Highlights rides along with the profile reload.
- **Blocked profile** path unchanged: header + banner, no tabs (`profile.isBlockedByViewer` branch
  stays above the tab scaffold).

### 5. Docs on ship

- `STATUS.md`: move "reacted/favourites tab" from the C4-rest ○ row to its own ✅ row.
- `SPEC-CLUB.md` §14: rename the tab vocabulary to "Reacted ⚡" (record the deviation); §29 row →
  app ✅.

## Edge cases

- **Account switch / sign-out mid-view:** `reactedFeedProvider` watches `currentUserSubProvider`
  (refetch on switch); the value-equal tab-set key remounts the controller only when the Reacted tab
  genuinely appears/disappears — never on ordinary rebuilds or token refreshes.
- **Server without cursor support:** single page, `atEnd = true`, no spinner tile — automatic.
- **401/errors on the reacted fetch:** surfaces through `PagedState.error` → `ClubErrorRetry` inside
  the grid (existing behavior).
- **Highlights present but blocked viewer:** irrelevant — blocked branch renders no tabs.
- **`autoDispose` + detail swipe:** tapping into `ArtworkDetailPage` keeps the provider alive via the
  page's `ref.watch` on `pagedArtworkSource` (same pattern as the hashtag feed / gallery today).

## Tests (pure Dart, no engine — keep Club tests engine-free)

There are **no existing Dio-mocking tests** to imitate (`app/test/` is model/logic-only and the dev
deps are just `flutter_test` + `flutter_lints`), so:

1. Parse-level tests for the reacted-posts shapes: `Page<Post>.fromJson` on a Page envelope vs a
   bare `{items:[...]}`, `next_cursor` → `Page.nextCursor` (extends the existing
   `club_models_test.dart` coverage).
2. `tabsFor(...)` helper: 4 combinations of signedIn × hasHighlights.
3. Cursor passthrough on `ProfileApi.reactedPosts`: a small **hand-rolled `HttpClientAdapter` fake**
   (plain Dio, no new dependency) that records the request URI and returns a canned page. If this
   proves disproportionate, drop it and let the manual checklist cover cursor behavior.
4. Paging behavior reuses the existing `paged.dart` tests (no change needed there).

## Verification

`flutter analyze` + `flutter test`; `./build.ps1 -Run` on Windows and `./build_android.ps1 -Install`
on the phone. Manual checklist: header collapses and re-expands; swipe between tabs; scroll position
preserved per tab; pull-to-refresh from the top of each tab; load-more in Gallery and Reacted;
signed-out → no Reacted tab; sign-in from the profile route → tab appears; account switch → reacted
content refetches; returning from Edit profile keeps the selected tab and scroll (silent reload);
opening a profile does **not** fetch reacted-posts until the Reacted tab is shown; a playlist tile in
Reacted opens without mkpx/mod/report menus; Highlights tab only on profiles that have highlights;
blocked profile unchanged.

## Out of scope

Highlights management (pin/unpin/reorder — C4 backlog), the website-field/handle-in-page profile-edit
gaps, playlists (fully deferred 2026-07-07), any server changes.
