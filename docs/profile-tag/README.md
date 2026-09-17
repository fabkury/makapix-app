# Mentions in comments ("profile tag") — design

**Status:** design only, nothing implemented. Written 2026-09-17 to scope the feature before any
code or any message to the server team. The open questions live in [`DECISIONS.md`](DECISIONS.md);
this file is the write-up they refer to.

**Working name:** this folder is called `profile-tag` because that is how the feature was first
described. The recommended product name is **mention** (see §2). Nothing in this document depends on
the folder name.

---

## 1. What the feature is

User U1 writes a comment C on post P by user U2. Inside the comment, U1 refers to user U3 by handle.
Three things follow:

1. **In the comment body,** U3's handle renders as a tappable link that opens U3's profile page.
2. **U3 receives a social notification** saying U1 mentioned them in a comment. The notification
   shows P's artwork thumbnail and tapping it opens P's page.
3. **The comment stays an ordinary comment** everywhere else: likes, replies, reports, moderation,
   deletion, and the notification preview text all keep working unchanged.

Comments only. Post descriptions, bios, and titles are out of scope for v1 (§9 says why that is
cheap to add later).

### Why this cannot be an app-only feature

The notification is created on the server, by the same code path that creates `comment` and
`comment_reply` notifications today (`api/app/routers/comments.py` → `SocialNotificationService`).
An app cannot write another user's inbox. So the feature is a **server + website + app** change with a
contract between the teams, like mod-hashtags and report-artwork were. The app team can draft the
contract and open the thread (precedent: the app team opened `notification-actor-sqid` on
2026-07-20), but the server team has the final say on the shared parts (`messages/README.md`).

Only the link (item 1) could be built app-only. §8 explains why shipping that alone is a bad idea.

---

## 2. Naming

"Tag" is already taken in this product. The server, the website, and the app all say **tag** for
hashtags: `post.hashtags`, `post.mod_hashtags`, the "Tagged by a moderator" legend, the
`mod_hashtags_updated` notification copy ("A moderator changed the hashtags on…"), and the Settings
page for monitored hashtags. A "tag" that means a person would be ambiguous in every conversation,
commit message, and notification string from here on.

Candidates:

| Name | Used by | Fit |
|---|---|---|
| **mention** | X/Twitter, Mastodon, Slack, Discord, GitHub, Reddit ("u/"), Instagram *comments* | The de-facto term for "@handle in text"; "mentioned you in a comment" reads naturally; no collision |
| tag | Instagram/Facebook *photos* | Collides with hashtags here; also implies attaching a person to the artwork, which this is not |
| callout / shout-out | informal | Reads as praise, not as a reference |
| ping | Discord slang | Too technical, and it names the notification rather than the link |

**Recommendation: "mention".** Notification type `mention`, UI copy "@U1 mentioned you in a comment
on *Title*", contract and docs titled "mentions". Keep "tag" for hashtags forever. This document uses
"mention" from here on.

---

## 3. What exists today (the parts a mention rides on)

Everything a mention needs already exists except the mention itself.

**Comments.** `POST /post/{id}/comments` takes `{body, parent_id?}`, body 1–2000 characters
(`schemas.CommentCreate`). The body is stored and returned as plain text; **no client renders any
markup in comment bodies** (website: `components/CommentsAndReactions.tsx` prints `comment.body`
verbatim; app: `Text(c.body)` in `app/lib/club/ui/widgets/comments_section.dart`). Comments carry
`author_handle`, `author_public_sqid`, `author_avatar_url` (flat fields; `models/comment.dart`). Anonymous
(signed-out) commenters exist on the website and are attributed to an IP; the app composer is
sign-in only. Rate limit: 30 comments per 5 minutes per user or IP. Profanity filter on the body.
Edits: `PATCH /post/comments/{id}` (authenticated authors only). Deletes tombstone the body and null
every notification's `comment_preview` for that `comment_id`.

