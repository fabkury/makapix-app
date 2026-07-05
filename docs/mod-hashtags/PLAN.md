# Moderator hashtags (app) — Implementation plan

Implements the app side of **moderator hashtags** against the frozen server
contract v1 (2026-07-05): `reference/makapix-club/docs/mod-hashtags/API-CONTRACT.md`.
Decisions in `DECISIONS.md` (A1–A14 here; D1–D22 in the server repo).

## Contract essentials (recap)

- `post.mod_hashtags: string[]` — new field on every full Post object, always
  present (possibly `[]`), invariant `mod_hashtags ⊆ hashtags`. `hashtags`
  stays the effective list; nothing existing changes.
- `PUT /v1/post/{id}/mod-hashtags` with `{"hashtags": [...], "note"?: str}` —
  moderator-only **full replace** of the mod set; returns the full updated
  Post. Server normalizes (trim, strip one `#`, lowercase, dedupe); cap 16
  post-normalization; per-tag ≤64 chars. Targets must be non-deleted artwork
  posts (playlists/soft-deleted → 404). Errors: `/v1` envelope, branch on
  `error.code`: `unauthorized` 401 · `forbidden` 403 · `not_found` 404 ·
  `validation_error` 422.
- Feature discovery: `GET /v1/config` gains `max_mod_hashtags_per_post: 16`.
  **All mod-editor UI is gated on the presence of this key** (A5). Key present
  on dev = dev go signal; on prod = launch signal.
- "Moderator" = `roles` from `/auth/me` containing `moderator` or `owner`
  (site role). The app already has this: the `canModerate` getter on `ClubMe`
  (`app/lib/club/models/club_user.dart:72`), reached via
  `ref.watch(authControllerProvider).me?.canModerate ?? false`.
- Notification `mod_hashtags_updated`, diff (e.g. `+nsfw −politics`) in
  `comment_preview`.

## Scope

**In:** Post model field · config discovery · shield-marked display for
moderators + artist · merged overflow menu with "Edit mod hashtags…" · the
editor bottom sheet (monitored quick-picks, free tags, optional note) · the
notification list case · unit tests · docs/STATUS updates · reply `0002` to
the server team.

**Out (unchanged by contract §8 / N/A in app):** feed/search/filter logic
(operates on `hashtags` as today) · monitored opt-in settings · any owner
metadata-edit form (doesn't exist in the app — A12) · push/FCM (no client —
A14) · moderator bulk tooling (server D4 keeps v1 post-page-only).

---

## Changes, file by file

### 1. Model — `app/lib/club/models/post.dart`

- Add `final List<String> modHashtags;` (constructor default `const []`).
- Parse: `modHashtags: (j['mod_hashtags'] as List?)?.map((e) => e.toString()).toList() ?? const []`
  — absent field (old server, card-shaped payloads) → `[]`, matching the
  existing `hashtags` fallback style.
- Add helper `bool isModTag(String tag) => modHashtags.contains(tag);`.

### 2. Config — `app/lib/club/models/server_config.dart`

- `ClubServerConfig` gains `final int? maxModHashtagsPerPost;` — **nullable,
  no default** (A5). Parse:
  `(j['max_mod_hashtags_per_post'] as num?)?.toInt()` (no `?? 16`).
- Convenience getter: `bool get modHashtagsEnabled => maxModHashtagsPerPost != null;`.
- `fallback` (offline) leaves it `null` → editor hidden when config can't be
  fetched. Correct failure mode: against an unknown server, don't offer a PUT
  that may 404.

### 3. API — new `app/lib/club/api/moderation_api.dart` (A8)

```dart
/// Moderator-role endpoints (`roles` ∋ moderator|owner). First occupant of
/// this file; future mod actions (hide/promote) belong here too.
class ModerationApi {
  final ClubApiClient client;
  ModerationApi(this.client);

  /// `PUT /post/{id}/mod-hashtags` — full replace of the mod set (contract v1).
  /// Returns the full updated Post (source of truth for hashtags + mod_hashtags).
  Future<Post> setModHashtags(int postId, List<String> hashtags, {String? note}) =>
      client.guard(() async {
        final resp = await client.dio.put('/post/$postId/mod-hashtags', data: {
          'hashtags': hashtags,
          'note': ?note,
        });
        return Post.fromJson((resp.data as Map).cast<String, dynamic>());
      });
}
```

