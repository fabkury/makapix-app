# UGC safety (app) — Implementation plan

Implements the app side of **UGC safety** (content reporting, user blocking,
moderation contact, first-run rules acceptance) against the frozen server
contract v1 (2026-07-06): `reference/makapix-club/docs/ugc-safety/API-CONTRACT.md`,
kickoff message `reference/makapix-club/message/0001-server-ugc-safety-kickoff.md`.
App-side decisions in `DECISIONS.md` (A1–A18 here; D1–D26 in the server repo).

These are the store-compliance features: Apple App Review Guideline 1.2 and
Google Play's UGC policy require a content-report mechanism, a way to block
users, a blocked-users management screen, a published moderation contact
(`acme@makapix.club`), and *agreed-to* content rules.

## Contract essentials (recap)

- **Feature gate:** `GET /v1/config` gains a `moderation` block — presence of
  the key is the gate (dev key = dev go signal; prod key = launch signal).
  Carries `report_reasons` (code+label list, may grow — tolerate unknown
  codes), `contact_email`, `guidelines_url`, `moderation_policy_url`,
  `max_blocks_per_user`. Render labels from config, never hardcode.
- **Report:** `POST /v1/report` — auth **optional** (send bearer when signed
  in). Body `{target_type: post|comment|user, target_id, reason_code,
  notes? ≤2000}`. Target ids (D9): post → **decimal integer id as string**;
  comment → **UUID**; user → **`public_sqid`**. `201` → Report object
  (ignore `reporter_handle`/`mod_notes`). Errors: `not_found` 404 ·
  `validation_error` 422 · `rate_limited` 429 (logged-in 10/h; anonymous
  5/h + 20/day per IP — operational values). 429 copy: "You're reporting too
  fast — try again later, or email acme@makapix.club" (email from config).
  Duplicate reports are accepted.
- **Block:** `POST /v1/user/u/{public_sqid}/block` → 204 idempotent;
  `DELETE` same → 204; both auth-required. Errors: `bad_request` 400
  (self-block) · `not_found` 404 · `block_cap_reached` 409 ·
  `unauthorized` 401. `GET /v1/me/blocks` → cursor-paginated
  `{items: [{public_sqid, handle, avatar_url, blocked_at}], next_cursor}`.
- **Server-side effects (free):** blocked users vanish from the blocker's
  list surfaces (feeds, search, comment threads, who-reacted, notifications);
  follows removed both directions at block time. Aggregate reaction counts
  NOT adjusted (D13). Direct fetches (post by sqid, profile by sqid) still
  work (D14).
- **Client must handle:** profile field `is_blocked_by_viewer: boolean`
  (always present; `false` logged out) → blocked state + Unblock, not a fake
  404. **`403 blocked`** can come back from any interaction POST (comment,
  reply, reaction, comment-like, follow) in either block direction.
- **Notifications:** `new_report` (to moderators/owner, throttled 6 h/target)
  and `report_resolved` (to the logged-in reporter). Delivered like existing
  types; unknown types already fall back generically.
- **Rules acceptance (D26/§8.6):** gate first run on accepting the rules at
  `guidelines_url`, with zero-tolerance wording.

## Scope

**In:** config discovery (`moderation` block) · `Report`/`BlockedUser` models
· `is_blocked_by_viewer` on profiles · `SafetyApi` + provider ·
`ClubError.isBlocked` · full-screen `ReportPage` reachable from post kebab /
comment row / profile menu (all logged-out capable) · post-report "Also
block" offer · profile Block/Unblock + blocked profile state ·
`BlockedUsersPage` in Settings · graceful `403 blocked` handling at every
interaction site · two new notification cases · first-run rules gate ·
Settings community/contact section · `url_launcher` dependency · unit tests ·
docs/STATUS updates · reply `0002` to the server team.