**Handles.** 3–32 code points; Unicode letters in any script, digits, combining marks, `-` and `_`;
must contain a letter or digit; may not start or end with `-`/`_` (`api/app/utils/handle_normalize.py`).
Uniqueness is by a **confusable skeleton** (`users.handle_normalized`: casefold + NFKC + a non-ASCII
homoglyph fold), so `Fab`, `fab`, and Cyrillic `fаb` are the same handle. **Handles are mutable:** a
user can rename via `PATCH /user/{key}` (the site owner cannot). The stable identity is
`public_sqid`; profiles resolve only by sqid (`GET /user/u/{sqid}/profile`) — there is no lookup by handle.

**User search.** `GET /user/browse?q=` (auth required, `ILIKE %q%` on handle, 40–200 per page,
sorted alphabetical/recent/reputation) already backs the app's Search page (`api/search_api.dart`).
It hides unverified, hidden, deactivated, non-conformant, and banned users, the site owner, and users
the viewer has blocked. `GET /search?types=users` is a trigram-similarity variant.

**Notifications.** One table (`social_notifications`) with denormalized display fields:
`actor_*`, `content_title/sqid/art_url`, `comment_id`, `comment_preview` (first 100 chars),
`post_id`. Types are the `NotificationType` enum in `api/app/constants.py`; the column is free text,
so a new type needs no migration. Delivery: the row, then an in-process SSE bus push
(`GET /realtime/notifications`), consumed by the app while foregrounded (`state/notifications_sse.dart`),
with a 60-second poll as fallback. **There is no OS push (no FCM/APNs) in the app**, so a mention is
seen when the user next opens the app or the website. Unread count and list are block-filtered by
actor (ugc-safety D10).

**How the app renders an unknown type today.** `NotificationsPage._text` falls to
`'$who · $type'` and the tile still deep-links to the post via `content_sqid`. The website falls to
"X interacted with *Title*". So a server that starts emitting `mention` before the clients update is
**ugly but not broken**. This is the property that lets the three teams ship independently.

**Blocks.** Symmetric interaction refusal (D11: comment/reaction/like/follow return `403 blocked`
between two users with a block in either direction) and one-way visibility (D10: the blocker never
sees the blocked user's content, notifications included; the rows are still written so unblocking
reveals history). Live SSE delivery is gated the same way.

**Feature discovery.** The repo's launch-signal pattern is a key on `GET /config`
(`max_mod_hashtags_per_post` gated the mod-hashtags UI; `moderation` gates report/block). The app
enables a feature's UI when the key appears on `development.makapix.club`, and its appearance on
`makapix.club` is the production launch.

---

## 4. The central design choice: how a mention is represented

Everything else follows from this. Three options were considered.

### Option A — plain `@handle` text, resolved by the server, with a sidecar (recommended)

The body stays exactly what the user typed: `great palette @fab, see @mika's remix`. On create and
edit, the server tokenizes the body, resolves each `@handle` token against `handle_normalized`, stores
the matches, and returns them alongside the comment:

```json
{
  "id": "…", "body": "great palette @fab, see @mika's remix", "author_handle": "u1", …,
  "mentions": [
    {"handle": "fab",  "public_sqid": "t5"},
    {"handle": "mika", "public_sqid": "Qx"}
  ]
}
```

Clients that know about `mentions` linkify the matching `@handle` tokens; clients that do not
render the plain text they always rendered. The website, the app's shipped builds, the notification
`comment_preview`, the moderation panel, and search all keep working with zero changes.

- **Pro:** nothing new on the wire in the body; graceful on every existing client; edits from an
  unaware client cannot corrupt anything; users type what they see everywhere else on the internet.
- **Pro:** rename-proof in the way that matters. The link goes to the stored `public_sqid`, so it
  keeps working after U3 renames. The *text* `@oldname` goes stale, which is what every major
  product does (X, GitHub, Slack all show the handle as written at the time).
- **Con:** the server must own a tokenizer, and the app must own an identical one for rendering and
  for composer autocomplete. The grammar must be pinned in the contract with shared test vectors
  (§6.1), or the two will disagree on Unicode edges.
- **Con:** a mention of someone who renames to a handle that another user later takes would, if
  re-resolved from text, point at the wrong person. The sidecar stores the sqid at write time, so
  it never re-resolves. This is why the sidecar must be **stored**, not recomputed on read.

### Option B — inline markup carrying the stable id

Body contains `@[fab](u:t5)` or `<@t5>`. Exact, rename-proof, no tokenizer ambiguity.