- Provider `moderationApiProvider` in `app/lib/club/state/api_providers.dart`,
  same pattern as `mkpxApiProvider`.
- `reason_code` is not sent in v1 (A4). Empty/whitespace note → omit the key.

### 4. Edit-state controller — new `app/lib/club/edit/mod_hashtag_edit.dart` (A13)

Pure Dart, no Flutter imports; unit-tested.

- `List<String> normalizeHashtags(Iterable<String> raw)` — trim, strip **one**
  leading `#`, lowercase, drop empties, order-preserving dedupe. Mirrors
  server D12 for preview only (A9).
- `class ModHashtagEdit` — holds the working set (initialized from
  `post.modHashtags`), the cap (from config, default 16 when the key is
  present), and exposes:
  - `bool add(String raw)` — normalize; reject empty, >64 chars, duplicates,
    over-cap; returns whether it was added (UI shows why not).
  - `void remove(String tag)`; `bool toggle(String tag)` (for monitored
    chips) — removes if present, otherwise **routes through the guarded
    `add`** so a quick-pick chip cannot push the set past the cap (review
    finding T1),
  - `bool removesMonitored(...)` — true when the pending save would drop any
    `kMonitoredHashtagTags` member present in the original set (drives the
    confirmation in §6),
  - `bool get changed` — set-inequality vs the original (order-insensitive,
    matching the server's set-based diff), so Save can stay disabled on no-op,
  - `List<String> get tags` — current working list, insertion-ordered.

### 5. Display — `app/lib/club/ui/artwork_detail_page.dart`

**Shield marker (A3, A6).** In the hashtag `Wrap` (currently
`artwork_detail_page.dart:189-204`): compute once per build
`showModMarker = viewerCanModerate || viewerIsArtist` where
`viewerCanModerate = ref.watch(authControllerProvider).me?.canModerate ?? false`
and `viewerIsArtist = _isOwner(post)` (existing helper, line 311). For each
tag with `post.isModTag(tag) && showModMarker`, render the same tappable text
prefixed by a small inline shield (`Icons.shield`, ~13px, same primary color,
inside the existing `GestureDetector` via a `Row(mainAxisSize: min)`), wrapped
in `Tooltip(message: 'Added by moderators')` (long-press on mobile, hover on
Windows). Accessibility: keep the tag text as the primary semantics label —
`Semantics(label: '#$tag, added by moderators')` with the shield icon excluded
from semantics, so a screen reader doesn't read the row as just "Added by
moderators" (review finding U6). Tap behavior unchanged (opens
`HashtagFeedPage`). Public users and signed-out viewers see plain tags — same
rendering as today.

**Persistent legend (review finding U2).** A long-press tooltip alone is
undiscoverable, and the artist's whole comprehension moment is "why is this
tag here?". When `showModMarker` and the post has ≥1 mod tag, render one
always-visible caption line directly under the hashtag `Wrap`:
`🛡 Tagged by a moderator` (small, `Colors.white38`-style, matching `_meta`'s
tone; plural-insensitive copy on purpose). Visible only to moderators and the
artist; keeps the tooltip as a secondary hint.

**Merged overflow menu (A2, A7).** Replace `_mkpxMenu` (line 343) with
`_overflowMenu(context, post)` returning at most one `PopupMenuButton<String>`
whose items aggregate:

- the two mkpx entries, under the existing condition
  (`_mkpxRules.enabled && !post.isPlaylist && _isOwner(post)`);
