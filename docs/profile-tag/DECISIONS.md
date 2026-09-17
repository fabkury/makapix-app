# Mentions in comments — decisions

Questions for the project owner, written 2026-09-17 alongside [`README.md`](README.md) (section
numbers below refer to it). Each item gives the options, the recommendation, and what changes if the
answer differs. Answer inline under **Decision:**; the contract message to the server team is written
only after the product decisions are settled. The numbering is stable so messages can cite `D6`.

**Settled 2026-09-17:** D1, D2, D6, D13. **Raised by those answers:** D17–D21. Everything else is
open.

---

## Product decisions

**D1 — The name.** "Tag" already means hashtag in all three codebases and in notification copy (§2).
**Decision (2026-09-17): mention.** Notification type `mention`; UI copy "mentioned you in a
comment"; docs and the contract say "mentions". "Tag" stays reserved for hashtags.

**D2 — Representation.** Plain `@handle` text with a server-resolved sidecar, versus inline markup
carrying the stable id (§4).
**Decision (2026-09-17): inline markup with the sqid.** Consequences taken into the design: the
markup grammar (D17), a compatibility strategy for the readers that print `body` verbatim (D18),
hand-typed handles do not mention (D19), read-time handle refresh (D20), and roughly three extra
developer-days (§7).

**D3 — Who can be mentioned.** Recommended: exactly the users who would appear in `/user/browse`
for the commenter (verified, not hidden/deactivated/banned/non-conformant), and **nobody with a
block in either direction** with the commenter; anyone else is flattened to plain text, silently
(§5.2 R2). The alternative (refuse the comment with `403 blocked`, as replies to a blocker do today)
tells U1 that U3 blocked them.
Sub-question: **should the site owner be mentionable?** Browse hides the owner today; a mention of
`@fab` on Makapix would be common and presumably welcome.
**Decision:** _pending_

**D4 — Anonymous commenters.** The website allows signed-out, IP-attributed comments. Recommended:
their mentions link but never notify (§5.1 W4). Alternatives: (a) as recommended · (b) notify with
actor "Anonymous", like anonymous replies do today · (c) neither link nor notify.
**Decision:** _pending_

**D5 — Caps.** Recommended: at most **5** mentions per comment (extras flattened to plain text, the
comment is not rejected), and **60** notified mentions per actor per hour on top of the existing
720/hour per actor→recipient pair (§5.1 W3, §5.3 N5). The per-comment cap is the `/config` launch
signal key. Are 5 and 60 right? Should the server reject (422) instead of flattening the extras?
**Decision:** _pending_

**D6 — One notification per recipient per comment.** (§5.3 N2)
**Decision (2026-09-17): one notification.** When the mentioned user already gets `comment` (post
owner) or `comment_reply` (parent author) for the same comment, the `mention` row is skipped.
Precedence: `comment_reply` > `comment` > `mention`.

**D7 — Visibility guard.** Recommended: no `mention` notification when the recipient cannot see the
post (hidden, pending approval, deleted) or when the post carries a monitored hashtag the recipient
has not opted into (§5.3 N3). Without it a mention puts a filtered thumbnail into the recipient's
inbox. Alternative: notify anyway but strip the thumbnail for that recipient (more code, same leak via
the title).
**Decision:** _pending_

**D8 — Edits.** Recommended: re-parse on edit and notify **only newly added** recipients; removed
mentions keep their old notification (§5.3 N6). Alternatives: (a) as recommended · (b) edits never
notify (simplest; closes the "edit an old comment to ping someone" path) · (c) also delete the
notification when a mention is removed.
**Decision:** _pending_

**D9 — Notification copy and tap target.** Recommended tile: "**@U1** mentioned you in a comment on
*Title*: *preview*", actor avatar → U1's profile, whole tile → the post page (matching every comment
type today). Scroll-to-comment on open is not implemented for any type and is proposed as a separate
small effort (§9). Agree?
**Decision:** _pending_

**D10 — Scope beyond comments.** v1 is comments only. Post descriptions and bios are a natural v2
using the same grammar and rules (§9). Should v1 at least *render* mentions in descriptions (no
composer, no notification) so the renderer is written once, or keep descriptions untouched?
**Decision:** _pending_

**D11 — A "who can mention me" setting.** Everyone / people I follow / nobody. Recommended for v2,
with the server check written as one function so it is a one-condition addition later (§8 risk 1).
The app has no notification-preferences UI today, so this is a small feature of its own. Ship it in
v1 anyway?
**Decision:** _pending_