**Out (explicitly):** moderator queue UI (`GET/PATCH /v1/report` — website
handles moderation; the app's `new_report` notification just points there) ·
client-side content filtering (server-side per contract §5) · playlist report
targets (D6/A14) · push/FCM (no client exists — A15) · anonymous composition
(the app has never offered it; D16 is website-only from this client) ·
website/About-page changes (server team's side).

---

## Changes, file by file

### 1. Config model — `app/lib/club/models/server_config.dart`

New classes, mirroring the `MkpxRules` style:

```dart
class ReportReason {
  final String code;
  final String label;
  const ReportReason({required this.code, required this.label});
}

/// UGC-safety capability from `GET /config` → `moderation`. Nullable on
/// `ClubServerConfig` — absent key = feature off everywhere (contract §1).
class ModerationRules {
  final List<ReportReason> reportReasons;
  final String contactEmail;
  final String guidelinesUrl;
  final String moderationPolicyUrl;
  final int maxBlocksPerUser;
  // fromJson: defensive per-field defaults (contactEmail
  // 'acme@makapix.club', maxBlocksPerUser 1000, urls '') but NO
  // fromJson(null) → instance: the block itself must be present.
}
```

- `ClubServerConfig` gains `final ModerationRules? moderation;` — nullable,
  **no default** (A5). Parse only when the key is present. Getter
  `bool get moderationEnabled => moderation != null;`. `fallback` keeps
  `null`.
- Reasons parse in server order; unknown codes flow through untouched (A6).
- **A present block with a missing or empty `report_reasons` list parses as
  absent** (`moderation = null`, A18) — a report form whose submit can never
  enable is worse than feature-off (review R-extra).

### 2. Models — new `app/lib/club/models/report.dart`, `blocked_user.dart`

- `Report`: `id, targetType, targetId, reasonCode, notes, status,
  createdAt` — parsed from the 201 body. The app only needs it for
  confirmation + tests; ignore `reporter_handle`/`mod_notes`/`action_taken`.
- `BlockedUser`: `publicSqid, handle, avatarUrl, blockedAt` +
  `fromJson` — feeds `Page<BlockedUser>.fromJson(j, BlockedUser.fromJson)`
  (existing `Page<T>` in `models/page.dart`).
- New `ReportTarget` (A11) in `app/lib/club/models/report.dart`: pure value
  class `{String type, String id, String label, String? offenderSqid,
  String? offenderHandle}` with factories:
  - `ReportTarget.post(Post p)` → `('post', p.id.toString(),
    '“${p.title}”', p.owner.sqid, p.owner.handle)`
  - `ReportTarget.comment(Comment c)` → `('comment', c.id,
    'comment by @${c.author?.handle ?? 'guest'}', c.author?.sqid,
    c.author?.handle)` — "guest" matches how the comments UI already renders
    anonymous authors (`comments_section.dart:141`; review R10a)
  - `ReportTarget.user(UserProfile u)` → `('user', u.sqid,
    '@${u.handle}', u.sqid, u.handle)`
  The D9 id-format mapping lives only here.

### 3. Profile model — `app/lib/club/models/user_profile.dart`

- `UserProfile` gains `final bool isBlockedByViewer;` parsed
  `(j['is_blocked_by_viewer'] as bool?) ?? false` — absent field (old
  server) → `false`, so pre-flip behavior is unchanged.
- `UserProfile.copyWith` (`user_profile.dart:98`) must carry the new field —
  the optimistic `toggleFollow` path rebuilds profiles through it (review R7).

### 4. Errors — `app/lib/club/models/club_error.dart`

- Add `bool get isBlocked => status == 403 && code == 'blocked';` (A8).
- Add the shared copy constant (same file, or alongside):
  `const kBlockedInteractionMessage = "You can't interact with this user.";`
  — direction-neutral by design (D11).

### 5. API — new `app/lib/club/api/safety_api.dart` (A7)

```dart
/// User-facing UGC-safety endpoints (report + block; contract ugc-safety v1).
/// Distinct from the moderator-role ModerationApi. Report works logged-out:
/// the client attaches the bearer only when a session exists.
class SafetyApi {
  final ClubApiClient client;
  SafetyApi(this.client);

  Future<Report> report(ReportTarget t,
          {required String reasonCode, String? notes}) =>
      client.guard(() async {
        final resp = await client.dio.post('/report', data: {
          'target_type': t.type,
          'target_id': t.id,
          'reason_code': reasonCode,
          'notes': ?notes,          // omits the key only on null —
        });                         // callers pass trimmed-or-null (R10b)
        return Report.fromJson((resp.data as Map).cast<String, dynamic>());
      });

  Future<void> block(String sqid) =>
      client.guard(() => client.dio.post('/user/u/$sqid/block'));
  Future<void> unblock(String sqid) =>
      client.guard(() => client.dio.delete('/user/u/$sqid/block'));

  Future<Page<BlockedUser>> blocks({String? cursor}) => client.guard(...);
}
```

- Provider `safetyApiProvider` in `app/lib/club/state/api_providers.dart`
  (template: `moderationApiProvider`, line 35).

### 6. State — new `app/lib/club/state/safety_providers.dart`

- `blockedUsersProvider` — `PagedNotifier<BlockedUser>` over
  `SafetyApi.blocks`, `autoDispose`, watching `currentUserSubProvider` so an
  account switch resets it (template: `notificationsFeedProvider`,
  `notifications_providers.dart:46`).
- Two small action helpers used by profile page / blocked list / report
  offer, so invalidation lives in one place:
  `Future<void> blockUser(WidgetRef ref, String sqid)` and `unblockUser` —
  call the API then `ref.invalidate` the profile provider (for that sqid),
  the feed providers, and `blockedUsersProvider`. Comment threads and search
  refetch on next open (their providers are per-post / per-query); a note in
  the manual matrix verifies freshness expectations. No client-side
  filtering (A9).

### 7. Report page — new `app/lib/club/ui/report_page.dart` (A2)

`ReportPage({required ReportTarget target})`, pushed with
`Navigator.push(MaterialPageRoute(...))` from all three entry points. Works
signed-out (no auth gate anywhere in the flow).

Layout (top → bottom):

1. `AppBar(title: Text('Report'))`.
2. Target line: "Reporting ‹target.label›" (one line, ellipsized).
3. Reason list: `RadioListTile<String>` per `ReportReason` from
   `ref.watch(serverConfigProvider).valueOrNull?.moderation` (A6) — server
   order, none preselected.
4. Notes: multiline `TextField`, `maxLength: 2000`, label
   "Anything else we should know? (optional)". Submitted as
   `notes.trim().isEmpty ? null : notes.trim()` so the key is omitted for
   blank notes (same fix as mod-hashtags T3; review R10b).
5. A small footer: "See the community rules" → `guidelinesUrl`, and
   "Questions? Email ‹contactEmail›" (`mailto:`) — both via `url_launcher`.
   The footer doubles as the **signed-out-reachable published moderation
   contact** (review R3: Settings is signed-in-only in this app).
6. Submit `FilledButton` — disabled until a reason is selected and while the
   POST is in flight (spinner in the button).

**On 201:** show a confirmation `AlertDialog` in-page — title "Report sent",
body "Thanks — a moderator will review it." (This is the contract's
"confirmation toast on 201", upgraded to a dialog so it can double as the
block-offer surface — noted in the `0002` reply.) Actions: `Done` (pops
dialog + page) and, **only when applicable** (A3: signed-in ∧
`offenderSqid != null` ∧ offender ≠ self ∧ not already-blocked-known),
`Block @handle` — which calls `blockUser(...)`, snackbars "Blocked @handle",
and pops both. Block-offer failures surface via the block error mapping (§9)
without re-showing the report UI (the report itself succeeded).

**Error mapping** (branch on `ClubError.code`/status, never message):

| condition | behavior |
|---|---|
| `rate_limited` / 429 | Inline error: "You're reporting too fast — try again later, or email ‹contactEmail›." (contract copy; email interpolated from config) |
| `not_found` / 404 | "This content is no longer available." + pop the page |
| `validation_error` / 422 | Server `message` verbatim (normally pre-blocked client-side) |
| network/timeout | "Could not send the report — check your connection and try again." (stay on page, state intact) |
| anything else | Generic retry copy, stay on page |

### 8. Entry points

**Post detail — `app/lib/club/ui/artwork_detail_page.dart`.** Extend
`_overflowMenu` (line 383):

- `final modRules = ref.watch(serverConfigProvider).valueOrNull?.moderation;`
  (`ref.watch`, not `read` — same loading/fallback semantics as the existing
  `modEnabled` at line 388).
- `final showReport = modRules != null && !post.isPlaylist && !_isOwner(post);`
  (A14, A16; logged-out → `_isOwner` false → visible).
- The kebab now renders when **any** of mkpx / mod-hashtags / report apply —
  for signed-out viewers that means the report entry alone. New item
  `'report'` → `Icons.flag` + "Report post…", divider-separated from the
  other groups; `onSelected` pushes
  `ReportPage(target: ReportTarget.post(post))`.

**Comments — `app/lib/club/ui/widgets/comments_section.dart`.** In `_tile`
(line 124), append to the `_miniBtn` action row (lines 149–159):
`if (modRules != null && !isOwn && !c.deleted) _miniBtn('Report', ...)` →
pushes `ReportPage(target: ReportTarget.comment(c))` (A16, A17). Anonymous
comments included (their UUID is the target). `isOwn` is already computed
per-tile; signed-out viewers see Report on every non-deleted comment.

**Profile — `app/lib/club/ui/profile_page.dart`.** The `AppBar` (line 27)
gains `actions: [PopupMenuButton<String>]`, rendered when
`moderationEnabled && !profile.isOwnProfile` (own profile: no menu at all,
A16):

- "Report user…" (always, incl. signed-out) →
  `ReportPage(target: ReportTarget.user(profile))`.
- Signed-in: "Block @handle…" (when `!profile.isBlockedByViewer`) or
  "Unblock @handle" (when blocked).

The menu derives from the **resolved** profile —
`ref.watch(profileProvider(sqid)).valueOrNull` — and is hidden while
loading/on error (the AppBar builds before the fetch completes; review R6).
Ownership uses the existing server-authoritative `profile.isOwnProfile`
field (`user_profile.dart:57`), not a re-derived sub comparison (review R7).

### 9. Blocking — `profile_page.dart` + `state/safety_providers.dart`

**Block action.** Confirm `AlertDialog`: "Block @handle? They won't be able
to comment on your posts, react to them, or follow you — and you won't see
their content. You can unblock them anytime in Settings → Blocked users."
`Cancel` / `Block`. On confirm → `blockUser(...)` (§6) → snackbar
"Blocked @handle." The profile provider invalidation re-renders the page in
its blocked state.

**Blocked profile state (A9).** When `profile.isBlockedByViewer`: keep the
header (avatar + handle + counts), replace the follow button and the artwork
grid with a banner — `Icons.block`, "You've blocked @handle. They can't
interact with you, and you won't see their content." + `Unblock` button
(direct action, no confirm — low risk) → `unblockUser(...)` → snackbar +
re-render normal profile.

**Block error mapping** (shared by profile, blocked list, report offer):

| `code` / status | copy |
|---|---|
| `block_cap_reached` / 409 | "You've reached the limit of ‹maxBlocksPerUser› blocked users." (from config) |
| `not_found` / 404 | "User not found." |
| `unauthorized` / 401 | existing session-expired handling |
| `bad_request` / 400 | unreachable (self-block UI is hidden); fall through to generic |
| network / else | "Could not update the block — try again." |

### 10. `403 blocked` at interaction sites (A8)

Map `e.isBlocked → kBlockedInteractionMessage` in each controller's
`on ClubError catch`, at **all five** interaction sites (review R4):

1. **Detail-page reaction** — `ReactionsController.toggle`
   (`app/lib/club/state/post_providers.dart`; error surfaces via snackbar at
   `reactions_bar.dart:33`).
2. **Feed-grid like** — `GridLikesController.toggle`
   (`post_providers.dart:114`; surfaces at `feed_grid.dart:153`) — a real
   blocked-direction path (a blocked user liking the blocker's post from
   Featured).
3. **Comment create / reply** — composer error path in
   `app/lib/club/ui/widgets/comments_section.dart`.
4. **Comment like** — `CommentsController.toggleLike` currently **swallows
   every error** (`catch (_) {}`, `post_providers.dart:229–239`) and its
   call site is fire-and-forget. Change it to
   `on ClubError catch (e)` and surface the blocked case (snackbar via a
   result/callback); other errors stay silent as today — targeted change,
   no behavior shift beyond the contract requirement.
5. **Follow/unfollow** — `toggleFollow` in
   `app/lib/club/state/profile_providers.dart` (surfaces at
   `profile_page.dart:149`).

No retries, no special recovery: the optimistic-revert paths these
controllers already have are correct (the server refused; state rolls back).

### 11. Blocked-users screen — new `app/lib/club/ui/blocked_users_page.dart` (A10)

- `ListView.separated` over `blockedUsersProvider`, pull-to-refresh, plus a
  `ScrollController` near-end listener calling `loadMore()` — the in-repo
  load-more idiom is `FeedGrid`'s (`feed_grid.dart:36–41`), **not** the
  notifications page, which only ever shows page 1 (review R5).
- Row: avatar (`HandleAvatar` idiom) · `@handle` · "Blocked ‹date›" ·
  `Unblock` `TextButton`. Unblock → 204 → remove the row from local paged
  state; `PagedNotifier.state` is protected, so `blockedUsersProvider` uses
  a small subclass with `remove(String sqid)` (review R8). Error → snackbar
  via §9 mapping. Row tap → `ProfilePage(sqid: ...)`.
- Empty state: "You haven't blocked anyone."

### 12. Settings — `app/lib/club/ui/settings_page.dart`

Two additions, both gated on `moderationEnabled`. Settings is signed-in-only
in this app (`settings_page.dart:81` renders a sign-in prompt otherwise, and
the page is only reachable from the signed-in home menu — review R3), so
both live inside the signed-in branch:

- **"Blocked users"** `ListTile` → `BlockedUsersPage` (template: the Account
  tile, lines 87–94).
- **"Community" section**: "Community rules" → `guidelinesUrl` ·
  "Moderation policy" → `moderationPolicyUrl` · "Contact the moderators" →
  `mailto:contactEmail` — all via `url_launcher`.

**Signed-out discoverability** of the published moderation contact and rules
is carried by the surfaces signed-out users actually reach: the report
page's footer (rules link + contact email, §7) and the rules-gate page
(rules + moderation-policy links, §14). No new signed-out Settings entry
point (review R3, scale-down option).

### 13. Notifications — `app/lib/club/ui/notifications_page.dart` (A15)

- `_text` (line 74) gains:
  ```dart
  case 'new_report':
    return 'New content report — open the moderation queue';
  case 'report_resolved':
    return "Thanks — we've reviewed your report.";
  ```
- `_tile`'s shield-avatar branch (lines 59–61) generalizes to
  `const {'mod_hashtags_updated', 'new_report', 'report_resolved'}
  .contains(x.type)`.
- Tap behavior: `report_resolved` keeps the unchanged default (deep-links
  when `hasContentLink`, inert otherwise). **`new_report` is forced inert**
  (`onTap: null`) until the server team answers what its `content_sqid`
  carries — for a user-target report it would not be a post sqid, and the
  default would push a broken `ArtworkDetailPage` (review R9; question is in
  the `0002` reply).

### 14. Rules gate — new `app/lib/club/state/rules_gate.dart` + `app/lib/club/ui/rules_gate_page.dart` (A1, A12)

**Controller** (`rules_gate.dart`): `kRulesVersion = 1`; persisted key
`club.rules_accepted_version` via `shared_preferences` (pattern:
`player_providers.dart:221`). Exposes a Riverpod provider combining the
stored version + `serverConfigProvider` into a boolean — the gate is
**reactive, never blocking on the config fetch** (A12, rewritten per review
R2 — the original `pending`-splash design would have stalled every pre-flip
cold start on the 15 s config timeout and failed manual item 15):

| state | meaning → UI |
|---|---|
| `show` | not accepted (for `kRulesVersion`) ∧ config resolved with `moderation` present | the gate page |
| `passed` | everything else: accepted, or config loading, or `moderation` absent (pre-flip / offline fallback — fail-open) | proceed to Club |

Club renders immediately; when the config future resolves with the key and
the install hasn't accepted, the gate interposes (sub-second on a live
connection). One-frame-late is fine for App Review — it still blocks before
any meaningful interaction — and a pre-flip or offline server produces
**zero behavioral change**. `accept()` writes the version and flips the
state.

**Gate page** (`rules_gate_page.dart`): full-screen `Scaffold` — app
icon/title, "Community rules" heading, short body: "Makapix Club is a shared
space. We have **zero tolerance** for objectionable content or abusive
behavior — content that breaks the rules is removed and repeat offenders are
banned." · "Read the community rules" link (`guidelinesUrl`) · footnote "You
can report any content or user, and block anyone, from inside the app." ·
one primary `FilledButton`: **"Agree and continue"** → `accept()`.

**Insertion, two places** (review R1):

1. `app/lib/club/ui/club_home_page.dart` (build, before the existing
   branches at lines 181–188):

   ```dart
   if (ref.watch(rulesGateProvider) == RulesGate.show) {
     return const RulesGatePage();
   }
   // existing: if (!auth.isSignedIn) return const ClubWelcomePage(); …
   ```

   This covers the Club pillar's nested navigator root (welcome, feeds,
   detail, contribute) for signed-in and signed-out users.

