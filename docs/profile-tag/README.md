# Mentions in comments ("profile tag") — design

**Status:** design only, nothing implemented. Written 2026-09-17 to scope the feature before any
code or any message to the server team; revised the same day after the owner settled the first four
decisions (name, representation, notification dedupe, autocomplete source — see
[`DECISIONS.md`](DECISIONS.md), which also holds the questions still open).

**Working name:** this folder is called `profile-tag` because that is how the feature was first
described. The product name is **mention** (D1). Renaming the folder is D16.

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

---

## 2. Naming (decided: "mention", D1)

"Tag" is already taken in this product. The server, the website, and the app all say **tag** for
hashtags: `post.hashtags`, `post.mod_hashtags`, the "Tagged by a moderator" legend, the
`mod_hashtags_updated` notification copy ("A moderator changed the hashtags on…"), and the Settings
page for monitored hashtags. A "tag" that means a person would be ambiguous in every conversation,
commit message, and notification string from here on.

| Name | Used by | Fit |
|---|---|---|
| **mention** | X/Twitter, Mastodon, Slack, Discord, GitHub, Reddit ("u/"), Instagram *comments* | The de-facto term for "@handle in text"; "mentioned you in a comment" reads naturally; no collision |
| tag | Instagram/Facebook *photos* | Collides with hashtags here; also implies attaching a person to the artwork, which this is not |
| callout / shout-out | informal | Reads as praise, not as a reference |
| ping | Discord slang | Too technical, and it names the notification rather than the link |

Notification type `mention`, UI copy "@U1 mentioned you in a comment on *Title*", contract and docs
titled "mentions". "Tag" stays reserved for hashtags.

---

## 3. What exists today (the parts a mention rides on)

Everything a mention needs already exists except the mention itself.

**Comments.** `POST /post/{id}/comments` takes `{body, parent_id?}`, body 1–2000 characters
(`schemas.CommentCreate`). The body is stored and returned as plain text; **no client renders any
markup in comment bodies.** The website prints `comment.body` verbatim in three places
(`components/CommentsAndReactions.tsx`, `components/SPOCommentsOverlay.tsx`, the moderation
`umd/RecentCommentsPanel.tsx`); the app does `Text(c.body)` once, in
`app/lib/club/ui/widgets/comments_section.dart`, which both the artwork detail page and the full-screen
comments page render through. Comments carry `author_handle`, `author_public_sqid`,
`author_avatar_url` (flat fields; `models/comment.dart`). Anonymous (signed-out) commenters exist on
the website and are attributed to an IP; the app composer is sign-in only. Rate limit: 30 comments per
5 minutes per user or IP. Profanity filter on the body. Edits: `PATCH /post/comments/{id}`
(authenticated authors only). Deletes tombstone the body and null every notification's
`comment_preview` for that `comment_id`.

**Handles and identity.** Handles are 3–32 code points; Unicode letters in any script, digits,
combining marks, `-` and `_`; must contain a letter or digit; may not start or end with `-`/`_`
(`api/app/utils/handle_normalize.py`). Uniqueness is by a **confusable skeleton**
(`users.handle_normalized`: casefold + NFKC + a non-ASCII homoglyph fold), so `Fab`, `fab`, and
Cyrillic `fаb` are the same handle. **Handles are mutable:** a user can rename via `PATCH /user/{key}`
(the site owner cannot). The stable identity is `public_sqid` (Sqids, alphabet in
`api/app/sqids_config.py`); profiles resolve only by sqid (`GET /user/u/{sqid}/profile`). There is no
lookup by handle.

**User search.** `GET /user/browse?q=` (auth required, `ILIKE %q%` on handle, sorted
alphabetical/recent/reputation) backs the app's Search page. It hides unverified, hidden, deactivated,
non-conformant, and banned users, the site owner, and users the viewer has blocked.
`GET /search?types=users` is a trigram-similarity variant. Neither ranks by context (thread, follow
graph), which is why D13 asks for a dedicated endpoint.