- `'Edit mod hashtags…'` (with a small shield leading icon), under
  `modHashtagsEnabled && canModerate && !post.isPlaylist`, where
  `modHashtagsEnabled` comes from
  `ref.watch(serverConfigProvider).valueOrNull?.modHashtagsEnabled ?? false` —
  **`ref.watch`, not `ref.read`**, so the entry appears when the config
  future resolves; null while loading / on fallback keeps it hidden (same
  pattern as `_mkpxRules` at `artwork_detail_page.dart:308`; review finding
  T4);
- a `PopupMenuDivider` between the groups when both are present.

No entries → no button (unchanged layout for regular users). Soft-deleted
posts never render this page, so no extra check. `onSelected` routes to the
existing mkpx handlers or `_editModHashtags(context, post)`.

### 6. Editor sheet — new `app/lib/club/ui/widgets/mod_hashtags_sheet.dart`

`showModalBottomSheet(isScrollControlled: true, ...)` from
`_editModHashtags`, seeded with the current `Post` and the cap. Layout (top to
bottom), matching the approved mock:

1. Header: shield icon + "Edit moderator hashtags".
2. **Monitored quick-picks** (A11), under a small section label **"Quick
   add"**: a `Wrap` of five `FilterChip`s from `kMonitoredHashtags`
   (`app/lib/club/config/monitored_hashtags.dart`), selected ⇔ tag in the
   working set; tap toggles (via the guarded `toggle`, §4).
3. **Current mod tags**, under a section label **"On this post"**: `Wrap` of
   `InputChip`s with delete ×, one per working tag, insertion order. The two
   labels make the chip-appears-in-both-sections model legible (review
   finding U3). Monitored tags get a shield leading icon + highlight color so
   a typo'd near-monitored tag is visually distinct (A11). Empty set → a
   one-line hint ("No moderator hashtags on this post.").
4. **Add tag**: `TextField` (lowercase keyboard, no autocorrect) + add button;
   submits on Enter/comma. Rejections surface inline (duplicate, >64 chars,
   cap). The cap in all copy is **interpolated from config**, never the
   literal 16 — counter `n/$cap`, error "cap reached — $cap max" (review
   finding T2).
5. **Note (optional)**: single-line `TextField`, label
   "Note (for the audit log)".
6. Actions: `Cancel` · `Save` (disabled while unchanged per
   `ModHashtagEdit.changed`, and while saving — spinner in the button).

**Confirm before exposing (review finding U1 / A15).** Adding a monitored tag
(hides a post) and removing one (re-exposes it publicly) are asymmetric in
risk: one fat-fingered chip-× plus a reflexive Save un-hides NSFW content.
When `edit.removesMonitored` is true at Save time, interpose an
`AlertDialog` — "Removing #nsfw will make this post visible to everyone
again. Remove it?" (list the affected tags; `Cancel` / `Remove`) — precedent:
`_detachMkpx`'s confirm in the same file. The fast add-`#nsfw` path stays
one tap on Save.

**Save flow:** `setModHashtags(post.id, edit.tags, note: noteTrimmedOrNull)` —
the sheet passes `note.trim().isEmpty ? null : note.trim()` so the key is
omitted for blank notes (`'note': ?note` omits only on null; review finding
T3). On success:
pop the sheet, `ref.invalidate(postDetailProvider(sqid))` (A10), snackbar
"Moderator hashtags updated." On `ClubError`, keep the sheet open with state
intact and show the error inside the sheet (not a snackbar behind it):

| `code` / condition | Message / behavior |
|---|---|
| `forbidden` | "Only moderators can edit these hashtags." (role revoked mid-session) |
| `not_found` | "This post can't be tagged — it may have been deleted." + pop sheet + invalidate detail provider |
| `validation_error` | Server message verbatim (cap/length — normally pre-blocked client-side) |
| `unauthorized` / `isAuth` | Existing session-expired copy, matching `_openLayersInEditor`'s handling |
| anything else | "Could not save — check your connection and try again." |

**Keyboard:** the sheet is `isScrollControlled` and padded by
`MediaQuery.viewInsets` so the add-tag field stays visible above the keyboard
(standard app pattern).

### 7. Notification — `app/lib/club/ui/notifications_page.dart`