2. `app/lib/club/ui/publish_page.dart` — the same check at the top of the
   build. The editor's "Post to Club" does **not** switch pillars: it pushes
   `PublishPage` directly onto the editor navigator
   (`editor_page.fileio.dart:159–185`), so without this second check the
   publish flow would bypass the gate entirely (review R1 — the plan's
   original "verify during implementation" assumption was wrong). When the
   gate is `show`, `PublishPage` renders the gate content; on accept it
   continues into the publish form. Double-gating for the in-pillar
   contribute path is harmless (`passed` renders normally).

The editor pillar itself stays ungated (A1) — it exposes no UGC.

### 15. Dependency — `app/pubspec.yaml`

- Add `url_launcher: ^6.3.0` (A13). Verify the Windows build (it's a
  federated plugin with a Windows implementation; no ATL-style gotchas
  known).

### 16. Docs

- `SPEC-CLUB.md`: §22 (reporting) updated to the v1 contract (new reason
  codes from config, optional auth, block endpoints, `moderation` config
  block, `is_blocked_by_viewer`, `403 blocked`, the two notification types);
  §29 parity matrix rows for report/block/blocked-list/rules-gate.
- `STATUS.md`: new Club rows (ugc-safety).
- `CLAUDE.md`: no change needed (no new build steps).
- `docs/ugc-safety/PROGRESS.md`: created during implementation, tracks the
  checklist.
