# UGC safety (app) — Decisions

Product/UX decisions taken with the owner on 2026-07-06, plus engineering
decisions made during planning. Numbered `A*` (app, folder-scoped) to avoid
colliding with the server repo's `D1–D26`
(`reference/makapix-club/docs/ugc-safety/DECISIONS.md`), which remain
authoritative for server behavior and the wire contract.

## Owner decisions (2026-07-06)

**A1 — Rules gate: first-run, everyone, Club pillar only.** A one-time
blocking "Community rules" screen shown before first entry into the Club
pillar — both signed-in and signed-out (signed-out users can browse UGC, so a
sign-in-only gate would under-deliver on Apple 1.2 / server D26). Zero-
tolerance wording, link to `guidelines_url`, single "Agree and continue"
action. Acceptance is persisted per-install via `shared_preferences` and
**versioned** (`kRulesVersion = 1`) so a future material rules change can
re-prompt. Existing installs see the gate once after updating (once the
`moderation` config key is live). The **editor pillar stays reachable
ungated** — it exposes no UGC, and "editor reachable without login" is a
standing product guarantee — with one exception: the editor's "Post to
Club" flow pushes `PublishPage` on the editor navigator without entering
the Club pillar, so `PublishPage` carries its own gate check (review R1).

**A2 — Report flow is a full-screen page** (owner choice over the app's
bottom-sheet idiom). Entry points stay lightweight — post-detail kebab
"Report post…", a per-comment "Report" mini-button, profile-menu "Report
user…" — and all three push one shared `ReportPage`. Rationale: more room for
the 9-reason radio list plus a notes field, and a dedicated screen gives App
Review an unambiguous screenshot surface.

**A3 — Block entry points: profile menu + post-report offer.** "Block
@handle…" lives in the profile page's new overflow menu (with a confirm
dialog). Additionally, after any successful report, the confirmation dialog
offers "Also block @handle" when applicable (viewer signed in; offender known,
non-self, attributable). This covers the report-then-block harassment path
without adding block entries to every post/comment menu. Blocked-users
management screen (Settings) and the Unblock affordance on blocked profiles
are mandatory regardless (App Review looks for them).

**A4 — The `0002` reply ships with the plan.** The reply message answering
the server team's §8 items (ack, gate confirmation, logged-out browsing
answer, ETA) is committed to the server repo's `develop`
(`reference/makapix-club/message/0002-app-ugc-safety-ack.md`) at the same
time this plan is committed, so the server team can line up the joint prod
flip immediately.

## Engineering decisions

**A5 — Feature gate = nullable `ModerationRules` object.**
`ClubServerConfig` gains `final ModerationRules? moderation;` parsed from the
`moderation` config block with **no default** — `null` means the server does
not have the feature, and every safety affordance stays hidden: report
entries, block entries, the Settings "Blocked users" tile, the Settings
community/contact section, and the first-run rules gate. Getter
`bool get moderationEnabled => moderation != null;`. `fallback` (offline)
keeps it `null`. Same mechanism as `upload.mkpx` and
`max_mod_hashtags_per_post` (contract §1 / D17).

**A6 — Report reasons render from config verbatim.** The report page's radio
list is built from `moderation.report_reasons` (code + label pairs) in server
order — no hardcoded labels, and unknown codes are tolerated by construction
(contract §1: the list can grow within v1). Client-side validation is only
"a reason must be selected" and "notes ≤ 2000 chars".

**A7 — New `SafetyApi`** (`app/lib/club/api/safety_api.dart`): `report(...)`,
`block(sqid)`, `unblock(sqid)`, `blocks(cursor)` — the user-facing safety
domain, deliberately distinct from the moderator-role `ModerationApi`.
Registered as `safetyApiProvider` in `state/api_providers.dart` per the
existing pattern. Logged-out reporting needs no new plumbing: the shared Dio
attaches the bearer only when a token exists.

**A8 — `ClubError.isBlocked` + one copy constant.** `ClubError` gains
`bool get isBlocked => status == 403 && code == 'blocked';`. All **five**
interaction sites map it to one shared, direction-neutral string — "You
can't interact with this user." — because D11 refuses interactions in
**either** direction and the copy must not disclose who blocked whom. The
sites (review R4): detail-page reaction, feed-grid like, comment
create/reply, comment like (whose controller today swallows every error and
must be changed to surface the blocked case), and follow.