**Notifications.** One table (`social_notifications`) with denormalized display fields:
`actor_*`, `content_title/sqid/art_url`, `comment_id`, `comment_preview` (first 100 chars),
`post_id`. Types are the `NotificationType` enum in `api/app/constants.py`; the column is free text,
so a new type needs no migration. Delivery: the row, then an in-process SSE bus push
(`GET /realtime/notifications`), consumed by the app while foregrounded (`state/notifications_sse.dart`),
with a 60-second poll as fallback. **There is no OS push (no FCM/APNs) in the app**, so a mention is
seen when the user next opens the app or the website. Unread count and list are block-filtered by
actor (ugc-safety D10).

**How the clients render an unknown notification type today.** `NotificationsPage._text` falls to
`'$who · $type'` and the tile still deep-links to the post via `content_sqid`. The website falls to
"X interacted with *Title*". A server that emits `mention` before the clients update is ugly but not
broken.

**Blocks.** Symmetric interaction refusal (D11: comment/reaction/like/follow return `403 blocked`
between two users with a block in either direction) and one-way visibility (D10: the blocker never
sees the blocked user's content, notifications included; the rows are still written so unblocking
reveals history). Live SSE delivery is gated the same way.

**Feature discovery.** The repo's launch-signal pattern is a key on `GET /config`
(`max_mod_hashtags_per_post` gated the mod-hashtags UI; `moderation` gates report/block). The app
enables a feature's UI when the key appears on `development.makapix.club`, and its appearance on
`makapix.club` is the production launch.

**Client identification.** Every app request carries `User-Agent: MakapixClub/<version>+<build> (…)`
(`api/club_user_agent.dart`). The server matches it only to bucket device types
(`api/app/utils/view_tracking.py`); it does not parse the version. Version-gating a payload by
User-Agent would be new server work and is not proposed (§4.3).

---

## 4. Representation (decided: inline markup with the sqid, D2)

The owner chose inline markup carrying the stable id over the plain-text-plus-sidecar alternative
(kept in §4.4 for the record). This section is the design of that choice.

### 4.1 The markup

A mention is written in the stored body as

```
@[handle](u:SQID)
```

Example body: `great palette @[fab](u:t5), see @[mika](u:Qx)'s remix`.

- `@[` … `]` holds the **display handle**; `(u:` … `)` holds the user's `public_sqid`. The `u:`
  prefix leaves room for other reference kinds later (`p:` for posts) without a second grammar.
- The form deliberately mirrors the bio mini-markdown that both codebases already parse
  (`[text](url)` in `widgets/markdown_bio.dart` / `MarkdownBio.tsx`), so the parser shape and the
  "unknown or malformed markup renders as plain text" rule are familiar.
- **The sqid is the truth; the handle text is decoration.** On every write the server replaces the
  bracketed text with the current handle of the user that sqid resolves to. A body that claims
  `@[fab](u:XX)` where `XX` is not fab becomes `@[<XX's real handle>](u:XX)`. Without this rule the
  markup is a phishing primitive (a link that says one name and opens another profile).
- A markup whose sqid does not resolve to a **mentionable** user (§5.2) is flattened to plain
  `@handle` text before storage. It never links and never notifies. No error is returned, so the
  markup can never be used to probe who blocked whom.
- Literal `@[` in ordinary text that is not followed by a valid `](u:…)` is plain text.
- The 2000-character body limit applies to the stored (markup) form. A mention costs roughly
  `handle + sqid + 7` characters; five mentions of long handles use under 250 characters.

### 4.2 Why this and not `<@SQID>` or `@handle{sqid}`

The bracket form degrades best on a client that has not been updated: `@[fab](u:t5)` still reads as
"fab". A handle-less token like `<@t5>` degrades to noise. A form without brackets cannot delimit
Unicode handles safely.