- **Con (disqualifying):** every client that does not understand the markup shows it raw. That is
  the website today, every app build in the field, `comment_preview` in every notification, and the
  website moderation panel. The server would need a "plain" rendering of every body at every read
  site until every client is updated, and an edit from an unaware client strips or mangles the
  markup. The bio mini-markdown (`widgets/markdown_bio.dart`) is a precedent for markup, but bios
  have had it from the start; comments have two years of plain-text readers.

### Option C — app-only: parse `@handle` on render, resolve lazily, no notification

The app would tokenize on render and call `/user/browse?q=handle` to find the sqid.

- **Con (disqualifying for the stated feature):** no notification is possible without the server.
- **Con:** `/user/browse` is a substring search, so exact resolution needs a client-side skeleton
  match that will diverge from the server's confusable table; and it costs one request per distinct
  handle per comment list.
- **Value:** as a *development stepping stone* it lets the app team build and test the renderer and
  the composer before the server lands. Not as a release (§8).

**Recommendation: Option A**, stored sidecar, with the grammar pinned in the contract.

---

## 5. Proposed behavior (v1)

Numbered so [`DECISIONS.md`](DECISIONS.md) can refer to them. Items marked *(open)* are decisions
for the owner; the text states the recommended answer.

### 5.1 Writing a mention

- **W1.** A mention is `@` + a handle, written by the user in the comment body. Nothing else changes
  in the body.
- **W2.** The app composer offers **autocomplete** when the caret is inside an `@` token with at
  least one character. Candidates, in order: the post owner and the authors already in the loaded
  thread (zero network — the app has them), then `GET /user/browse?q=` results, debounced 250 ms,
  request-cancelled on every keystroke, at most one page. Picking a candidate replaces the token with
  `@handle ` (trailing space).
- **W3.** *(open — D5)* At most **5 resolved mentions per comment**. Beyond that the server keeps the
  text but neither links nor notifies the extras (it does not reject the comment). The app shows the
  cap in the composer once reached.
- **W4.** *(open — D4)* Anonymous (signed-out, IP-attributed) commenters: their `@handle` tokens are
  **resolved and linked but never notify**. An unaccountable ping is a harassment vector with no
  recourse for the recipient.
- **W5.** Self-mention resolves and links but never notifies (the existing self-action rule).

### 5.2 Resolving

- **R1.** Resolution is by handle skeleton (`users.handle_normalized`), so casing and confusables
  behave exactly like handle uniqueness does. One indexed lookup per token; tokens are deduplicated
  first.
- **R2.** *(open — D3)* A token resolves only to a user who would appear in `/user/browse` for that
  commenter: email-verified, not hidden by user or moderator, not deactivated, not banned, not
  non-conformant, not the site owner, and **no block in either direction** between commenter and
  target. Anyone else stays plain text, silently. No error, no hint (a `403 blocked` here would tell
  U1 that U3 blocked them; refusing the comment would do the same).
- **R3.** Resolution happens once, at create and at edit, and the result is stored
  (`comment_mentions`: `comment_id`, `user_id`, `handle_at_mention`, `created_at`). Reads never
  re-resolve from text (§4, Option A, last con).

### 5.3 Notifying

- **N1.** New `NotificationType.MENTION = "mention"`. Fields: actor = commenter (handle, avatar,
  sqid), `post_id` + `content_title/sqid/art_url` = P, `comment_id` = C, `comment_preview` = first
  100 chars of C. This is byte-for-byte the shape of `comment_reply`, so both clients' whole-tile
  deep link (post page) and avatar link (actor profile) work without new fields.
- **N2.** *(open — D6)* **One notification per recipient per comment.** If the recipient already
  receives `comment` (they own P) or `comment_reply` (they wrote the parent) for C, the `mention` row
  is skipped. Precedence: `comment_reply` > `comment` > `mention`. Two rows for one comment is the
  most common complaint about mention systems.
- **N3.** *(open — D7)* **Visibility guard.** No notification when the recipient cannot access P
  (`can_access_post`: hidden, unlisted-to-them, pending approval, soft-deleted) **or when P carries a
  monitored hashtag the recipient has not opted into** (`approved_hashtags`). Without this, a mention
  puts an `#nsfw` thumbnail into the inbox of someone who has that filter on. This guard does not
  exist for `comment_reply` today because the recipient chose to participate in that thread; a
  mention is unsolicited.