Add to `_text` (line 72), copy softened per review finding U4:

```dart
case 'mod_hashtags_updated':
  return 'A moderator changed the hashtags on ${x.contentTitle ?? 'your artwork'}'
      '${x.commentPreview != null ? ': ${x.commentPreview}' : ''}';
```

**Anonymized presentation (review finding U5 / A17):** the text says
"a moderator" but the tile's leading `HandleAvatar` would show the acting
moderator's avatar/handle if the server populates the actor fields — the two
halves of the tile would disagree. For `type == 'mod_hashtags_updated'`,
render a shield avatar (a `CircleAvatar` with `Icons.shield`) instead of
`HandleAvatar`, matching the deliberately impersonal copy and the contract's
own framing ("A moderator updated tags…").

Model/API untouched (`commentPreview` already parsed; tile already deep-links
via `contentSqid`). The default-case fallback keeps older builds safe (already
true today).

### 8. Docs

- `SPEC-CLUB.md`: add mod-hashtags to the server-contract section (field,
  endpoint, config key, notification type) and to the §29 parity matrix.
- `STATUS.md`: new line under Club coverage.
- `docs/mod-hashtags/PROGRESS.md`: created during implementation, tracks the
  checklist below.

---

## Tests (`app/test/`, pure unit — no engine, no network)

New `mod_hashtags_test.dart`:

1. **Post parsing** — `mod_hashtags` present / absent / empty → `modHashtags`
   correct; `isModTag` membership.
2. **Config gating** — `max_mod_hashtags_per_post` present → enabled with the
   value; absent → `maxModHashtagsPerPost == null`, `modHashtagsEnabled` false;
   `fallback` disabled.
3. **Normalization** — mirrors server D12: `' #NSFW '` → `nsfw`; `'##x'` →
   `'#x'` (only one `#` stripped); empties dropped; order-preserving dedupe.
4. **`ModHashtagEdit`** — add/remove/toggle; duplicate and >64-char rejection;
   cap enforcement (post-normalization: adding `NSFW` when `nsfw` is present
   is a duplicate, not an extra tag); **`toggle` at the cap does not add**
   (T1); `removesMonitored` true only when a monitored tag present in the
   original set is missing from the working set; `changed` false for a
   reorder of the original set, true for a real diff, false again after
   reverting.
5. **Notification copy** — `mod_hashtags_updated` with and without
   `comment_preview`; unknown type still falls back.

Gates: `flutter test` and `flutter analyze` clean; `cargo` untouched (no
engine involvement — this is Dart-only Club work, keeping the engine
network-free per the architecture rule).

## Manual verification (dev, after the server team's "live on dev" message)

Build with `-Dev`; needs a moderator account and a second regular account on
development.makapix.club.

1. Regular signed-in user: no overflow mod entry; mod tags on others' posts
   render as plain tags.
2. Moderator on an artwork post: menu present; sheet opens seeded with the
   current mod set.
3. Add `nsfw` via quick-pick → save → detail page shows `🛡 #nsfw`; artist
   account sees the shield too; a third non-opted-in account no longer sees
   the post in feeds (server-side monitored filtering) but can still open the
   direct link (contract §8).
4. Artist account receives the `mod_hashtags_updated` notification with the
   diff; tapping deep-links to the post.
5. Claim semantics: artist-added tag added to the mod set → shield appears
   (claimed); removing it from the mod set removes it from the post entirely.
6. Cap/validation: over-cap tag blocked client-side (typed **and** via a
   monitored chip at the cap); sheet counter shows `n/16` (16 from config).
7. Playlist post: no mod entry in the menu.
8. No-op save: Save disabled when the set is unchanged (including reorder).
9. Removing a monitored tag prompts the confirmation dialog; cancel keeps the
   sheet state; confirm saves and the post reappears in feeds for everyone.
10. Artist + moderator see the "🛡 Tagged by a moderator" caption under the
    tags; a regular third account does not.