**D12 — Should the app ship before the website does?** With the dual field (D18) yes, and nothing
looks broken (§5.5 G2). Without it, the app's composer must wait for the website's renderer to be on
`main`, or website readers see raw markup.
**Decision:** _pending_

---

## Engineering decisions

**D13 — Autocomplete source.** (§5.1 W2, §6.2)
**Decision (2026-09-17): a dedicated server endpoint.** `GET /user/mention-candidates` with
contextual tiers (post owner · thread participants · following · followers · prefix search). The
sketch in §6.2 is the ask to the server team; D21 covers its details.

**D14 — Grammar and test vectors.** The §6.1 bracket grammar, frozen in the contract, with vectors
in all three test suites. Now a parser question rather than a tokenizer one (no Unicode word
boundaries), but the same rule applies: any divergence is a quiet bug.
**Decision:** _pending_

**D15 — Where the contract lives.** The app repo's `messages/` convention says the server team
opens threads, but the app team opened `notification-actor-sqid` in 2026-07. Recommended: the app
team opens `messages/0003-mentions/0001-app-mentions-proposal.md` with the §6 contract, mirrored by
the server team under `docs/mentions/messages/`. Agree, or should this first be a conversation?
**Decision:** _pending_

**D16 — Rename this folder.** With D1 settled, rename `docs/profile-tag/` to `docs/mentions/` so the
folder never contradicts the feature name in STATUS.md and commits. Recommended: yes, in the commit
that opens the contract thread.
**Decision:** _pending_

**D17 — Markup syntax.** Recommended `@[handle](u:SQID)` (§4.1–4.2): mirrors the bio mini-markdown
both codebases already parse, degrades to a readable handle on a client that does not know it, and
the `u:` prefix leaves room for other reference kinds. Alternatives: `<@SQID>` (compact, degrades to
noise) · `@handle{SQID}` (no safe delimiting of Unicode handles).
**Decision:** _pending_

**D18 — Compatibility for readers that print `body` verbatim.** Three website surfaces, every app
build in the field, and `comment_preview` (§4.3). Recommended: **dual field** — `body` stays a plain
rendering, new `body_markup` carries the source. Alternatives: a transition window with raw markup
visible on legacy readers · version-gating by User-Agent (new server parsing, fragile).
Sub-question: an edit from a legacy client writes back the plain body and the comment's mentions are
lost. Accept that, or should the server **refuse** a plain-body edit of a comment that has mentions
until the client is updated?
**Decision:** _pending_

**D19 — Hand-typed handles do not mention.** A mention exists only when picked from the candidates
list (or pasted as valid markup); a typed `@fab` that was never picked is plain text (§5.1 W1). This
follows from D2 (the server never resolves text) and matches Instagram/Slack/Discord. The
alternative reintroduces a text tokenizer on the server. Confirm?
**Decision:** _pending_

**D20 — Read-time handle refresh.** Because the stored form carries the sqid, the server can render
the *current* handle in old mentions after a rename (§4.5). Recommended: yes, on both `body` and
`body_markup`. Alternative: freeze the handle as written (cheaper by one lookup per page; stale text
after renames).
**Decision:** _pending_

**D21 — The candidates endpoint.** Details for the ask in §6.2: (a) tier order `owner · thread ·
following · follower · search`; (b) empty `q` allowed (returns the contextual set, so the list opens
on a bare `@`); (c) `limit` default 8, max 20; (d) rate limit ~120/minute per user; (e) it applies
exactly the `/user/browse` visibility filters plus the two-way block check; (f) it excludes the
caller. Any of these you want different, and should the site owner appear (ties to D3)?
**Decision:** _pending_

---

## Things confirmed while researching (no decision needed)

- Comment bodies are plain text on every client today; nothing parses them. A mention is the first
  inline structure comments have ever carried, which is why D18 exists.
- Handles are mutable and unique by confusable skeleton; `public_sqid` is the only stable identity
  and the only way to open a profile. The markup carries the sqid for exactly this reason.
- The server already sees the app's version in the User-Agent but does not parse it; UA-based
  gating would be new work (§3, §4.3).
- The app has no OS push. Notifications are in-app (SSE while foregrounded, 60 s poll otherwise).
- Both clients render an unknown notification type without crashing (app: "@who · mention" with a
  working post link; website: "X interacted with *Title*"). The server can therefore ship first.
- The existing block machinery already hides a blocked actor's notifications and gates SSE delivery;
  only the *mentionability* check (D3) is new.
- Deleting a comment already nulls `comment_preview` on every notification with that `comment_id`;
  `mention` rows are covered for free.
- Nothing here touches the engine, the FFI seam, memory budgets, or the launch path.