### 4.3 Compatibility: what the three legacy surfaces see

The cost of inline markup is that every reader that prints `body` verbatim — the website's three
comment surfaces, every app build in the field, and `comment_preview` in every notification — shows
raw markup until it is updated. Three ways to handle it were weighed:

| Strategy | What legacy clients see | Cost |
|---|---|---|
| **Dual field (recommended, D18)** | `body` keeps being a **plain rendering** (`@fab`); a new `body_markup` carries the source. New clients render `body_markup`; old ones are untouched | one derived field on the schema, computed at read from the stored source |
| Transition window | raw `@[fab](u:t5)` on the website until its PR lands and on old app builds forever | zero server work; cosmetic damage proportional to how long the website lags and to the app's update tail |
| Version-gate by User-Agent | plain for old, markup for new | new UA-version parsing on the server, fragile, still leaves the website until updated |

With the dual field the rollout is order-independent again and `comment_preview` is derived from the
plain rendering with no extra rule. One consequence to accept: an **edit from a legacy client** sends
back the plain `body` it displayed, so the server stores that and the comment's mentions are lost.
Edits are rare, the website is expected to update within the same release cycle, and the loss is
visible only as a handle that stopped being a link (D18 asks whether that is acceptable or whether
the server should refuse a plain-body edit of a comment that has mentions).

Request side: `POST`/`PATCH` keep the single `body` field and accept markup in it. A client that
never writes markup is unaffected.

### 4.4 The alternative not taken (plain `@handle` text + a stored sidecar)

Body stays what the user typed; the server tokenizes `@handle`, resolves it against the handle
skeleton at write time, stores `(comment_id, user_id, handle_at_mention)`, and returns
`mentions: [{handle, public_sqid}]`; clients linkify matching tokens. It needs no compatibility field
and lets hand-typed handles mention, but it needs two tokenizers (Dart and Python) that agree on
Unicode boundaries, and its text goes stale on rename with no way to refresh it. The owner chose the
markup for its exactness (D2). Nothing else in this document depends on the choice not taken.

### 4.5 A benefit the markup buys: rename-proof text

Because the stored form carries the sqid, the server can refresh the display handle **at read time**
too (resolve each distinct sqid in a page of comments; one `selectinload`-sized query). After U3
renames, every old mention of them reads with the new handle, in both `body` and `body_markup`. This
is proposed as the default (D20); the plain-text alternative could not do it.

---

## 5. Proposed behavior (v1)

Numbered so [`DECISIONS.md`](DECISIONS.md) can refer to them. Items marked *(open)* are decisions
for the owner; the text states the recommended answer.

### 5.1 Writing a mention

- **W1.** The user types `@` and picks a person from the candidates list; the composer inserts the
  mention. **A mention exists only if it was picked** (or pasted as valid markup). A hand-typed
  `@fab` that was never picked is plain text: it does not link and does not notify (D19). This is how
  Instagram, Slack, and Discord behave, and it is what makes the markup decision consistent: the
  server never guesses from text.
- **W2.** Candidates come from a new `GET /user/mention-candidates` (§6.2; D13): the post owner and
  the thread's participants first, then people the commenter follows and is followed by, then a
  prefix match on the handle skeleton. Requested on `@` (empty query returns the contextual set) and
  on every keystroke inside the token, debounced 250 ms, previous request cancelled, at most 8 rows.
- **W3.** *(open — D5)* At most **5 mentions per comment** (`max_mentions_per_comment`). The server
  flattens extras to plain text rather than rejecting the comment; the composer stops offering
  candidates once the cap is reached and says why.
- **W4.** *(open — D4)* Anonymous (signed-out, IP-attributed) commenters: their mentions link but
  never notify. An unaccountable ping is a harassment vector with no recourse.