- Server repo (`reference/makapix-club`, branch `develop`): commit
  `message/0002-app-ugc-safety-ack.md` (Appendix A) and push.

---

## Tests (`app/test/ugc_safety_test.dart`, pure unit — no engine, no network)

1. **Config discovery** — `moderation` present → reasons parsed in order
   (codes + labels), `contactEmail`/urls/`maxBlocksPerUser` read; unknown
   reason codes pass through; absent key → `moderation == null`,
   `moderationEnabled` false; **present block with missing/empty
   `report_reasons` → `null`** (A18); `fallback` off; missing sub-fields →
   defensive defaults.
2. **Models** — `Report.fromJson` (201 body verbatim from the contract);
   `BlockedUser` + `Page<BlockedUser>` paging shape;
   `UserProfile.isBlockedByViewer` present/absent(→false) **and retained
   through `copyWith`** (R7).
3. **`ReportTarget`** — the D9 mapping: post → decimal string of `post.id`;
   comment → UUID; user → sqid; offender extraction incl. anonymous comment
   (`offenderSqid == null`) and label shapes.
4. **`ClubError.isBlocked`** — 403+`blocked` true; 403+`forbidden` false;
   401 false; plus existing envelope parsing untouched.
5. **Error copy helpers** — 429 report copy interpolates `contactEmail`;
   409 block copy interpolates `maxBlocksPerUser`; blocked-interaction
   constant is direction-neutral.