**A9 — Blocked profile renders header + Unblock; content collapsed.** When
`is_blocked_by_viewer` is true, the profile keeps its header (avatar +
handle) and shows a blocked banner with an Unblock button instead of the
follow button and artwork grid — never a fake 404 (D14). List-surface
cleanup after block/unblock is **server-side**; the app only invalidates the
profile and feed providers so the next build refetches. No client-side
filtering anywhere (contract §5: none needed).

**A10 — Blocked-users screen copies the notifications-list pattern.**
Settings → "Blocked users" `ListTile` → `BlockedUsersPage`:
`PagedNotifier<BlockedUser>` over `GET /me/blocks` + `ListView.separated`.
Per-row Unblock (removes the row from local state on 204); row tap opens the
profile. This is the app's first people-list screen; the follower/following
APIs exist but have no UI to reuse.

**A11 — `ReportTarget` value class.** `ReportPage` takes a small pure-Dart
descriptor `{type, id, label, offenderSqid?, offenderHandle?}` with factory
constructors `ReportTarget.post(Post)`, `.comment(Comment)`,
`.user(UserProfile)` — so the three entry points share one page, the
`target_type`/`target_id` mapping (post → decimal integer id as string,
comment → UUID, user → `public_sqid`; contract §2/D9) is encoded in exactly
one testable place, and the post-report block offer knows whom to offer.

**A12 — Rules gate: config-driven, fail-open, reactive (never blocks
startup).** *(Rewritten per review R2 — the original splash-while-loading
design would have stalled every pre-flip cold start on the config fetch,
15 s offline, and failed its own "prod build unchanged" manual gate.)* The
gate needs `guidelines_url`, so it depends on the config fetch — but Club
always renders immediately; the gate **interposes** the moment
`serverConfigProvider` resolves with the `moderation` key while the
acceptance flag is missing. A sub-second-late gate still blocks before any
meaningful interaction, which is what Apple 1.2 cares about. Config resolved
with `moderation` absent (pre-flip server, or the offline fallback) →
proceed ungated. Fail-open is deliberate: the app must not hard-lock
offline, and a pre-flip prod server must produce behavior identical to
today. The gate re-arms on every launch until accepted.

**A13 — `url_launcher` added** (Flutter-side dependency; the Rust engine's
zero-dependency rule is untouched). Needed for `guidelines_url` /
`moderation_policy_url` links and the `mailto:` moderation contact. Already
present transitively in `pubspec.lock`; promoting it to a direct dependency
is cheap and it supports Windows + Android.

**A14 — Playlist posts get no report entry in v1.** Server D6 defers
playlists as report targets ("posts, comments, users" only). The kebab's
report entry is gated on `!post.isPlaylist`, matching the existing mkpx/mod
entries; the playlist's owner can still be reported from their profile.
Flagged in the `0002` reply as a clarification (if the server team intends
playlist posts to count as `post` targets, dropping the exclusion is one
condition).

**A15 — Impersonal shield presentation for the two new notification types.**
`new_report` → "New content report — open the moderation queue" (moderators
only receive these; the queue is website-side). `report_resolved` → "Thanks —
we've reviewed your report." Both render the shield `CircleAvatar` (the
`mod_hashtags_updated` branch generalizes to a type set). Taps:
`report_resolved` keeps the default `content_sqid` deep-link behavior;
`new_report` is **forced inert** until the server team answers what its
`content_sqid` carries — a user-target report's sqid is not a post id and
would push a broken detail page (review R9; asked in the `0002` reply). No
push work: the app has no FCM/MQTT client; both types arrive via the polled
list (same posture as mod-hashtags A14).

**A16 — No self-report / self-block affordances.** Report entries are hidden
on own posts, own comments, and the own profile; Block is hidden on the own
profile. The server would refuse anyway (400 on self-block); hiding avoids
dead-end UI.

**A17 — Deleted and anonymous comments.** Soft-deleted comments
(`c.deleted`) lose their report affordance (their body is redacted; there is
nothing left to report). Anonymous comments (`c.author == null`) **stay
reportable** — the content itself is the target (D16) — but produce no
post-report block offer (no stable identity to block). Their report label
says "guest", matching how the comments UI renders anonymous authors
(review R10a).

**A18 — Empty `report_reasons` means feature-off** (review, 2026-07-06). A
`moderation` block whose `report_reasons` is missing or empty parses as
`moderation = null`: a report form whose submit can never enable is a
worse failure mode than the feature staying hidden. Costless robustness in
the parser.