- **W5.** Self-mention links but never notifies (the existing self-action rule).
- **W6.** In the app's `TextField` the user sees `@fab`, never the markup. The composer keeps a
  display string plus the list of picked `(handle, sqid)` pairs; on send it serializes each picked
  handle that is still present as a token into markup. If the user edits a picked handle's characters
  the pair is dropped and the text becomes plain (§10 has the mechanics).

### 5.2 Resolving (server, on create and on edit)

- **R1.** Parse the markup; deduplicate by sqid; resolve each sqid to a user.
- **R2.** *(open — D3)* A sqid is **mentionable** for the commenter when the user is exactly what
  `/user/browse` would show them: email-verified, not hidden by user or moderator, not deactivated,
  not banned, not non-conformant, **and no block in either direction** with the commenter. The site
  owner is hidden from browse today; D3 asks whether they should be mentionable anyway. Anyone else
  is flattened to plain text, silently (§4.1).
- **R3.** Canonicalize the display handle from the resolved user (§4.1). Store the normalized
  markup body. No side table is needed: the body is the record; edit diffs parse old and new.

### 5.3 Notifying

- **N1.** New `NotificationType.MENTION = "mention"`. Fields: actor = commenter (handle, avatar,
  sqid), `post_id` + `content_title/sqid/art_url` = P, `comment_id` = C, `comment_preview` = first
  100 chars of the **plain** rendering. This is byte-for-byte the shape of `comment_reply`, so both
  clients' whole-tile deep link (post page) and avatar link (actor profile) work without new fields.
- **N2 (decided, D6).** **One notification per recipient per comment.** If the recipient already
  receives `comment` (they own P) or `comment_reply` (they wrote the parent) for C, the `mention` row
  is skipped. Precedence: `comment_reply` > `comment` > `mention`.
- **N3.** *(open — D7)* **Visibility guard.** No notification when the recipient cannot access P
  (`can_access_post`: hidden, pending approval, soft-deleted) **or when P carries a monitored hashtag
  the recipient has not opted into** (`approved_hashtags`). Without this a mention puts an `#nsfw`
  thumbnail into the inbox of someone with that filter on. `comment_reply` has no such guard because
  its recipient chose to be in that thread; a mention is unsolicited.
- **N4.** Blocks: R2 means no row is ever written in either direction; the existing D10 list filter
  and SSE gate remain as a second line.
- **N5.** Rate: in addition to the existing 720/hour per actor→recipient pair, a **per-actor mention
  budget** (recommendation: 60 notified mentions per hour). The pair limit does not bound fan-out;
  the per-comment cap and the per-actor budget together do.
- **N6.** *(open — D8)* Edit: parse old and new bodies; **notify only newly added recipients**;
  never re-notify; removed mentions keep their old notification.
- **N7.** Delete: the existing `comment_preview` nulling covers `mention` rows because they carry the
  same `comment_id`. Hide-by-mod: unchanged from `comment`/`comment_reply`.
- **N8.** Deleted recipient accounts: `users.id` cascade already deletes their notifications; their
  sqid stops resolving, so old markup renders (§4.5) as plain text. Deleted *actor* accounts:
  `actor_id` goes NULL like every other type; the tile renders an inert avatar.

### 5.4 Rendering

- **V1.** The app parses `body_markup` (falling back to `body` when absent, which renders as today)
  into spans; each mention becomes a tappable span opening `ProfilePage(sqid)`; malformed markup is
  plain text. One place: `comments_section.dart`.
- **V2.** Style: the handle color already used for tappable handles (the comment author line and
  `by @owner` on the comments page), no underline, body font size.
- **V3.** Notification tile: "**@U1** mentioned you in a comment on *Title*: *preview*", actor avatar
  left, artwork thumbnail right, whole tile opens P (matching `comment`/`comment_reply`).
  *(open — D9)* Scroll-to-comment on open is not implemented for any comment type and stays out of
  scope.