6. **Rules gate logic** — with `SharedPreferences.setMockInitialValues`:
   unaccepted + config-with-moderation → `show`; unaccepted +
   config-without → `passed` (fail-open); unaccepted + config still
   loading → `passed` (reactive, never blocks — R2); accepted v1 →
   `passed`; stored version < `kRulesVersion` → `show` again.
7. **Notification copy** — `new_report` / `report_resolved` strings; unknown
   type still falls back; shield-avatar type set contains all three types.

Gates: `flutter test` and `flutter analyze` clean; `cargo` untouched (Dart-
only Club work; the engine stays network-free).

## Manual verification (dev, after the server's "live on dev" message)

Build with `-Dev`. Needs: a fresh install (or cleared app data), two regular
accounts (A, B), and a moderator account on development.makapix.club.

1. **Rules gate:** fresh install → Club renders, gate interposes as soon as
   the config resolves (sub-second; reactive by design, R2); "Read the
   community rules" opens the dev About page; Agree → welcome/feeds;
   relaunch → no gate. Editor pillar reachable without passing the gate.
2. **Logged-out report — post:** featured grid → detail → kebab (report entry
   only) → full-screen page → reasons match dev config → submit → 201 →
   "Report sent" dialog **without** a block offer.
3. **Logged-out report — comment & user:** per-comment Report mini-button;
   profile ⋮ → "Report user…". Both submit fine without auth.
