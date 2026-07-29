# Club feature-gap inventory: website → app

**Date:** 2026-07-29 · **Sources:** website `reference/makapix-club` @ `99c2681` (code sweep of
`web/src`), app @ `dc7fc8d` (code sweep of `app/lib/club` + `STATUS.md`), cross-checked against
SPEC-CLUB §29 (parity matrix) and §28 (phase plan).

**Scope:** regular-user features only. Moderator/owner tooling excluded by decision. This document
is the reference list to tick off; each gap names the server endpoints (all already live — the
website calls them) and the app files involved.

---

## Ranked gap list

Impact = how much a regular user misses it. Effort = app-side work (S ≲ half a day · M ≈ a day or
two · L = multi-day). **Server:** none of tier A/B needs server changes — every endpoint is already
serving the website.

### Tier A — high value

| # | Gap | Impact | Effort | Status |
|---|-----|--------|--------|--------|
| A1 | **Own-post actions on the post detail page: Edit details · Hide/Unhide · Delete** | High | M (S each) | ✅ shipped 2026-07-29 |
| A2 | **Per-post statistics** (the website's StatsPanel) | High (artists) | M | ✅ shipped 2026-07-29 |
| A3 | **Followers list** (+ following) | Med-High | S | ✅ shipped 2026-07-29 (both tabs) |
| A4 | **Feed filters & sort** (the website's FilterButton) | Med-High | M/L | ○ open |
| A5 | **Real downloads: save artwork to device** (native / upscaled / other formats / `.mkpx`) | Med | M | ✅ shipped 2026-07-29 |

### Tier B — medium value, mostly small

| # | Gap | Impact | Effort | Status |
|---|-----|--------|--------|--------|
| B1 | Search: pagination + sort options | Med | M | ○ open |
| B2 | Comment "who liked this" list | Med-Low | S | ○ open |
| B3 | Notifications: load-more + per-item mark-read | Med-Low | S | ◑ load-more shipped 2026-07-29; per-item mark-read skipped (the page auto-marks-all-read on open, same as the website) |
| B4 | Badges explorer (definitions vs granted) | Low-Med | S | ○ open |
| B5 | Server-side logout (refresh-token revoke) | Low-Med (hygiene) | S | ○ open |
| B6 | Markdown rendering of profile bios | Low | S | ○ open |

### Tier C — product decisions, deferred phases, or big bets

| # | Gap | Status |
|---|-----|--------|
| C1 | Signed-out browsing (Recommended feed, post detail, guest commenting, logged-out reporting) | Product decision — the app gates the whole pillar behind sign-in; the website serves logged-out users |
| C2 | Upload scaling remedies for nonconforming files (NN/Lanczos3, by ratio/dimensions) | The app only *names* the nearest allowed size; the editor is the manual workaround |
| C3 | "Allow others to edit" upload option | Verify the server field first; the app never sends it |
| C4 | Live notifications (MQTT-over-WS) | SPEC-CLUB C5, planned; polling today |
| C5 | Soft player / kiosk mode (the website's WebPlayer) | SPEC-CLUB C5, planned |
| C6 | Player certificate download / renewal | Deliberately excluded from My Players (2026-07-17); revisit only if users ask |
| C7 | Divoom import | Website-specific power feature (browser WASM decoders); port only on demand |

---

## Tier A detail

### A1 — Own-post actions on the post detail page ⭐ (the known gap)

The website's `/p/{sqid}` kebab gives the owner:

- **✏️ Edit details** — inline form for title, description, hashtags → `PATCH /api/post/{id}`.
  Mod-owned hashtags shown read-only. (Website allows title ≤200 there; the app should keep the
  model-truth ≤128 per SPEC-CLUB §31.6.)
- **🙈 Hide / 👁️ Unhide** — `POST /api/post/{id}/hide` / `DELETE /api/post/{id}/hide`.
- **🗑️ Delete** — confirm → `DELETE /api/post/{id}` → navigate away. (PMD copy mentions a 7-day
  grace window server-side; reuse that wording.)

App today: **none of the three exist anywhere** — no `PATCH /post/{id}` client at all; hide/delete
exist only as *bulk* PMD actions (`POST /pmd/action`) reachable via ☰ → My Posts. License is also
bulk-only (`POST /pmd/license`); the website has no single-post license control either, so that part
is parity.

App touchpoints: `api/post_api.dart` (new calls), `ui/artwork_detail_page.dart` (kebab entries +
edit sheet), invalidation of feeds/profile/PMD lists after mutate (`state/safety_providers.dart` has
the pattern).

### A2 — Per-post statistics

Website: owner-only 📈 StatsPanel modal — authenticated-only toggle, summary cards (views, unique
7d, reactions, comments), 30-day daily-views bar chart, views by country/device/type, reactions by
emoji, first/last view, refresh. `GET /api/post/{id}/stats` (+ `?refresh=true`).

App: deliberately deferred (`api/stats_api.dart` notes it); the aggregate Artist Dashboard shipped
instead. The dashboard's breakdown widgets (`ui/artist_dashboard_page.dart`) are reusable here.

### A3 — Followers list (+ following)

Website: tapping the 👤 follower count opens FollowersOverlay (limit 200, rows → profile).
App: **both API methods already exist unused** — `ProfileApi` `GET /user/u/{sqid}/followers` and
`…/following` (`api/profile_api.dart:36-38`) — the count just isn't tappable. UI can mirror
`ui/blocked_users_page.dart` / `ui/reactions_page.dart`. (The website only shows followers;
a following tab is a free bonus.)

### A4 — Feed filters & sort

Website FilterButton (Recent, hashtag, and profile-gallery feeds): sort by creation date / reactions
/ file size · asc/desc · base (min dimension) 8–128+ · size multi-select · file-size range · kind
static/animated. All as query params on `GET /api/post`.

App: no filter/sort UI on any feed; `api/feed_api.dart` hardcodes `sort=created_at&order=desc`.
Needs a filter sheet + provider plumbing per feed family. Biggest tier-A surface; can ship in
slices (sort+kind first, dimension/file-size later).

### A5 — Real downloads (save to device)

Website Download menu: upscaled (`/api/d/{sqid}/upscaled`), native (`/api/d/{sqid}`), alternative
formats (`/api/d/{sqid}.{fmt}`), layers file (`/api/d/{sqid}.mkpx`, signed-in + `has_mkpx`).

App: share-only — re-encodes and opens the OS share sheet; the only true file export is the PMD ZIP.
The `.mkpx` can only be opened *into the editor*. Add a Download submenu on the detail kebab using
the same file-picker save flow PMD's ZIP download already uses (`ui/post_management_page.dart`).

---

## Tier B detail

- **B1 Search** — website: combined search paginates ("Load more"); hashtag tab sorts Popular/A-Z
  with per-tag artwork rollers + infinite scroll; user browse sorts alphabetical/recent/reputation.
  App: single fetch per tab, no paging (`ui/search_page.dart`), `browseUsers` sort param exists but
  is hardcoded alphabetical (`api/search_api.dart:20`).
- **B2 Comment like-users** — `GET /api/post/comments/{cid}/like-users`; app has no client for it.
  Mirror `ui/reactions_page.dart` as a small sheet.
- **B3 Notifications** — the paged notifier already exists (`state/notifications_providers.dart`);
  the page just never requests page 2. Per-item mark-read: `NotificationsApi.markRead` **already
  exists unused** (`api/notifications_api.dart:25`).
- **B4 Badges explorer** — `GET /api/badge` catalog vs granted; app shows the chips with no
  explanation surface.
- **B5 Logout revoke** — website `POST /api/auth/logout` revokes the refresh token;
  `ClubSession.logout()` is local-only.
- **B6 Markdown bio** — website renders bios as markdown; the app renders plain text.

---

## At parity — or app ahead

Feeds (Recent/Recommended/Following/hashtag + trending bar + super-post tile) · detail pager with
swipe · reactions incl. who-reacted page · comments (post/reply/like/delete/report) · report flow
(posts/comments/users) · block/unblock + blocked list · profiles (view/edit/avatar/share) · Reacted
tab · Highlights display strip · follow/unfollow · Artist Dashboard · PMD bulk hide/unhide/delete/
license/ZIP export · publish flow (+`.mkpx` attach/replace/remove) · edit/remix + replace-artwork ·
monitored hashtags · My Players (register/rename/delete) · Player Bar (send, pause, brightness,
rotation, mirror) · auth (email+password, GitHub PKCE, OTP verify, password reset, onboarding,
account management, delete account).

App-ahead notes: Apple sign-in; native PKCE OAuth; "Use as profile photo" works on the detail page
(the website has it **disabled** there, enabled only in the grid overlay); synchronized feed
animation playback; local Private tab; `.mkpx` opens straight into a layered editor document.

## Explicitly not gaps

- **Playlists** — fully deferred 2026-07-07, do not develop.
- **Blog** — postponed on the website itself (notice pages).
- **Gifting** — "Coming Soon" placeholder on the website.
- **Highlights pin/unpin management** — absent from the website's user UI too (server API exists;
  park until either client wants it).
- **Comment editing** — `PATCH /post/comments/{id}` client exists in the app unused, but the
  website has no edit UI either.
- **Page-view telemetry** (`/track/page-view`) — the app is deliberately telemetry-free (§26).

## Minor fidelity notes

- Comment reply depth: website detail page allows 3, its overlay and the app allow 2.
- View registration: the website registers grid-overlay views after a 2 s dwell with channel
  context; the app only registers on detail open (`channel: "artwork"`).
- Website bugs noticed during the sweep (report upstream, not app work): profile highlights link to
  a nonexistent `/a/{sqid}` route; `SelectedArtworkOverlay.tsx` and `SendToPlayerModal.tsx` are dead
  code; two permanently disabled kebab stubs on `/p/[sqid]`.