- **V4.** The website does the same on its three comment surfaces and on `pages/notifications.tsx`
  (server team). With the dual field neither client is blocked on the other.

### 5.5 Discovery and rollout

- **G1.** Launch signal: `GET /config` gains `max_mentions_per_comment`. The app enables the
  composer's `@` candidates only when the key is present, and renders `body_markup` whenever the field
  is present (harmless before the key exists).
- **G2.** Rollout order that never shows anything broken: server (parser + dual field + type +
  candidates endpoint; all additive) → app renderer + tile (reads `body_markup`, tolerant of its
  absence) → app composer (gated on G1) → website. Each step is independently releasable. Without
  the dual field (D18) the website must ship no later than the first app build that writes markup.

---

## 6. The contract to send to the server team (sketch)

To be turned into `messages/000N-mentions/0001-app-mentions-proposal.md` once the remaining decisions
are settled (D15). The parts the server team decides are marked.

### 6.1 Markup grammar (shared, pinned with test vectors)

```
mention  := "@[" handle "](u:" sqid ")"
handle   := 3–32 code points from { Unicode letter, decimal digit, combining mark, "-", "_" }
sqid     := 1+ characters from the configured Sqids alphabet
```

Rules: no nesting; no whitespace inside; anything that fails the grammar is plain text; the server
rewrites `handle` from the resolved user on write and on read; a non-mentionable or unknown sqid is
flattened to `@handle` (plain). Test vectors both parsers must pass (`app/test/`, `api/tests/`):

| Stored body | Renders as | Notes |
|---|---|---|
| `hi @[fab](u:t5)!` | hi **@fab**! | link → `/u/t5` |
| `@[fab](u:t5), @[mika](u:Qx).` | **@fab**, **@mika**. | two mentions |
| `@[wrong](u:t5)` | **@fab** | handle canonicalized on write (§4.1) |
| `@[fab](u:ZZZZ)` (unknown sqid) | @fab | flattened on write; plain text |
| `@[fab](u:t5` · `@[](u:t5)` · `@[fab](t5)` | as written | malformed → plain text |
| `@fab` | @fab | plain text: never picked (W1) |
| `me@[example](u:t5)` | me**@example**… | server decides: allow (no boundary rule needed with brackets) |
| 6 valid mentions | first 5 link | cap (W3); the sixth is flattened |

### 6.2 New endpoint: `GET /user/mention-candidates` (server team's design; this is the ask)

- Auth required. Query: `q` (optional prefix, matched on the handle skeleton so casing and
  confusables behave like uniqueness), `post_id` (optional; enables the contextual tiers),
  `limit` (default 8, max 20).
- Response: `{"items": [{"handle", "public_sqid", "avatar_url", "reason"}]}` where `reason` is one
  of `owner` · `thread` · `following` · `follower` · `search`, in that rank order, then alphabetical.
- Excludes: the caller, anyone not mentionable for the caller (§5.2 R2). *(D3: the site owner?)*
- Rate limit suggestion: 120 requests/minute per user (one debounced request per keystroke).
- No caching (the contextual tiers are per caller and per post).

### 6.3 Wire changes (all additive)

- `Comment` payload (list, create, update responses): `body_markup` (string, always present when the
  server has the feature; equals `body` when the comment has no mentions). `body` remains the plain
  rendering (D18).
- `POST`/`PATCH` comment: `body` accepts markup. No new request field.
- `GET /config`: `max_mentions_per_comment` (integer; the launch signal).
- `NotificationType.MENTION = "mention"` with the `comment_reply` field shape (§5.3 N1).

### 6.4 Server-side storage (server team's call)

No new table. `comments.body` stores the normalized markup; the plain rendering is derived. If the
team prefers not to derive on every read, a `body_plain` column kept in sync on write is the obvious
alternative; either is invisible to the clients.

---

## 7. Costs

Estimates for a first shippable version under the decisions taken so far and the recommendations
above. Three teams, each independently releasable.

