# Mentions — design

**Status:** **live on the server and the website since 2026-09-22** (server PR #275); the **app side is
built** and ships in the next store release. The thread:
[`0001`](../../messages/0004-mentions/0001-app-mentions-proposal.md) (our proposal) →
[`0002`](../../messages/0004-mentions/0002-server-mentions-accepted.md) (accepted, with five answers
and three amendments) → [`0003`](../../messages/0004-mentions/0003-app-mentions-adopted.md) (what we
built). Designed 2026-09-17/18 as `docs/profile-tag/`, all 21 decisions in
[`DECISIONS.md`](DECISIONS.md), renamed per D16.

**This document describes the system as built.** Where the server's amendments (0002 §2) changed what
we had proposed, the text below is the amended rule and says so; the proposal as written is in `0001`.

---

## 1. What the feature is

A user writes a comment, or a post description, and refers to another member by handle. Three
things follow:

1. **In the text,** the handle renders as a tappable link that opens that member's profile page.
2. **The mentioned member receives a social notification** ("@U1 mentioned you in a comment on
   *Title*") showing the artwork thumbnail; tapping it opens the post page.
3. **The comment or post stays ordinary** everywhere else: likes, replies, reports, moderation,
   deletion, hashtags, and the notification preview text all keep working unchanged.

Scope (D10): **comments and post descriptions, both in v1.** Bios and titles are out.

### Why this cannot be an app-only feature

The notification is created on the server, by the same code path that creates `comment` and
`comment_reply` notifications today (`api/app/routers/comments.py` → `SocialNotificationService`).
An app cannot write another user's inbox. So the feature is a **server + website + app** change with a
contract between the teams, like mod-hashtags and report-artwork were. The app team opens the thread
(D15; precedent: `notification-actor-sqid`, 2026-07-20); the server team has the final say on the
shared parts (`messages/README.md`).

---

## 2. Naming (D1: "mention")

"Tag" already means hashtag in all three codebases and in the notification copy (`post.hashtags`,
`post.mod_hashtags`, "Tagged by a moderator", `mod_hashtags_updated`, the Monitored hashtags
setting). A person-tag would be ambiguous in every conversation, commit, and string from here on.

| Name | Used by | Fit |
|---|---|---|
| **mention** | X/Twitter, Mastodon, Slack, Discord, GitHub, Reddit ("u/"), Instagram *comments* | The de-facto term for "@handle in text"; "mentioned you in a comment" reads naturally; no collision |
| tag | Instagram/Facebook *photos* | Collides with hashtags; implies attaching a person to the artwork |
| callout / shout-out | informal | Reads as praise, not as a reference |
| ping | Discord slang | Names the notification, not the link |

Notification type `mention`; UI copy "mentioned you in a comment on…" / "…in the description of…";
contract and docs say "mentions". "Tag" stays reserved for hashtags.

---

## 3. What exists today (the parts a mention rides on)

**Comments.** `POST /post/{id}/comments` takes `{body, parent_id?}`, body 1–2000 characters
(`schemas.CommentCreate`). Bodies are stored and returned as plain text; **no client parses them.**
The website prints `comment.body` verbatim in three places (`components/CommentsAndReactions.tsx`,
`components/SPOCommentsOverlay.tsx`, the moderation `umd/RecentCommentsPanel.tsx`); the app does
`Text(c.body)` once, in `app/lib/club/ui/widgets/comments_section.dart`, which both the artwork detail
page and the full-screen comments page render through. Comments carry `author_handle`,
`author_public_sqid`, `author_avatar_url` (flat fields; `models/comment.dart`). Anonymous
(signed-out) commenters exist on the website and are attributed to an IP; the app composer is sign-in
only. Rate limit: 30 comments per 5 minutes per user or IP. Profanity filter on the body. Edits:
`PATCH /post/comments/{id}` (authenticated authors only). Deletes tombstone the body and null every
notification's `comment_preview` for that `comment_id`.

**Descriptions.** `description` is a free-text field of up to 5000 characters on the post
(`schemas.PostUpdate`), written at upload (`POST /post/upload`; app `ui/publish_page.dart`) and via
`PATCH /post/{id}` (app `ui/edit_post_details_page.dart`, `PostApi.update`). Rendered as plain text on
the app detail page (`artwork_detail_page.dart`) and in the website's post overlays. A post can be
**pending approval** at upload time and become visible only when a moderator approves it
(`post_approved` notification).

**Handles and identity.** Handles are 3–32 code points (Unicode letters, digits, combining marks,
`-`, `_`), unique by a **confusable skeleton** (`users.handle_normalized`; `Fab`, `fab`, and Cyrillic
`fаb` collide), and **mutable** via `PATCH /user/{key}` (the site owner cannot rename). The stable
identity is `public_sqid` (Sqids; alphabet in `api/app/sqids_config.py`); profiles resolve only by
sqid (`GET /user/u/{sqid}/profile`). There is no lookup by handle.

**User search.** `GET /user/browse?q=` (auth required, `ILIKE %q%` on handle) backs the app's Search
page. It hides unverified, hidden, deactivated, non-conformant, and banned users, **the site owner**,
and users the viewer has blocked. Neither it nor `GET /search?types=users` ranks by context, which
is why D13 asks for a dedicated endpoint.

**Notifications.** One table (`social_notifications`) with denormalized display fields (`actor_*`,
`content_title/sqid/art_url`, `comment_id`, `comment_preview`, `post_id`). Types are the
`NotificationType` enum in `api/app/constants.py`; the column is free text, so a new type needs no
migration. Delivery: the row, then an in-process SSE push (`GET /realtime/notifications`), consumed
by the app while foregrounded (`state/notifications_sse.dart`), with a 60-second poll as fallback.
**There is no OS push (no FCM/APNs) in the app**: a mention is seen when the user next opens the app
or the website. Unread count and list are block-filtered by actor (ugc-safety D10). Both clients
render an unknown type without crashing (app: `"@who · mention"` with a working post link; website:
"X interacted with *Title*"), so the server can ship first.

**Blocks.** Symmetric interaction refusal (D11 of ugc-safety: comment/reaction/like/follow return
`403 blocked` in either direction) and one-way visibility (D10: the blocker never sees the blocked
user's content, notifications included). Live SSE delivery is gated the same way.

**User settings.** `PATCH /user/{key}` (`schemas.UserUpdate`) carries the existing per-user
preferences (`approved_hashtags`, `hidden_by_user`); the app's Settings page lists Blocked users and
Monitored hashtags as sub-pages; `/auth/me` returns the current values.

**Feature discovery.** A key on `GET /config` is the repo's launch signal (`max_mod_hashtags_per_post`
gated the mod-hashtags UI; `moderation` gates report/block).

---

## 4. Representation (D2, D17, D18)

### 4.1 The markup: `<@SQID>`

A mention is stored inline in the text as the user's public sqid in angle brackets:

```
great palette <@t5>, see <@Qx>'s remix
```

- **The sqid is the only content.** There is no handle text to keep in sync or to spoof; the handle
  is resolved from the sqid on every read (§4.3). A body that mentions someone reads correctly
  after they rename, forever.
- Grammar: `"<@" sqid ">"`, `sqid` = 1–32 characters of the Sqids alphabet; no whitespace inside; no
  nesting. Anything else that starts with `<@` is plain text.
- **Clients match `[A-Za-z0-9]{1,32}`** (0002 §1.1). `SQIDS_ALPHABET` is environment-configured on the
  server and is in no repo, so no client can match the real alphabet; both environments' alphabets are
  subsets of base62, and a user sqid is at most 7 characters. The server is the only party that decides
  whether a matching sqid resolves.
- A `<@SQID>` whose sqid does not resolve to a **mentionable** user for the writer (§5.2) is
  **flattened** on write to plain `@handle` text (or to `@user` if the sqid resolves to no account —
  the placeholder confirmed in 0002 §1.2). It never links and never notifies, and no error is returned,
  so the markup can never be used to probe who blocked whom or who opted out.
- **Resolution is generous by design** (0002 §3): any account that still exists resolves, including one
  hidden or banned *after* the mention was written — its profile page applies its own rules. Only a
  deleted account renders `@user`.
- Length limits (2000 for comments, 5000 for descriptions) apply to the stored markup form; a
  mention costs `len(sqid) + 3` characters.

### 4.2 The dual field: legacy readers keep seeing plain text

Every reader that prints the text verbatim today (three website surfaces, every app build in the
field, `comment_preview` on notifications) would otherwise show `<@t5>`. So the server serves two
fields (D18):

| Field | Content | Who reads it |
|---|---|---|
| `body` / `description` | **plain rendering**: each `<@SQID>` replaced by `@handle` (current handle, resolved at read) | every client that exists today, unchanged |
| `body_markup` / `description_markup` | the stored source with `<@SQID>` | clients that render mention links |

Request side: `POST`/`PATCH` keep their single `body` / `description` field and accept markup in it.
The rollout is therefore order-independent (§5.5).

One accepted consequence (D18): an **edit from a legacy client** writes back the plain text it
displayed, so that comment's or description's mentions are lost (the handle stops being a link). No
server-side re-merge; edits are rare and the website adopts the composer in the same cycle.

### 4.3 Read-time resolution

The server stores the **markup only** and resolves the plain rendering on every read (0002 §3) — there
is no stored plain copy, so a rename always shows the current handle. Rendering needs each distinct
sqid on the page resolved to a user (one `IN (...)` query per comment page, one per post). This is also where the mentionability of the
*reader* does not matter: a mention links for everyone who can see the text; only the *writer's*
relationship to the target decided whether it was stored as a mention at all.

### 4.4 The alternative not taken

Plain `@handle` text with a server-resolved sidecar (`mentions: [{handle, public_sqid}]`) would
have needed no compatibility field and would let hand-typed handles mention, but needs two or three
Unicode word-boundary tokenizers that agree, and its text goes stale on rename. The owner chose the
sqid markup for exactness (D2); with the dual field it degrades just as gracefully.

---

## 5. Behavior (v1, as decided)

Rules apply to comments and descriptions alike unless a row says otherwise.

### 5.1 Writing

- **W1 (D19).** A mention exists only when **picked from the candidates list** (or pasted as valid
  markup). A hand-typed `@fab` that was never picked is plain text: no link, no notification. The
  server never resolves text.
- **W2 (D13, D21).** Candidates come from `GET /user/mention-candidates` (§6.2): the post owner and
  the thread's participants first, then people the writer follows and is followed by, then a prefix
  match on the handle skeleton. Requested on `@` (empty query returns the contextual set) and on
  every keystroke inside the token, debounced 250 ms, previous request cancelled, at most 8 rows.
  At first publish there is no `post_id` yet, so only the graph and search tiers apply.
- **W3 (D5).** At most **16 mentions per text** (`max_mentions_per_text` on `/config`). Extras are
  flattened to plain text, never rejected; the composer stops offering candidates at the cap and says
  why.
- **W4 (D4).** Anonymous (signed-out, IP-attributed) commenters cannot mention: their markup is
  flattened on write. Neither link nor notification.
- **W5.** Self-mention links but never notifies (the existing self-action rule).
- **W6.** The app's text fields show `@handle`, never `<@SQID>`. The composer keeps a display string
  plus the list of picked `(handle, sqid)` pairs and serializes on send (§10). Three fields get this:
  the comment composer, the description on the publish page, and the description on the edit-details
  page (D10) — one shared widget.

### 5.2 Mentionability (server, on create and on edit; D3, D11)

A sqid is mentionable **for this writer** when the target:

1. would appear in `/user/browse` for the writer (email-verified; not hidden by user or moderator;
   not deactivated, banned, or non-conformant), **except that the site owner is mentionable** even
   though browse hides them (D3);
2. has **no block in either direction** with the writer;
3. has a **mention policy** that admits the writer (D11, v1): `everyone` (default) · `following`
   (only members the target follows may mention them) · `nobody`.

Anything else is flattened silently (§4.1) and absent from the candidates list. The check is one
server function used by the write path and by the candidates endpoint, so the two can never
disagree.

The setting: `users.mention_policy` (`everyone` | `following` | `nobody`, default `everyone`),
settable through `PATCH /user/{key}`, returned by `/auth/me`; app Settings gains a **Mentions** row
beside Blocked users and Monitored hashtags; the website mirrors it.

### 5.3 Notifying

- **N1.** New `NotificationType.MENTION = "mention"`. Actor = the writer; `post_id` +
  `content_title/sqid/art_url` = the post. For a **comment** mention: `comment_id` = the comment and
  `comment_preview` = first 100 chars of its plain rendering. For a **description** mention:
  `comment_id` null, `comment_preview` = first 100 chars of the plain description. Same field shape
  as `comment_reply`, so both clients' whole-tile post link and avatar link work with no new fields;
  `comment_id` null-or-not tells the tile which copy to use.
- **N2 (D6).** **One notification per recipient per comment.** If the recipient already receives
  `comment` (post owner) or `comment_reply` (parent author) for the same comment, the `mention` row
  is skipped. Precedence: `comment_reply` > `comment` > `mention`. (Descriptions have no
  competing type.)
- **N3 (D7, amended by 0002 §2 A1).** **Visibility guard — and a hold until approval.** No notification
  when the recipient cannot access the post or when the post carries a monitored hashtag the recipient
  has not opted into (`approved_hashtags`).

  The proposal assumed `can_access_post` hides a pending post. **It does not** — since the server's
  August new-post UX, a pending post is reachable by anyone with its link and is listed on the author's
  profile. The visibility guard alone would therefore have let an unmoderated upload push itself into
  up to 16 inboxes. The rule as built: **no `mention` notification goes out while the post's
  `public_visibility` is false**, for description mentions *and* comment mentions. On approval the
  server notifies the still-eligible recipients of the description and of every live comment, each at
  most once, so a revoke → re-approve sends nothing twice. Uploads by users with auto-approval notify
  at once. The links themselves work throughout.

- **N3b (0002 §2 A3).** **Hidden or deleted posts notify nobody**, moderators included. Unhiding does
  not replay mentions, same as every other notification type.

- **N3c (0002 §2 A2).** **A description's writer is always the post owner**, including when a moderator
  edits the description: mentionability is checked against the owner and the notification's actor is
  the owner. (The app has no moderator description editor, so this is a website and server rule.)
- **N4.** Blocks and policy: §5.2 means no row is ever written; the existing D10 list filter and SSE
  gate remain as a second line.
- **N5 (D5).** Rate: **256 notified mentions per writer per hour**, on top of the existing 720/hour
  per actor→recipient pair. Past the budget, mentions still link; they stop notifying.
- **N6 (D8).** Edit (comment `PATCH`, description `PATCH`): diff the old and new mention sets;
  **notify newly added recipients only**; never re-notify; removed mentions keep their old row.
- **N7.** Delete: the existing `comment_preview` nulling covers `mention` rows (same `comment_id`).
  Hide-by-mod: unchanged from `comment`/`comment_reply`.
- **N8.** Deleted recipient accounts: the `users.id` cascade removes their notifications and their
  sqid stops resolving, so old markup renders as plain `@user`. Deleted *actor* accounts: `actor_id`
  goes NULL like every other type; the tile renders an inert avatar.

### 5.4 Rendering

- **V1.** The app parses `body_markup` / `description_markup` (falling back to the plain field when
  absent) into spans; each `<@SQID>` becomes a tappable span opening `ProfilePage(sqid)` with the
  handle resolved by the server (§4.3 — the server includes `mentions: [{public_sqid, handle}]`
  alongside the markup so clients do not resolve anything themselves; §6.3). Malformed markup is plain
  text. Two places: `comments_section.dart` and the description block of `artwork_detail_page.dart`,
  through one shared span builder.
- **V2.** Style: the handle color already used for tappable handles (the comment author line and
  `by @owner`), no underline, body font size.
- **V3 (D9).** Notification tile: "**@U1** mentioned you in a comment on *Title*: *preview*" or
  "**@U1** mentioned you in the description of *Title*", actor avatar left (→ U1's profile), artwork
  thumbnail right, whole tile opens the post page. Scroll-to-comment stays a separate effort.
- **V4.** The website does the same on its three comment surfaces, its post overlays, and
  `pages/notifications.tsx` (server team).

### 5.5 Discovery and rollout (D12)

- **G1.** Launch signal: `GET /config` gains `max_mentions_per_text`. The app enables the `@`
  candidates in its three composers only when the key is present, and renders the `*_markup` fields
  whenever they are present.
- **G2.** Order: **server → app → website.** All server changes are additive; the app's renderer
  tolerates the fields' absence; the website follows. Nothing looks broken at any step because of
  the dual field.

---

## 6. The contract

Sent as [`messages/0004-mentions/0001-app-mentions-proposal.md`](../../messages/0004-mentions/0001-app-mentions-proposal.md)
(D15) and accepted in [`0002`](../../messages/0004-mentions/0002-server-mentions-accepted.md), which
answered the five open items and amended three rules. What follows is the contract **as built**; the
five answers are folded into the text below rather than left as questions.

### 6.1 Grammar and vectors (shared; all three test suites)

```
mention := "<@" sqid ">"      sqid := 1+ characters of the Sqids alphabet
```

| Stored text | Plain rendering (`body`) | Markup client renders | Notes |
|---|---|---|---|
| `hi <@t5>!` | `hi @fab!` | hi **@fab**! | link → `/u/t5` |
| `<@t5>, <@Qx>.` | `@fab, @mika.` | **@fab**, **@mika**. | two mentions |
| `<@ZZZZ>` (no such account) | `@user` | @user | flattened on write; `@user` confirmed in 0002 §1.2 |
| `<@t5>` written by someone t5 blocked, or whose policy excludes the writer | `@fab` | @fab | flattened on write; no notification; no error |
| `<@t5` · `<@>` · `<@ t5>` · `< @t5>` | as written | as written | malformed → plain text |
| `@fab` | `@fab` | @fab | never picked (W1): plain text |
| `a<@t5>b` | `a@fabb` | a**@fab**b | no boundary rule needed; allowed |
| 17 valid mentions | first 16 link | first 16 link | cap (W3) |
| `<@t5>` after t5 renames to `fabkury` | `@fabkury` | **@fabkury** | read-time resolution (§4.3) |

### 6.2 New endpoint: `GET /user/mention-candidates` (the ask; D21 accepted as sketched)

- Auth required. Query: `q` (optional prefix on the handle skeleton, so casing and confusables behave
  like uniqueness), `post_id` (optional; the **integer** post id, not the sqid — silently ignored when
  the caller cannot access that post), `limit` (default 8, 1–20). An empty `q` returns **only** the
  contextual tiers; `search` rows appear only with a non-empty `q` (0002 §1.5).
- Response: `{"items": [{"handle", "public_sqid", "avatar_url", "reason"}]}`, `reason` one of
  `owner` · `thread` · `following` · `follower` · `search`, ranked in that order, then alphabetical.
- Applies exactly the mentionability function of §5.2 (browse visibility + site owner + two-way
  block + mention policy); excludes the caller.
- Rate limit **120 requests / 60 s per user**, 429 past it (0002 §1.4). No caching (per caller, per
  post). The app debounces 250 ms and cancels the previous request, so a fast typist costs about one
  request per word.

### 6.3 Wire changes (all additive)

- `Comment` payload: `body_markup` (string) and `mentions: [{public_sqid, handle, avatar_url?}]`
  for the sqids it contains, resolved at read. `body` stays the plain rendering.
- `Post` payload: `description_markup` and `mentions` likewise. `description` stays plain.
- `POST /post/{id}/comments`, `PATCH /post/comments/{id}`, `POST /post/upload`, `PATCH /post/{id}`:
  the existing text field accepts markup. No new request fields.
- `GET /config`: `max_mentions_per_text` (integer; the launch signal).
- `NotificationType.MENTION = "mention"` with the `comment_reply` field shape (§5.3 N1). **One
  correction to our "no new fields" claim** (0002 §4): `comment_id` was not on the notification wire
  before, only on the server's internal create schema. It is now served on every notification, REST and
  SSE alike; `club_notification.dart` already read it, so it simply started arriving.
- `users.mention_policy` on `UserUpdate` / `UserPublic`-for-self / `/auth/me`:
  `everyone` | `following` | `nobody`.

### 6.4 Server-side storage (as built)

No new table: `comments.body` and `posts.description` store the markup and the plain rendering is
resolved on every read — no `*_plain` column. One new column, `users.mention_policy` (varchar, default
`everyone`), plus its migration. Edit diffs parse old and new text.

Also decided server-side (0002 §3): moderators get no looser rules as writers; the length limits
(2000 / 5000) apply to the submitted text, and flattening may make the stored text slightly longer
without it ever being truncated or refused; the profanity filter runs on the text with the markup
removed; and **every other reader gets the plain rendering** — all notification previews, the player
RPC, search, moderator tools, exports. Nothing outside a `*_markup` field ever shows `<@…>`.

---

## 7. What it took

| Where | Outcome |
|---|---|
| **Server + website** | Built and released together, 2026-09-22, server PR #275. Server record: `docs/mentions/README.md` in that repo (decisions S1–S12). |
| **App** | Built 2026-09-22 against the live server: models, the markup parser, the span builder, the shared `@` composer in three fields, the notification tile, Settings → Mentions, the `/config` gate. 77 tests across `mention_markup_test.dart` and `mentions_test.dart`. Ships in the next store release. |

The original estimate was 11–14 developer-days across the three codebases. The parts that carried the
most weight were the ones predicted: the shared composer widget (an overlay anchored to a field that
sits above the keyboard, plus keeping the picked pairs consistent through edits and paste) and the
server's contextual candidates endpoint.

Two things the estimate missed, both cheap once seen:

- **The optimistic comment.** The comment provider echoes what it sent, which is now markup, so the
  new tile would have flashed `<@t5>` until the reload landed. It now takes the picked pairs and
  renders the plain text with live links immediately (`post_providers.dart`).
- **Seeding an edit.** Populating the edit-description field from the server's `mentions` array means
  an app edit that leaves the handles alone **preserves** them, rather than stripping them as D18
  allows. The strip now only happens if the user edits the handle text itself.

Runtime cost is as predicted: one `IN` lookup per page of comments or per post, at most 16 notification
rows per text, one debounced candidates query per word typed.

## 8. Risks, and where each one landed

Ordered by how much they would have hurt.

1. **Unsolicited-ping channel (abuse).** Mentions are the first way to put a notification in someone's
   inbox without them having posted, commented, or followed. **Closed as designed:** per-text cap (W3),
   per-writer budget (N5), block symmetry and the mention policy (§5.2), no anonymous pings (W4), the
   existing report flow.
2. **Leaking filtered or invisible content into an inbox.** **Closed, and it was worse than we thought**
   — see N3. Our guard rested on pending posts being inaccessible, which they are not; the server
   replaced it with a hold on `public_visibility`, covering comment mentions too, which our proposal
   did not.
3. **Legacy edits strip mentions.** **Reduced on our side.** The app seeds its edit fields from the
   server's `mentions` array, so an app edit that leaves the handles alone preserves them. The strip
   remains only for a user who edits the handle text itself, and for clients that do not do the seeding.
4. **Parser divergence between Dart, TypeScript, and Python.** **Contained:** the §6.1 table is in all
   three suites — `api/tests/test_mentions.py`, `web/e2e/mention-markup.spec.ts` (a port of our Dart
   implementation), and our `mention_markup_test.dart`. A row that changes moves all three files.
5. **Description mentions and approval timing.** **Answered:** the server re-evaluates at approval, for
   descriptions and comments alike (N3).
6. **Double notification.** Closed by D6 for comments; descriptions have no competing type.
7. **Expectation mismatch: no OS push.** A mentioned user is only told when they next open the app or
   the site. True of every type today; one line in the release notes.
8. **Candidates endpoint as a directory.** No new exposure: it applies the §5.2 function exactly, so an
   empty `q` lists what the caller can already see and a prefix query is `/user/browse` better ranked.
9. **Mention policy semantics.** `following` means "only people I follow may mention me". The app's
   setting states the direction twice, in the option label ("People I follow") and its description.

Still open, both for the device pass rather than the design:

- **The composer overlay on a real keyboard.** It picks above or below the field from the space left
  under the viewport inset. Tested in widget tests, not yet on the Pixel or an iPhone.
- **Candidate latency on a slow connection.** The list stays empty and silent on error rather than
  toasting mid-typing; whether that reads as broken is a judgment call best made on a device.

No memory, battery, engine, or FFI impact: this is pure Club (`app/lib/club/`), and Club unit tests
keep running without the engine binary.

---

## 9. Deferred

- **Scroll-to-comment on notification tap** (benefits `comment`, `comment_reply`, `comment_like`,
  `mention` alike): separate small effort.
- **Mentions in bios and titles**: the grammar and renderer transfer; not planned.
- **Server-side re-merge of legacy edits**: rejected (D18); revisit only if stripped mentions turn
  out to be common.
- **Reference kinds beyond users** (`<#post>`): the grammar leaves room; nothing planned.

---

## 10. The code, as built

Everything below is on `main` as of 2026-09-22 and ships in the next store release. Nothing here
touches the engine, the FFI seam, memory budgets, or the launch path — it is all `app/lib/club/`, and
the Club unit tests still run without the engine binary.

**Parsing and models**

- `models/mention_markup.dart` — the grammar, written 2026-09-22 ahead of the server and of any UI,
  because it is the Dart third of the three-parser divergence risk (§8.4). `parseMentionMarkup` →
  `List<MentionSegment>` (`PlainSegment` | `MentionedSegment`), `plainFromMarkup`,
  `serializeMentions(displayText, picked)`, `hasMentionMarkup`, `MentionRef`, `kMaxMentionsPerText`.
  Client-side sqid class `[A-Za-z0-9]{1,32}` (§4.1).
- `models/mention_candidate.dart` — `MentionCandidate` and `MentionReason` (`owner` · `thread` ·
  `following` · `follower` · `search`, plus `unknown`, so a tier added later renders instead of
  crashing).
- `models/comment.dart`, `models/post.dart` — `bodyMarkup` / `descriptionMarkup` and `mentions`, both
  tolerant of a server that does not send them. `markDeleted` and `withReplies` carry them through.
- `models/club_user.dart` — `MentionPolicy` (`everyone` · `following` · `nobody`, unknown reads as
  `everyone`) with the label and description strings, and `ClubUser.mentionPolicy` + `copyWith`.
- `models/server_config.dart` — `maxMentionsPerText` (nullable) and `mentionsEnabled`, the launch gate.

**Rendering**

- `ui/widgets/mention_text.dart` — the span builder. `Text.rich` with one `TapGestureRecognizer` per
  mention, rebuilt per build and disposed with the widget. Link style `colorScheme.primary` weight 600,
  following `markdown_bio.dart`. Falls back to one ordinary `Text` when there is no markup, so the old
  path is untouched. No `semanticsLabel` on the span: it would replace the handle in `toPlainText()`,
  which copy and text extraction rely on.
- Hosts: `ui/widgets/comments_section.dart` (comment bodies) and `ui/artwork_detail_page.dart`
  (the description block).

**Composing**

- `ui/widgets/mention_field.dart` — `findMentionToken` (the `@`-led token under the caret; an `@` must
  open a token, so an email address never triggers it), `MentionComposer` (owns the text controller and
  the picked pairs, exposes `serialized`, `liveCount`, and `seedFromMarkup` for edits), and
  `MentionField` (wraps the host's own `TextField`, shows the candidates overlay above or below
  depending on room under the keyboard, debounces 250 ms, orphans a late response by sequence number,
  and says why when the cap is reached).
- `api/mentions_api.dart` + `mentionsApiProvider` — `GET /user/mention-candidates`.
- Three hosts: the comment composer, `ui/publish_page.dart` (no `post_id` yet, so graph and search
  tiers only), and `ui/edit_post_details_page.dart` (seeded from the post's `mentions`, so an edit that
  leaves the handles alone preserves them).
- `state/post_providers.dart` — `add()` takes the picked pairs so the optimistic comment renders the
  plain text with live links instead of flashing raw markup.

**Around the edges**

- `ui/notifications_page.dart` — the `mention` case, comment vs description by `commentId`.
- `ui/mentions_settings_page.dart` + the Settings row — the three-way policy through
  `SettingsApi.setMentionPolicy`, mirrored into the cached identity by
  `AuthController.updateMentionPolicy`, the row gated on `mentionsEnabled`.

**Tests** — `test/mention_markup_test.dart` (41: the §6.1 vectors, the cap, malformed input,
serialize→parse round trips) and `test/mentions_test.dart` (36: token detection, composer bookkeeping
and edit seeding, the span builder including tap and recognizer disposal, model parsing, the config
gate). Full suite 1054 pass, `flutter analyze --fatal-infos` clean.

**Server and website (`makapix`)** — released 2026-09-22 in PR #275. Its own record is
`docs/mentions/README.md` in that repo, decisions S1–S12.
