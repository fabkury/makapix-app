# C4 (partial) — Post Management, Artist Dashboard & Settings

Bring three website features to the app. This is a **partial Club phase C4** ("Curate & manage"),
implementing the app-side of:

- **`SPEC-CLUB.md` §20** — Post Management Dashboard (PMD): bulk hide/unhide/delete + bulk license change
  + the async ZIP **data export** (BatchDownloadRequest).
- **`SPEC-CLUB.md` §19** — Artist dashboard, **aggregate** screen (totals + breakdowns + per-post table).
- **`SPEC-CLUB.md` §21** — Settings → **monitored hashtags** (content-filter opt-in).

All work is Dart-only in `app/lib/club/`. The Rust engine is untouched. Reference for the source behaviour is
the read-only website snapshot in `reference/makapix-club/` (FastAPI `api/` + Next.js `web/`).

## Decisions (locked with the user)

1. **PMD scope:** full §20, including the ZIP data export (queue → poll → save to disk). No moderator
   cross-user (`target_sqid`) mode — self-only (cross-user is C6).
2. **Artist dashboard:** aggregate screen now. The per-post `GET /post/{id}/stats` drill-in (daily-trend
   chart) is **deferred** to a fast follow.
3. **PMD endpoint path:** the app calls the **unversioned** `/api/pmd/*` directly via a second Dio base
   (`/api`), since PMD is mounted outside `/api/v1` server-side. (A future server `/api/v1/pmd` alias could
   replace this; not required now.)

## Server contract

| Feature | Method · Path | Base | Notes |
|---|---|---|---|
| Settings | `GET /auth/me` | `/api/v1` | read `user.user_key` (UUID) + `user.approved_hashtags` |
| Settings | `PATCH /user/{user_key}` `{approved_hashtags:[…]}` | `/api/v1` | **UUID only** (resolves by `user_key`); each tag must be in the monitored set |
| Dashboard | `GET /user/{user_key}/artist-dashboard?page&page_size` | `/api/v1` | `user_key` accepts UUID **or** public_sqid; owner/mod only |
| PMD | `GET /pmd/posts?limit&cursor` | **`/api`** | cursor = base64 datetime; excludes playlists |
| PMD | `POST /pmd/action` `{action,post_ids[≤128]}` | **`/api`** | action ∈ hide/unhide/delete |
| PMD | `POST /pmd/license` `{post_ids[≤128],license_id?}` | **`/api`** | `license_id:null` = all-rights-reserved |
| PMD | `POST /pmd/bdr` `{post_ids[≤128],include_comments,include_reactions,send_email}` | **`/api`** | 8/day cap → 429 |
| PMD | `GET /pmd/bdr` | **`/api`** | list ≤20; **poll** this (no SSE) |
| PMD | `GET /pmd/bdr/{id}/download` | **`/api`** | ZIP bytes; 410 if expired |
| PMD (licenses) | `GET /license` | `/api/v1` | reuse existing `UploadApi.licenses()` |

## Groundwork (shared, first)

- **`models/club_user.dart`** — `ClubUser` gains `userKey` (← `user_key`) and `approvedHashtags`
  (← `approved_hashtags`, default `[]`). `ClubMe` exposes both through `user`.
- **`api/club_api_client.dart`** — factor the auth/401-refresh interceptor into a helper; add a second Dio
  `dioRoot` with base `{baseUrl}/api` (for PMD). Both share `guard()`.
- **`config/club_config.dart`** — add `apiRoot` (= `$baseUrl/api`).
- **`config/monitored_hashtags.dart`** (new) — Dart mirror of the server's `MONITORED_HASHTAGS`
  (`politics, nsfw, explicit, 13plus, violence`) with label + description.

## Feature work

### A. Settings — monitored hashtags
- `api/settings_api.dart` — `setApprovedHashtags(userKey, tags)` → `PATCH /user/{key}`.
- `state/settings_providers.dart` — controller seeded from `auth.me.approvedHashtags`; on save updates the
  in-memory `ClubMe` and **invalidates feed providers** (feeds are filtered server-side).
- `ui/settings_page.dart` — 5 checkboxes + dirty-tracked Save. Mirrors website `/u/{sqid}/settings`.

### B. Artist dashboard (aggregate)
- `models/artist_stats.dart` — `ArtistDashboard`, `ArtistStats` (totals + by-country/device maps +
  reactions-by-emoji + `_authenticated` twins + timestamps), `PostStatsListItem`.
- `api/stats_api.dart` — `artistDashboard(userKey,{page,pageSize})` → `GET /user/{key}/artist-dashboard`.
- `state/stats_providers.dart` — paged controller keyed by userKey + an `authenticatedOnly` toggle.
- `ui/artist_dashboard_page.dart` — summary cards → breakdown lists → per-post table → auth-only switch.

### C. Post Management Dashboard (full §20)
- `models/pmd.dart` — `PmdPostItem`, `BatchActionResult`, `Bdr`, `CreateBdrResult`.
- `api/pmd_api.dart` (on `dioRoot`) — `listPosts`, `batchAction`, `batchLicense`, `createBdr`, `listBdr`,
  `downloadBdr(id)→bytes`.
- `state/pmd_providers.dart` — post-list paged controller + selection set + optimistic mutations; a BDR-list
  provider that polls `GET /pmd/bdr` while any job is pending/processing.
- `ui/post_management_page.dart` — selectable post list, bulk action bar (Hide/Unhide/Delete + license
  dropdown + Request-download), Downloads section with ZIP save (reuse `FilePicker.saveFile` desktop/mobile
  pattern). Client-side chunking (>128 split; delete UI cap 32).

### Navigation
- `ui/club_home_page.dart` top-bar `PopupMenuButton`: add **My Posts**, **Dashboard**, **Settings** items +
  `_onMenu` cases that `_push(...)` the new pages. (Menu is signed-in-only already.)

## Testing
- Dart unit tests (`app/test/`, pure — no engine/network): `fromJson` round-trips for new models + new
  `ClubMe` fields; bulk-op chunking (>128 split, 32 delete cap); settings dirty-tracking; monitored-tag set.
- `flutter analyze` clean after each feature.
- Manual: `./build.ps1 -Run` against `development.makapix.club`.

## Progress tracker

Legend: ✅ done · ◑ in progress · ○ not started

- ✅ Plan doc committed
- ✅ Groundwork: `ClubUser`/`ClubMe` fields, `dioRoot`, `apiRoot`, monitored-hashtag constant
- ✅ Feature A — Settings (api · state · ui · nav) — `flutter analyze` clean
- ✅ Feature B — Artist dashboard (models · api · state · ui · nav) — `flutter analyze` clean
- ○ Feature C — PMD (models · api · state · ui · nav · ZIP save)
- ○ Dart unit tests
- ○ `flutter analyze` clean (full)
- ○ STATUS.md + SPEC-CLUB §29 parity matrix updated

### Notes / deviations
- Settings form state lives in the page (`ConsumerStatefulWidget`) with widget-local dirty
  tracking; the save call goes through `settingsApiProvider` and `AuthController.updateApprovedHashtags`.
  No separate `state/settings_providers.dart` was needed (the `settingsApiProvider` lives in
  `state/api_providers.dart` with every other API provider).

## Out of scope / deferred
- Per-post stats drill-in (`/post/{id}/stats`) + daily-trend chart.
- PMD moderator cross-user mode (`target_sqid`) — C6.
- Other §21 settings (account/password/profile-edit/app-preferences/GitHub-publishing).
- A server-side `/api/v1/pmd` alias (using the unversioned path for now).