| Where | Work | Estimate |
|---|---|---|
| **Server** | markup parser + canonicalization + flattening (R1–R3) · dual `body`/`body_markup` on the schema (+ read-time handle refresh, D20) · `mention` type + precedence + guards + budgets (N1–N6) · **`/user/mention-candidates`** with the four contextual tiers · `max_mentions_per_comment` on `/config` · edit diff · tests (mirroring `test_comment_author_sqid.py` / `test_blocks.py`) · `docs/http-api/` updates | 2.5–3.5 days |
| **Website** | markup renderer on three comment surfaces · `mention` copy on the notifications page · composer with candidates (must also write markup, or its edits strip mentions, §4.3) | 1.5–2 days |
| **App** | `bodyMarkup` on `Comment` + markup parser + `Text.rich` renderer with recognizer lifecycle (`comments_section.dart`) · notification tile copy · **composer**: `@` detection, candidates overlay, display-text ↔ picked-pairs model, serialization on send, cap hint · `/config` gate · unit tests (grammar vectors, model parsing, serializer round-trip, tile text) | 3–4 days |
| **Coordination** | contract thread (`messages/`), dev-server verification, STATUS/CLAUDE doc updates, store release cadence (Play same day; App Store review 1–3 days) | 0.5 day |

Total: about **8–10 developer-days** across the three codebases, plus release latency. That is
roughly three days more than the plain-text alternative, spent on the candidates endpoint (owner's
choice, D13) and on the composer having to hide markup from the user (a consequence of D2). Runtime
cost stays negligible: one sqid resolution per distinct mention per comment page, at most 5
notification rows per comment, one debounced candidates query per keystroke.

The single largest app item is the composer: an overlay anchored to the caret inside a
`SingleChildScrollView` above the keyboard, plus keeping the picked-pairs model consistent through
edits, cursor moves, and paste. Everything else has a precedent in the repo (`markdown_bio.dart` for
spans, the Search page for candidate lists, the notification tiles for the copy).

---

## 8. Risks

Ordered by how much they would hurt.

1. **Unsolicited-ping channel (abuse).** Today nobody can put a notification in your inbox without
   you having posted, commented, or followed. Mentions change that. Mitigations in v1: the per-comment
   cap (W3), the per-actor budget (N5), block symmetry (R2), no anonymous pings (W4), and the existing
   comment report flow. Not in v1 but the server should be designed to honor it later: a per-user
   "who can mention me" setting (D11). The app has no notification-preferences UI at all today.
2. **Spoofed display handles.** Inline markup lets a body claim any handle for any sqid. Closed by
   canonicalizing the handle from the sqid on write and read (§4.1). This rule is not optional.
3. **Leaking filtered or invisible content into an inbox.** Covered by N3. Without it, the artwork
   thumbnail in the notification bypasses the monitored-hashtag filter and the pending-approval
   queue.
4. **Raw markup on legacy readers.** Inherent to D2; neutralized by the dual field (D18). Without
   it the website shows `@[fab](u:t5)` until its PR ships and old app builds show it for as long as
   they are installed.
5. **Legacy edits strip mentions.** A client that does not know the markup writes back the plain body
   (§4.3). Bounded by how quickly the website adopts the composer; D18 offers a server-side refusal
   as the strict alternative.
6. **Double notification** (owner or parent author also mentioned). Closed by D6.
7. **Parser divergence between Dart, TypeScript, and Python.** Three implementations of one grammar.
   The bracket grammar is far simpler than a Unicode word-boundary tokenizer, and the §6.1 vectors go
   into all three test suites, but the risk is the same in kind: a body that links on one client and
   not on another.
8. **Expectation mismatch: no OS push.** A mentioned user is only told when they next open the app or
   site. True of every notification type today; "mention" just carries a stronger real-time
   expectation from other products. One line in the release notes.