4. **Logged-in report + block offer:** report B's post as A → dialog offers
   "Block @B" → tap → B's profile shows blocked state; Settings → Blocked
   users lists B.
5. **Rate limit:** fire >10 quick reports (or >5 anonymous) → 429 copy with
   the contact email, page state preserved. **Run this one last** — it
   consumes the dev account/IP report budget for a real hour (review).
6. **Block effects (A blocks B):** B's posts gone from A's feeds + search;
   B's comments (and their replies) gone from threads A views; mutual
   follows removed; **both directions**: B → A comment/react/follow all
   refuse with the neutral blocked message; A can still direct-open B's post
   (D14).
7. **Blocked profile:** A opens B's profile → header + banner + Unblock;
   unblock → normal profile returns; re-block from the ⋮ menu works.
8. **Blocked-users screen:** paging (if >1 page), per-row unblock removes the
   row, row tap opens the profile, empty state after unblocking all.
9. **Notifications:** moderator account receives `new_report` (shield tile,
   ≤1 per target per 6 h); after resolving on the website, reporter A
   receives `report_resolved`.
10. **Self-guards:** no report entry on own post/comment/profile; no block on
    own profile.
11. **Playlist post:** no report entry (A14).
12. **Deleted/anonymous comments:** deleted → no Report; anonymous → Report
    present, no block offer after submitting.