- **N4.** Blocks: the existing machinery already covers the *recipient-blocked-the-actor* direction
  at read time (D10 list filter, SSE gate). With R2, no row is created in either direction anyway.
- **N5.** Rate: in addition to the existing 720/hour per actor→recipient pair, a **per-actor mention
  budget** (recommendation: 60 resolved mentions per hour). The pair limit does not bound fan-out;
  the per-comment cap (W3) and the per-actor budget together do.
- **N6.** Edit: re-tokenize; **notify only newly added recipients**; never re-notify an existing
  one; removed mentions keep their old notification (deleting it would be a second write for a
  marginal case — *(open — D8)*).
- **N7.** Delete: the existing `comment_preview` nulling covers `mention` rows because they carry the
  same `comment_id`. Hide-by-mod: unchanged from `comment`/`comment_reply` (row stays; the post page
  simply no longer shows the comment).
- **N8.** Deleted recipient accounts: `users.id` cascade already deletes their notifications;
  `comment_mentions.user_id` should cascade too. Deleted *actor* accounts: `actor_id` goes NULL like
  every other type; the tile renders an inert avatar.

### 5.4 Rendering

- **V1.** Wherever a comment body renders (`comments_section.dart`, used by both the artwork detail
  page and the full-screen comments page), each `@handle` token whose handle (case-insensitively)
  appears in `mentions` becomes a tappable span opening `ProfilePage(sqid)`. Tokens not in the
  sidecar stay plain text (the cap overflow, unresolvable handles, blocked users, anonymous-author
  edge cases all fall here, uniformly).
- **V2.** Style: the handle color already used for tappable handles (the comment author line and
  `by @owner` on the comments page), no underline, same font size as the body.
- **V3.** The notification tile: "**@U1** mentioned you in a comment on *Title*: *preview*", actor
  avatar left, artwork thumbnail right, whole tile opens P (matching `comment`/`comment_reply`).
  *(open — D11)* Scroll-to-comment on open is not implemented for any comment type today and stays
  out of scope.
- **V4.** The website does the same in `CommentsAndReactions.tsx` and `pages/notifications.tsx`
  (server team). Because of Option A, the app can ship before the website does and vice versa.

### 5.5 Discovery and rollout

- **G1.** Launch signal: `GET /config` gains `max_mentions_per_comment` (the W3 cap). The app
  enables autocomplete and the composer hint only when the key is present, and linkifies from
  `mentions` whenever the field is present (which is harmless before the key exists). Same mechanism
  as mod-hashtags.
- **G2.** Rollout order that never shows anything broken: server (tokenizer + sidecar + type,
  behind nothing — additive) → app renderer + tile (reads `mentions`, tolerant of its absence) → app
  composer autocomplete (gated on G1) → website. Each step is independently releasable.

---

## 6. The contract to send to the server team (sketch)

To be turned into `messages/000N-mentions/0001-app-mentions-proposal.md` once
[`DECISIONS.md`](DECISIONS.md) is answered. The parts the server team decides are marked.

### 6.1 Tokenizer grammar (shared, pinned with test vectors)

A mention token is:

- `@`, preceded by start-of-text or a character that is **not** a handle character
  (so `me@example.com` and `a@b` are not mentions);
- followed by the maximal run of handle characters (Unicode letter, decimal digit, combining
  mark, `-`, `_`);
- the run is then trimmed of trailing `-` and `_` (a handle cannot end with them, so `@fab_` is
  `@fab` + `_`);
- a trimmed run shorter than 3 or longer than 32 code points is not a token (never truncated).

Test vectors both tokenizers must pass (`app/test/`, `api/tests/`):