11. Windows build: tooltip on hover; sheet layout sane with a mouse.
12. Against **prod** (feature not yet flipped): config key absent → zero
    mod UI anywhere, marker impossible (field never sent). App otherwise
    unchanged.

## Rollout

1. Implement + unit tests (can start **now**, before the dev endpoint is live —
   everything except manual verification is contract-driven).
2. Commit reply `0002-app-mod-hashtags-ack.md` to the server repo's `develop`
   (appendix A).
3. When the server team announces dev-live: run the manual matrix above.
4. Ship in the next Play release (`release_android.ps1`, normal flow). Safe in
   either order vs the prod flip (config-key gate, D19): app-first → UI stays
   hidden until the key appears; server-first → older builds simply don't
   render markers/editor and the notification falls back generically.

## Risks / notes

- **Two menus collapsing into one** (A7) touches the existing mkpx menu; the
  merged builder must keep its exact conditions and handlers (covered by
  manual step where a moderator-owner sees both groups in one menu).
- **`_isOwner` compares `me.user.sub` to `post.owner.sqid`** — existing app
  idiom (used for the mkpx menu today); reused as-is for the artist marker.
- **Shield glyph**: use `Icons.shield` (Material) rather than the emoji so
  color follows the theme and Windows font fallback is a non-issue; the
  emoji in docs/mocks is illustrative.
- **No optimistic update**: the mod set only changes via the sheet's save →
  invalidate; no cache to reconcile. Feed cards don't render hashtags, so no
  other surface shows stale mod state.
- **Invalidate re-fires a view registration**: `postDetailProvider`
  (`post_providers.dart:12`) calls `registerView` on every (re)build, so each
  save logs one extra view by the moderator. Server-throttled (1/3 s),
  cosmetic; accepted (review finding T5).
- The server may add `reason_code` conventions later; A4 keeps the field out
  of the UI but the API method signature can grow it without churn.

## Review round (2026-07-05)

Two independent agents reviewed this plan (technical soundness vs contract +
codebase; UX adequacy). Verdicts: sound / production-grade / no blockers, and
"enough for the user's needs" respectively. All four should-fixes and most
nits were incorporated (marked `T*`/`U*` above; A15–A17 in DECISIONS.md).
Explicitly **not** adopted: a moderator-signal tint on the kebab icon (U7 —
reviewer itself deemed it unnecessary for a moderator population of ~1) and
any change to the bare-text tag tap-target size (pre-existing, out of scope).

---

## Appendix A — draft reply `0002-app-mod-hashtags-ack.md` (to server repo `message/`)

> **From:** app team · **To:** server team · **Re:** 0001 mod-hashtags kickoff
>
> 1. **Contract v1 acked** — no objections; building against it as frozen. One
>    clarification for your notes, no action needed: your §3 item 1 ("owner
>    edit form") is N/A in the app — the app has no post-metadata edit form
>    (hashtags are set once at publish; artwork "Replace" is bytes-only). The
>    artist-facing protection is covered by the read-only shield-marked
>    display on the post page. If the app grows a metadata editor later, it
>    will implement the exclusion.
> 2. **Moderator surface:** the app has none today; we're adding one for this
>    feature (overflow menu on the artwork detail page → "Edit mod hashtags"
>    bottom sheet with one-tap monitored chips per your D22, plus an optional
>    audit note; `reason_code` not exposed in v1). Shipping display +
>    notification + editor together in one release.
> 3. **Notification:** list rendering added for `mod_hashtags_updated`
>    (diff read from `comment_preview`). FYI the app has no push handling
>    today (a `google-services.json` is present but no FCM client is wired;
>    notifications are a polled list), so the push copy in §7 doesn't apply
>    to us; nothing needed from you. One optional suggestion, not blocking:
>    `#`-prefixing the tags in `comment_preview` (`+#nsfw −#politics`) would
>    read more naturally to artists on both clients.
> 4. **ETA:** app-side code + unit tests within ~1–2 days of now; manual
>    verification the day the endpoint is live on development.makapix.club.
>    We can flip whenever you're ready — the config-key gate makes order
>    irrelevant on our side.