9. **Edit-to-add-mentions.** A two-year-old comment can be edited to mention someone. N6 (diff-only)
   and N5 (budget) bound it; D8 offers "edits never notify" as the simpler alternative.
10. **Candidates endpoint as a directory.** An empty `q` with a `post_id` lists the thread's
    participants and the caller's graph, which is information the caller can already see on the post
    and on their own profile. A prefix query without `post_id` is `/user/browse` with better ranking.
    No new exposure, but the endpoint should apply exactly the browse visibility filters.

No memory, battery, engine, or FFI impact: this is pure Club (`app/lib/club/`), and Club unit tests
keep running without the engine binary.

---

## 9. Alternatives and staging

- **Ship the link without the notification first.** Not recommended: users who see `@handle` become
  a link assume the other person was told. The renderer *should* be built first, against the dev
  server's `body_markup`.
- **Reuse `comment` instead of a new type.** Rejected: both clients switch on `notification_type`
  for copy and glyphs; a flag would need every switch to grow a branch.
- **Let hand-typed `@handle` also mention (server-side text resolution).** Rejected as inconsistent
  with D2: it would need the tokenizer the markup was chosen to avoid, and it would make "did this
  mention or not" depend on whether a handle happened to exist. D19 records it.
- **Mentions in post descriptions and bios.** The grammar, renderer, canonicalization, and guards
  transfer unchanged; only the notification's content fields differ (the post itself). A natural v2
  once comments prove out. Descriptions are edited far more often than comments, so the edit rules
  (N6) need real usage first.
- **"Who can mention me" setting.** v2 (D11). Write the R2 check as one function so the setting is a
  single added condition.
- **Scroll-to-comment on notification tap.** Benefits `comment`, `comment_reply`, `comment_like`, and
  `mention` alike; a separate small effort.

---

## 10. Code touch-points (for the implementer, both repos)

**App (`makapix-app`):**

- `app/lib/club/models/comment.dart` — `bodyMarkup` (nullable; absent on old servers).
- New pure-Dart `app/lib/club/models/mention_markup.dart`: `parse(String) → List<Segment>`
  (text | mention{handle, sqid}) and `serialize(displayText, pickedPairs) → String`. Unit-tested
  with the §6.1 vectors and a serialize→parse round trip.
- `app/lib/club/ui/widgets/comments_section.dart` — body renderer (`Text.rich` with a
  `TapGestureRecognizer` per mention, disposed with the widget) and the composer. Composer
  mechanics: listen to the `TextEditingController`; when the caret sits inside an `@`-led token, query
  candidates and show an overlay (`CompositedTransformFollower` anchored to the field); on pick,
  replace the token with `@handle ` and record `(handle, sqid)`; on send, serialize only the pairs
  whose `@handle` token still appears intact. The field itself shows plain text throughout, so no
  custom controller is needed.
- `app/lib/club/api/search_api.dart` (or a new `mentions_api.dart`) — `mentionCandidates(q, postId)`.
- `app/lib/club/ui/notifications_page.dart` — the `mention` case in `_text` (the tile's links need
  nothing).
- `app/lib/club/models/server_config.dart` — `maxMentionsPerComment`.
- `STATUS.md` C1 rows and `CLAUDE.md`'s C6 line when it ships.

**Server (`makapix`), for the contract thread:** `api/app/routers/comments.py` (create/update),
`api/app/routers/users.py` (candidates endpoint), `api/app/services/social_notifications.py`,
`api/app/constants.py` (`NotificationType`), `api/app/schemas.py` (`Comment`, config), a new
`api/app/utils/mentions.py` (parser, canonicalization, flattening), `web/src/components/
CommentsAndReactions.tsx` + `SPOCommentsOverlay.tsx` + `umd/RecentCommentsPanel.tsx`,
`web/src/pages/notifications.tsx`, `docs/http-api/notifications.md`, `docs/http-api/posts.md`,
`docs/http-api/users.md`.