| Input | Tokens |
|---|---|
| `hi @fab!` | `fab` |
| `(@fab)` · `@fab, @mika.` | `fab` · `fab`, `mika` |
| `me@example.com` · `a@b` | none |
| `@fab_` · `@_fab` | `fab` · none (leading `_` invalid) → *(server decides: none, or `fab`)* |
| `@Fab` when the user is `fab` | `Fab` resolves to `fab` (skeleton) |
| `@fаb` (Cyrillic а) | resolves to `fab` (skeleton fold), text stays as written |
| `@ab` | none (too short) |
| `@makapix-user-12` | `makapix-user-12` |
| `email @fab@mika` | `fab` only (second `@` not at a boundary) |
| `@` + 33 handle chars | none (too long; not truncated to 32) |

Dart: `RegExp` with `unicode: true` and `\p{L}\p{N}\p{M}` classes. Python: per-character
`unicodedata.category`, which `handle_normalize.py` already does.

### 6.2 Wire changes (all additive)

- `Comment` payload (list, create, update responses): `mentions: [{handle, public_sqid}]`, always
  present, possibly empty. `handle` is the handle **as it was at write time**; `public_sqid` is the
  stable link target.
- `GET /config`: `max_mentions_per_comment` (integer).
- `NotificationType.MENTION = "mention"` with the `comment_reply` field shape (§5.3 N1).
- `POST`/`PATCH` comment: no request change. No new endpoint.

### 6.3 Server-side storage (server team's call)

`comment_mentions (comment_id UUID FK cascade, user_id int FK cascade, handle_at_mention
varchar(50), created_at, PRIMARY KEY (comment_id, user_id))`. Loaded with the comment list via
`selectinload`, one query per page. Tiny.

---

## 7. Costs

Estimates for a first shippable version, assuming the recommendations above. Three teams, each
independently releasable.

| Where | Work | Estimate |
|---|---|---|
| **Server** | tokenizer + skeleton resolution + visibility/block rules (R1–R3) · `comment_mentions` migration · `mentions` on the schema · `mention` type + precedence + guards + budgets (N1–N6) · `max_mentions_per_comment` on `/config` · edit diff · tests (mirroring `test_comment_author_sqid.py` / `test_blocks.py`) · `docs/http-api/notifications.md` + `posts.md` | 1.5–2.5 days |
| **Website** | linkified body in `CommentsAndReactions.tsx` (+ the UMD recent-comments panel if wanted) · `mention` copy on the notifications page · optional composer autocomplete | 0.5 day, +1 with autocomplete |
| **App** | `mentions` on `Comment` + tokenizer + `Text.rich` renderer with recognizer lifecycle (`comments_section.dart`) · notification tile copy · composer autocomplete overlay (thread participants + `/user/browse`, debounce, cancel, cap hint) · `/config` gate · unit tests (tokenizer vectors, model parsing, tile text) | 2–3 days |
| **Coordination** | contract thread (`messages/`), dev-server verification, STATUS/CLAUDE doc updates, store release cadence (Play same day; App Store review 1–3 days) | 0.5 day |

Total: about **5–7 developer-days** across the three codebases, plus release latency. Runtime cost
is negligible: at most 5 indexed lookups and 5 notification rows per comment, one extra
`selectinload` per comment page, one `/user/browse` call per autocomplete keystroke after debounce.
Storage: a few dozen bytes per mention.

What makes it more expensive than it looks: the autocomplete overlay in Flutter (positioning above
the keyboard inside a `SingleChildScrollView`, keeping the caret, handling the trailing-space
replacement) is the single largest app item, and the only one with UI polish risk. Everything else is
plumbing with existing precedents in the repo.

---

## 8. Risks

Ordered by how much they would hurt.

1. **Unsolicited-ping channel (abuse).** Today nobody can put a notification in your inbox without
   you having posted, commented, or followed. Mentions change that. Mitigations in v1: the per-comment
   cap (W3), the per-actor budget (N5), block symmetry (R2), no anonymous pings (W4), and the existing
   comment report flow. Not in v1 but the server should be designed to honor it later: a per-user
   "who can mention me" setting (everyone / people I follow / nobody). The app has no notification
   preferences UI at all today, so that setting is a small feature of its own.
2. **Leaking filtered or invisible content into an inbox.** Covered by N3. Without it, the artwork
   thumbnail in the notification bypasses the monitored-hashtag filter and the pending-approval
   queue.