13. **Windows build:** same flows on desktop — kebab hover, report page
    layout, `url_launcher` opens the browser/mail client.
14. **Publish path:** fresh install → editor → "Post to Club" before ever
    accepting the rules → `PublishPage` renders the gate first (R1);
    accepting there continues into the publish form, and the Club pillar no
    longer gates afterwards.
15. **Prod build (default, key absent):** zero new UI anywhere — no gate, no
    report/block entries, no Settings section; app byte-identical in
    behavior to today.

## Rollout

1. Implement + unit tests **now** (everything is contract-driven; only the
   manual matrix needs the dev server).
2. Commit this plan folder; commit + push
   `message/0002-app-ugc-safety-ack.md` to the server repo's `develop` (A4).
3. When the server team announces the `moderation` key on dev: build
   `./build_android.ps1 -Dev -Install` (+ `./build.ps1 -Dev -Run` for
   Windows) and run the manual matrix.
4. After the matrix passes: rebuild for prod (default, no `-Dev`) and ship
   via `release_android.ps1` on the normal internal→alpha track; coordinate
   the joint prod flip with the server team (message exchange). Order-safe
   either way (config-key gate): app-first → all safety UI stays hidden
   until the key appears on prod; server-first → old builds ignore the new
   config key and render unknown notification types generically.
5. Update the Play Console content questionnaire (UGC declarations) when the
   prod flip lands; Apple's questionnaire comes with the future iOS release.

## Risks / notes

- **Gate-vs-config startup:** the gate is reactive — Club renders
  immediately and the gate interposes when `serverConfigProvider` resolves
  with the `moderation` key (A12, per review R2). Nothing ever blocks on the
  config fetch: pre-flip and offline launches are behaviorally identical to
  today, and an unaccepted install re-arms on every launch until accepted.
  The brief pre-gate flash of the welcome/feed is deliberate and disclosed
  in the `0002` reply.
- **`new_report` deep-link follow-up:** once the server team answers the
  payload question, linking the tile to the website's moderation queue via
  `url_launcher` is a cheap improvement (the app has no queue UI by design).
- **Kebab visibility widens:** the detail-page kebab becomes visible to
  everyone (report entry) once the key is live — previously owner/moderator
  only. Menu builder conditions must keep the existing mkpx/mod entries
  exactly as they are (manual item: a moderator-owner sees all three groups
  in one menu).
- **Comment rows gain a button:** the Report mini-button appears on every
  non-own, non-deleted comment. Same `_miniBtn` styling keeps the noise low;
  if it reads too loud in practice, demoting it to a per-comment ⋮ is a
  contained follow-up (the push target stays `ReportPage`).
- **Stale caches after block:** feeds/profile are invalidated on block;
  comment threads, search results, and who-reacted lists refetch on next
  open. A just-blocked user's content can linger on an **already-open**
  screen until refresh — accepted (server is the source of truth; no
  client-side filtering by design, A9).
- **`is_blocked_by_viewer` only exists on full profile responses** — cards
  and comment tiles don't carry it, so "already blocked" can't gray out menu
  entries elsewhere; the block POST being idempotent (204) makes duplicate
  blocks harmless.
- **`url_launcher` on Windows** is the only new native-plugin surface; if it
  drags in a build issue, the fallback is copying the URL/email to the
  clipboard with a snackbar (one small helper, same call sites).
- **Anonymous reports get no `report_resolved`** (D5) — no app handling
  needed; the reporter simply never hears back.
- The server may tune rate limits without a version bump (D23) — the app
  hardcodes no limit values, only the 429 copy.

---

## Review round (2026-07-06)

