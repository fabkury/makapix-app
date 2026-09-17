# Mentions in comments — open decisions

Questions for the project owner, written 2026-09-17 alongside [`README.md`](README.md) (section
numbers below refer to it). Each item gives the options, the recommendation, and what changes if the
answer differs. Answer inline under **Decision:**; the contract message to the server team is written
only after D1–D8 are settled. The numbering is stable so messages can cite `D6`.

Product decisions first (they shape the contract), then engineering ones (they shape the code).

---

## Product decisions

**D1 — The name.** *Mention* is recommended over *tag* (§2): "tag" already means hashtag in all three
codebases and in the notification copy. This decides the notification type string (`mention`), the
UI copy ("mentioned you in a comment"), and whether this folder is renamed to `docs/mentions/`.
Options: (a) mention · (b) tag · (c) something else.
**Decision:** _pending_

**D2 — Representation.** Option A (plain `@handle` text + a server-resolved, stored `mentions`
sidecar) is recommended (§4). Option B (inline markup with the sqid) is rename-proof but shows raw
markup on every client that has not been updated, including the website today and every app build in
the field. Option C (app-only) cannot notify.
Options: (a) A · (b) B · (c) A now, B never · (d) something else.
**Decision:** _pending_

**D3 — Who can be mentioned.** Recommended: exactly the users who would appear in `/user/browse`
for the commenter (verified, not hidden/deactivated/banned/non-conformant, not the site owner), and
**nobody with a block in either direction** with the commenter; anyone else silently stays plain text
(§5.2 R2). The alternative (refuse the comment with `403 blocked`, as replies to a blocker do today)
tells U1 that U3 blocked them.
Sub-question: should the site owner be mentionable? Browse hides the owner; a mention of `@fab` on
Makapix would be common and presumably welcome.
**Decision:** _pending_

**D4 — Anonymous commenters.** The website allows signed-out, IP-attributed comments. Recommended:
their `@handle` tokens link but never notify (§5.1 W4). Alternatives: (a) as recommended ·
(b) notify with actor "Anonymous", like anonymous replies do today · (c) neither link nor notify.
**Decision:** _pending_

**D5 — Caps.** Recommended: at most **5** resolved mentions per comment (extras stay plain text, the
comment is not rejected), and **60** resolved mentions per actor per hour on top of the existing
720/hour per actor→recipient pair (§5.1 W3, §5.3 N5). Both numbers are `/config`-tunable server
constants; the per-comment cap is the launch signal key. Are 5 and 60 right? Should the server reject
(422) instead of silently not linking the extras?
**Decision:** _pending_

**D6 — One notification per recipient per comment.** Recommended: when the mentioned user already
gets `comment` (post owner) or `comment_reply` (parent author) for the same comment, skip the
`mention` row (§5.3 N2). The alternative is two rows for one comment.
**Decision:** _pending_

**D7 — Visibility guard.** Recommended: no `mention` notification when the recipient cannot see
the post (hidden, pending approval, deleted) or when the post carries a monitored hashtag the
recipient has not opted into (§5.3 N3). Without it a mention puts a filtered thumbnail into the
recipient's inbox. Alternative: notify anyway but strip the thumbnail for that recipient (more code,
same information leak via the title).
**Decision:** _pending_

**D8 — Edits.** Recommended: re-tokenize on edit and notify **only newly added** recipients; removed
mentions keep their old notification (§5.3 N6). Alternatives: (a) as recommended · (b) edits never
notify (simplest, closes the "edit an old comment to ping someone" path entirely) · (c) also delete
the notification when a mention is removed.
**Decision:** _pending_

**D9 — Notification copy and tap target.** Recommended tile: "**@U1** mentioned you in a comment on
*Title*: *preview*", actor avatar → U1's profile, whole tile → the post page (matching every comment
type today). Scroll-to-comment on open is not implemented for any type and is proposed as a separate
small effort (§9). Agree?
**Decision:** _pending_

**D10 — Scope beyond comments.** v1 is comments only. Post descriptions and bios are a natural v2
using the same grammar and rules (§9). Should v1 at least *link* mentions in descriptions (no
notification) so the renderer is written once, or keep descriptions untouched?
**Decision:** _pending_

**D11 — A "who can mention me" setting.** Everyone / people I follow / nobody. Recommended for v2,
with the server check written as one function so it is a one-condition addition later (§8 risk 1).
The app has no notification-preferences UI today, so this is a small feature of its own. Ship it in
v1 anyway?
**Decision:** _pending_

**D12 — Should the app ship the renderer before the website does?** With Option A the answer can be
yes without anything looking broken (a handle is a link on one client and text on the other, §5.5
G2). If you prefer a same-day launch on both, the app should hold its `/config`-gated composer until
the website's PR is on `main`.
**Decision:** _pending_

---

## Engineering decisions

**D13 — Autocomplete source.** Recommended: thread participants first (post owner + loaded comment
authors, zero network), then `GET /user/browse?q=` (substring, 250 ms debounce, cancel on
keystroke, one page, 2+ characters before hitting the server) (§5.1 W2). Alternatives: (a) as
recommended · (b) ask the server team for a dedicated `GET /user/mention-candidates?q=` with
prefix match and follow-graph ranking · (c) no autocomplete in v1, type the handle by hand (cuts the
largest app item, §7).
**Decision:** _pending_

**D14 — Tokenizer grammar.** The §6.1 grammar and test vectors, frozen in the contract, with the two
listed ambiguities for the server team (`@_fab` and over-length runs). Any objection to Unicode
handles in mentions being matched by the same confusable skeleton as handle uniqueness?
**Decision:** _pending_

**D15 — Where the contract lives.** The app repo's `messages/` convention says the server team
opens threads, but the app team opened `notification-actor-sqid` in 2026-07. Recommended: the app
team opens `messages/0003-mentions/0001-app-mentions-proposal.md` with the §6 contract, mirrored by
the server team under `docs/mentions/messages/`. Agree, or should this first be a conversation?
**Decision:** _pending_

**D16 — Rename this folder.** Once D1 is settled, rename `docs/profile-tag/` to match (e.g.
`docs/mentions/`) so the folder name never contradicts the feature name in STATUS.md and commits.
**Decision:** _pending_

---

## Things confirmed while researching (no decision needed)

- Comment bodies are plain text on every client today; nothing parses them. A mention is the first
  inline structure comments have ever carried.
- Handles are mutable and unique by confusable skeleton; `public_sqid` is the only stable identity
  and the only way to open a profile. Any stored reference must be the sqid.
- The app has no OS push. Notifications are in-app (SSE while foregrounded, 60 s poll otherwise).
- Both clients render an unknown notification type without crashing (app: `"@who · mention"` with a
  working post link; website: "X interacted with *Title*"). The server can therefore ship first.
- The existing block machinery already hides a blocked actor's notifications and gates SSE delivery;
  only the *resolution* step (D3) needs a block check.
- Deleting a comment already nulls `comment_preview` on every notification with that `comment_id`;
  `mention` rows are covered for free.
- Nothing here touches the engine, the FFI seam, memory budgets, or the launch path.
