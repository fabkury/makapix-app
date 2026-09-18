# Mentions — decisions

Decisions taken with the project owner on 2026-09-17 and 2026-09-18, numbered for reference from
[`README.md`](README.md) and from messages to the server team. Section numbers refer to the README.
Nothing is open; the next step is the contract message (D15).

---

## Product decisions

**D1 — Name: "mention".** "Tag" already means hashtag in all three codebases and in notification
copy (§2). Notification type `mention`; UI copy "mentioned you in a comment on…" / "…in the
description of…"; docs and the contract say "mentions". "Tag" stays reserved for hashtags.

**D2 — Representation: inline markup carrying the sqid.** Chosen over plain `@handle` text with a
server-resolved sidecar (§4.4) for exactness. Consequences: D17 (syntax), D18 (compatibility), D19
(hand-typed handles), and about three extra developer-days.

**D3 — Who can be mentioned.** Exactly the users `/user/browse` would show the writer (verified;
not hidden, deactivated, banned, or non-conformant) **plus the site owner**, and nobody with a block
in either direction with the writer. Anyone else is flattened to plain text silently, never a `403`,
so blocks cannot be probed (§5.2).

**D4 — Anonymous commenters cannot mention.** Their markup is flattened on write: neither link nor
notification (§5.1 W4).

**D5 — Caps: 16 per text, 256 notified per writer per hour, flatten extras.** Extras beyond 16 become
plain text; the comment or description is never rejected. The hourly budget sits on top of the
existing 720/hour per actor→recipient pair. `max_mentions_per_text` on `/config` is the launch
signal (§5.1 W3, §5.3 N5).

**D6 — One notification per recipient per comment.** When the mentioned user already gets
`comment` (post owner) or `comment_reply` (parent author) for the same comment, the `mention` row is
skipped. Precedence: `comment_reply` > `comment` > `mention` (§5.3 N2).

**D7 — Visibility guard: skip.** No `mention` notification when the recipient cannot see the post
(hidden, pending approval, deleted) or when the post carries a monitored hashtag they have not opted
into. For descriptions, the server re-evaluates when a pending post becomes visible (§5.3 N3).

**D8 — Edits notify newly added recipients only.** Diff old and new mention sets; never re-notify;
removed mentions keep their old notification (§5.3 N6). Applies to comment edits and description
edits.

**D9 — Tile: same shape as `comment_reply`.** "@U1 mentioned you in a comment on *Title*: *preview*"
(or "…in the description of *Title*"), actor avatar → U1's profile, whole tile → the post page.
Scroll-to-comment stays a separate effort (§5.4 V3, §9).

**D10 — Scope: comments and post descriptions, both fully in v1.** Descriptions get the composer
(publish page and edit-details page), the notification, and the same caps and guards. Bios and
titles are out (§1, §5).

**D11 — "Who can mention me" ships in v1.** `users.mention_policy`: `everyone` (default) ·
`following` (only members the target follows may mention them) · `nobody`. A writer the policy
excludes sees the target flattened to plain text and absent from candidates, exactly like a blocked
user (§5.2).

**D12 — Release order: server → app → website.** Each step independently releasable; the app does
not wait for the website's PR. The dual field (D18) is what makes this safe (§5.5).

---

## Engineering decisions

**D13 — Autocomplete source: a dedicated server endpoint.** `GET /user/mention-candidates` with
contextual tiers (post owner · thread participants · following · followers · prefix search). Details
in D21 and §6.2.

**D14 — Grammar and test vectors frozen in the contract** (§6.1) and present in all three test
suites (Dart, TypeScript, Python).

**D15 — The app team opens the contract thread.** `messages/0003-mentions/0001-app-mentions-
proposal.md` in this repo, carrying §6; the server team mirrors it under `docs/mentions/messages/` in
its repo. The server team has the final say on shared matters (`messages/README.md`).

**D16 — Folder renamed** from `docs/profile-tag/` to `docs/mentions/` (this commit).

**D17 — Markup syntax: `<@SQID>`.** No handle text in the markup; the handle is resolved from the
sqid on every read, so mentions are rename-proof and cannot be spoofed. Chosen over
`@[handle](u:SQID)`; with the dual field (D18) the readability-on-legacy-clients argument for the
bracket form no longer applies (§4.1).

**D18 — Compatibility: dual field; legacy edits may strip mentions.** `body` / `description` stay a
plain rendering (`@handle`); `body_markup` / `description_markup` carry the source. An edit from a
client that does not know the markup writes back the plain text and loses that text's mentions; the
server does not refuse it and does not re-merge (§4.2).

**D19 — Hand-typed handles do not mention.** A mention exists only when picked from the candidates
list (or pasted as valid markup). The server never resolves text (§5.1 W1).

**D20 — Read-time handle resolution: always.** Made mandatory by D17 (there is no stored handle to
freeze). The server includes `mentions: [{public_sqid, handle, avatar_url}]` beside each markup field
so clients resolve nothing themselves (§4.3, §6.3).

**D21 — Candidates endpoint accepted as sketched.** Tiers `owner · thread · following · follower ·
search`; empty `q` allowed; `limit` default 8, max 20; ~120 requests/minute per user; applies the
§5.2 mentionability function exactly (so the site owner appears and policy-excluded users do not);
excludes the caller (§6.2).

---

## Things confirmed while researching (no decision needed)

- Comment bodies and descriptions are plain text on every client today; nothing parses them. A
  mention is the first inline structure either has ever carried, which is why D18 exists.
- Handles are mutable and unique by confusable skeleton; `public_sqid` is the only stable identity
  and the only way to open a profile. The markup carries the sqid for exactly this reason.
- The server already sees the app's version in the User-Agent but does not parse it; UA-based
  gating would have been new work and was not chosen.
- The app has no OS push. Notifications are in-app (SSE while foregrounded, 60 s poll otherwise).
- Both clients render an unknown notification type without crashing (app: "@who · mention" with a
  working post link; website: "X interacted with *Title*"). The server can therefore ship first.
- The existing block machinery already hides a blocked actor's notifications and gates SSE delivery;
  the mentionability function (§5.2) adds the write-time check.
- Deleting a comment already nulls `comment_preview` on every notification with that `comment_id`;
  `mention` rows on comments are covered for free.
- Description length is 5000 on the server (`PostUpdate`); the 1000 seen nearby is the playlist
  schema.
- Nothing here touches the engine, the FFI seam, memory budgets, or the launch path.