3. **Tokenizer divergence between Dart and Python on Unicode.** Two implementations of one grammar
   will drift on combining marks, confusables, and boundaries unless the vectors in §6.1 are in both
   test suites and the contract freezes them. The failure mode is quiet: a mention links on one
   client and not on the other.
4. **Double notification** (owner or parent author also mentioned). Covered by N2; if the owner
   prefers two rows, that is a one-line change, but it should be a deliberate choice.
5. **Stale handle text after a rename.** Inherent to Option A and accepted (§4). The link stays
   correct; only the text ages. Never re-resolve from text.
6. **Cross-client mismatch during rollout.** With Option A this is cosmetic (a handle that is a link
   on one client and text on another). With Option B it would be raw markup on the website, which is
   why B is rejected.
7. **Expectation mismatch: no OS push.** A mentioned user is only told when they next open the app or
   site. This is true of every notification type today and is fine, but "mention" carries a stronger
   real-time expectation from other products. Worth one line in the release notes.
8. **Autocomplete traffic.** `/user/browse` is a substring `ILIKE` on an indexed column, auth-only,
   already used by the Search page. With debounce and cancellation the load is one query per
   completed word, not per keystroke. If it ever matters, the app can prefer thread participants and
   only call the server after 2+ characters.
9. **Edit-to-add-mentions.** A 2-year-old comment can be edited to mention someone today, and they
   get pinged. N6 (diff-only) and N5 (budget) bound it; the alternative (no notifications from edits
   at all) is simpler and defensible — *(open — D8)*.

No memory, battery, engine, or FFI impact: this is pure Club (`app/lib/club/`), and Club unit tests
keep running without the engine binary.

---

## 9. Alternatives and staging

- **Ship the link without the notification first** (Option C as a release). Not recommended: users
  who see `@handle` become a link will assume the other person was told. The renderer *should* be
  built first, but against the dev server's `mentions` field, not against a client-side resolver.
- **Reuse `comment` instead of a new type.** Rejected: both clients switch on `notification_type`
  for copy and glyphs; a flag would need every switch to grow a branch.
- **Resolve on read instead of storing.** Rejected: rename + reuse of a handle would silently
  redirect old mentions (§4).
- **Mentions in post descriptions and bios.** The grammar and renderer are reusable as-is; the
  server rules (cap, budget, guards) transfer unchanged; only the notification's content fields differ
  (the post itself). A natural v2 once comments prove out. Not in v1 because descriptions are edited far
  more often than comments and the edit-diff rules (N6) need real usage first.
- **"Who can mention me" setting.** v2. Design the server check as one function so the setting is a
  single added condition in R2.
- **Scroll-to-comment on notification tap.** Benefits `comment`, `comment_reply`, `comment_like`
  and `mention` alike; a separate small effort that should not be attached to this one.

---

## 10. Code touch-points (for the implementer, both repos)

**App (`makapix-app`):**

- `app/lib/club/models/comment.dart` — `CommentMention` + `mentions` on `Comment` (tolerant of
  absence, like every other optional field).
- `app/lib/club/ui/widgets/comments_section.dart` — body renderer (`Text.rich`, recognizer
  disposal), composer autocomplete overlay, cap hint; both the detail page and `comments_page.dart`
  render through this widget, so there is one place.
- `app/lib/club/ui/notifications_page.dart` — the `mention` case in `_text` (the tile's links need
  nothing).
- `app/lib/club/models/server_config.dart` — `maxMentionsPerComment`.
- New pure-Dart `app/lib/club/models/mention_tokenizer.dart` (or under `ui/widgets/`), unit-tested
  with the §6.1 vectors in `app/test/`.
- `STATUS.md` C1 rows and `CLAUDE.md`'s C6 line when it ships.

**Server (`makapix`), for the contract thread:** `api/app/routers/comments.py` (create/update),
`api/app/services/social_notifications.py`, `api/app/constants.py` (`NotificationType`),
`api/app/schemas.py` (`Comment`, config), `api/app/models.py` + one Alembic migration,
`api/app/utils/handle_normalize.py` (reuse the skeleton), `web/src/components/CommentsAndReactions.tsx`,
`web/src/pages/notifications.tsx`, `docs/http-api/notifications.md`, `docs/http-api/posts.md`.