An independent agent reviewed this plan with fresh eyes (soundness vs the
frozen contract, production-readiness, fit for the single-VPS backend and
this codebase's conventions), verifying every cited file/line against the
code. Verdict: **no blockers**; sound and appropriate, production-grade
after five should-fixes. All findings were incorporated (marked `R*` above):

- **R1** — the editor's "Post to Club" pushes `PublishPage` on the *editor*
  navigator and would have bypassed the rules gate; the gate check in
  `PublishPage` is now a definite task (§14) and the `0002` reply wording
  was corrected.
- **R2** — the original `pending`-splash gate design would have stalled
  every pre-flip cold start on the config fetch (15 s offline) and failed
  manual item 15; redesigned reactive (§14, A12 rewritten).
- **R3** — Settings is signed-in-only, so the "all viewers" Community
  section was unreachable signed-out; scaled to signed-in Settings +
  contact/rules links on the report page and gate page (§7, §12).
- **R4** — the `403 blocked` site list missed the feed-grid like controller
  and `toggleLike` swallows all errors; all five sites now enumerated with
  the `toggleLike` change specified (§10).
- **R5/R8** — the blocked-list "load-more template" (notifications page)
  doesn't implement load-more; switched to the `FeedGrid` scroll-listener
  idiom + a `PagedNotifier` subclass with `remove()` (§11).
- **R6/R7** — profile menu derives from the resolved profile; ownership uses
  the existing `profile.isOwnProfile` field; `copyWith` carries the new
  field (§3, §8).
- **R9** — `new_report` tap forced inert until the payload question is
  answered (§13).
- **R10** — "guest" label parity, trim-to-null notes, dialog-as-toast note
  in the reply (§2, §5, §7).
- Reviewer extras adopted: empty `report_reasons` ⇒ feature-off (A18);
  rate-limit manual test runs last; `new_report` website deep-link noted as
  follow-up.

Nothing was disregarded.

---

## Appendix A — draft reply `0002-app-ugc-safety-ack.md` (to server repo `message/`)

> **From:** Makapix Club app team
> **To:** Makapix Club server team
> **Date:** 2026-07-06
> **Re:** 0001 UGC safety kickoff — contract ack + answers (ugc-safety)
>
> 1. **Contract v1 acked** — no objections; building against it as frozen.
>    Two non-blocking clarifications and one FYI:
>    (a) *Playlists:* per D6 we hide the report affordance on playlist posts
>    (the owner remains reportable from their profile). If you intend
>    playlist posts to count as `target_type: "post"`, say so and we drop
>    the exclusion — the code path is shared.
>    (b) *`new_report` payload:* which content fields does it carry
>    (`content_sqid` of the reported target?)? For a user-target report a
>    `content_sqid` would not be a post id, so until you answer we render
>    the tile generically ("New content report — open the moderation
>    queue", shield avatar) with **no tap action** — safe either way,
>    answer whenever convenient.
>    (c) *FYI:* our 201 confirmation is a dialog rather than a toast — it
>    doubles as the "Also block @handle" offer surface. Same function,
>    strictly more.
> 2. **First-run rules gate: confirmed** (D26/§8.6). A one-time full-screen
>    "Community rules" gate covers the Club pillar (signed-in *and*
>    signed-out) **and** the editor's "Post to Club" publish entry, with
>    zero-tolerance wording and a link to `guidelines_url`; acceptance is
>    versioned per-install. The rest of the editor (no UGC exposure) stays
>    reachable ungated. The gate is keyed on the `moderation` config block,
>    so it arms itself per environment on your flip. Implementation note:
>    it's reactive — the app renders normally and the gate interposes the
>    moment `/config` resolves with the key (sub-second), so it blocks
>    before any meaningful interaction without ever stalling startup; when
>    `/config` is unreachable (offline) it fails open and re-arms on the
>    next launch.
> 3. **Logged-out browsing: yes.** Signed-out users browse the promoted/
>    featured feed, open post detail pages, and read full comment threads —
>    so logged-out reporting is first-class on all three surfaces (post
>    overflow menu, per-comment action, profile menu). Note the app never
>    offers anonymous composition (comment/react require sign-in), so the
>    D16 anonymous-interaction loophole is website-only as far as this
>    client is concerned.
> 4. **Notifications:** list rendering added for `new_report` and
>    `report_resolved`. As with mod-hashtags: the app has no FCM/MQTT
>    client (polled list only), so the push copy in §6 doesn't apply to us;
>    nothing needed from you.
> 5. **ETA:** app-side code + unit tests ≈1–2 days from now; manual
>    end-to-end the day the `moderation` key is live on
>    development.makapix.club. We can join the prod flip immediately after
>    our manual matrix passes — the config-key gate makes ordering safe on
>    our side. Play Store questionnaire updates ride our next release.
