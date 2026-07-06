# Profile editing — implementation plan

**Status: planned** · Phase: C4 (curate & manage) · Spec: `SPEC-CLUB.md` §14 "Edit own profile" ·
Reviewed 2026-07-06 (fresh-eyes agent pass; all endpoint/limit/line claims verified against
`reference/makapix-club` and the app code, amendments folded in)

## 1. Goal and scope

Let a signed-in user edit their **avatar**, **tagline**, and **bio** from the app. Today the only
write path is the one-time onboarding wizard (avatar + bio, skippable); after that the app has no
profile-editing UI and users must use the website.

**Decisions (user, 2026-07-06):**

- Fields: **avatar + tagline + bio only**. No website field (the app doesn't display it anywhere
  yet). Handle change stays where it already is (Settings → Account, `AccountManagementPage`).
- UI: a **dedicated Edit Profile page**, reached from the user's own profile page and from the
  account page. The profile page stays read-only.
- Avatar: **pick an image file** + **remove/clear**. No editor-drawn avatar (possible future
  feature), no client-side downscale.
- Save model: **single Save button** sending one PATCH with only the changed text fields.
  Avatar upload/delete are separate endpoints and apply **immediately** on user action.

**Out of scope:** website field · handle change (exists) · Markdown rendering/preview of the bio
(the app currently renders bio as plain text; unchanged) · "draw avatar in the Makapix Editor"
(future; would need an editor→club bytes bridge like publish) · account lifecycle.

## 2. Server contract (verified against `reference/makapix-club`)

| Operation | Endpoint | Notes |
|---|---|---|
| Update text fields | `PATCH /api/v1/user/{user_key}` | Body `{ bio?, tagline? }`. Path resolves by **UUID user_key only** (not sqid); auth = self (or owner/moderator). Omitted/`null` field = *no change*; **empty string = "cleared"** — note it stores `""`, not NULL, so a cleared field reads back as `""` while a never-set one reads back as `null`. Limits: `tagline` ≤ 48 chars, `bio` ≤ 1000 chars (`schemas.UserUpdate` — pydantic counts **code points**, see 3.2). `avatar_url` deliberately not accepted here. Oversize/bad-format avatar errors are **400** (not 413); pydantic limit violations are 422. |
| Upload avatar | `POST /api/v1/user/{user_key}/avatar` | Multipart field `image`. ≤ 5 MB; MIME allowlist in `api/app/avatar_vault.py` (PNG/GIF/JPEG/WebP). 201 → `UserFull` incl. new `avatar_url`. Each upload gets a **fresh UUID URL**, so URL-keyed caches never go stale. |
| Clear avatar | `DELETE /api/v1/user/{user_key}/avatar` | Sets `avatar_url` to null; best-effort file deletion server-side. **Not yet wrapped in the app client — must be added.** |
| Read back | `GET /api/v1/user/u/{sqid}/profile` · `GET /api/v1/auth/me` | Both already wrapped (`ProfileApi.profile`, `ClubApiClient.me`). `/auth/me` builds its response from the fresh DB row, so avatar changes reflect immediately. |

Existing app plumbing: `ClubApiClient.updateBio` (PATCH, bio only) and `ClubApiClient.uploadAvatar`
(`app/lib/club/api/club_api_client.dart:122-134`), currently called only by
`onboarding_controller.dart`.

## 3. Changes

### 3.1 API layer — `app/lib/club/api/club_api_client.dart`

1. Generalize `updateBio` → `updateProfile(String userKey, {String? bio, String? tagline})`:
   builds the PATCH body from only the non-null arguments (so callers control what changes;
   passing `''` clears a field). The current onboarding call is **positional**
   (`onboarding_controller.dart:106`, `updateBio(userKey, bio.trim())`), so that call site is
   edited to the named form in the same change.
2. Add `deleteAvatar(String userKey)` → `DELETE /user/{user_key}/avatar`.
3. `uploadAvatar` unchanged (already returns the new `avatar_url` when present). Keep passing the
   **picked file's real name** through — the server detects MIME from the filename extension
   (Dio's `MultipartFile.fromBytes` sends `application/octet-stream`); onboarding's `'avatar.png'`
   fallback pattern stays.

These stay on `ClubApiClient` (not `ProfileApi`) to match the existing split: `ProfileApi` is the
read/social side keyed by sqid; own-account mutations keyed by user_key live on the client, and
onboarding already imports them from there.

### 3.2 New page — `app/lib/club/ui/edit_profile_page.dart`

`EditProfilePage extends ConsumerStatefulWidget`, constructed with the already-loaded
`UserProfile` (both entry points have one or can fetch it; see 3.3). Layout mirrors the app's
existing form pages (`AccountManagementPage`, `SettingsPage` idioms: `ListView` + snackbar toasts +
busy flags):

- **Avatar section** — `CircleAvatar` (current avatar via `CachedNetworkImageProvider` +
  `avatarImageCache`, else initial-letter placeholder), with two actions:
  - *Change photo*: `file_picker` with `FileType.custom` +
    `allowedExtensions: ['png','jpg','jpeg','gif','webp']` and `withData: true` (narrower than
    onboarding's `FileType.image`, which admits e.g. BMP that the server 400s) → client-side
    ≤ 5 MB check → `uploadAvatar` immediately, busy spinner on the avatar while in flight → on
    success update local page state with the returned URL + refresh (3.4).
  - *Remove photo*: shown only when an avatar exists; confirm dialog (destructive, immediate) →
    `deleteAvatar` → placeholder + refresh (3.4).
- **Tagline** — single-line `TextField`, `maxLength: 48` (counter visible), prefilled. Because
  Flutter's `maxLength` counts grapheme clusters but the server's `max_length=48` counts **code
  points** (emoji can exceed one code point each), also validate `text.runes.length <= 48` before
  Save and show a friendly inline error — otherwise the server's 422 renders as a raw
  `detail`-list dump through `ClubError.fromBody`.
- **Bio** — multiline `TextField` (`maxLines` ~6), `maxLength: 1000`, prefilled; same
  code-point check (≤ 1000).
- **Save** — `FilledButton` enabled only when dirty (trimmed text differs from the loaded
  profile). Sends `updateProfile` with **only the changed fields**; an emptied field is sent as
  `''` (server clears it). On success: toast "Saved.", reset the dirty baseline, refresh (3.4).
- **Unsaved-changes guard** — `PopScope(canPop: false when dirty)` asks Discard / Keep editing.
  Avatar changes are already committed, so they never block leaving. Note the page is pushed onto
  the Club pillar's **nested navigator**; Android system back reaches it via `ClubPillar`'s
  `PopScope` → `maybePop()` (`club_pillar.dart:35-40`), which respects the top route's pop
  disposition — so the guard works for system back, the AppBar back button, and Windows alike.
- **Errors** — `on ClubError catch → toast e.message`, generic catch → generic toast; busy flags
  disable the controls (same pattern as `_changePassword` in `AccountManagementPage`).

To keep the payload logic unit-testable without widgets, put it in a small pure helper (new file
`app/lib/club/edit/profile_edit.dart` or alongside the page):

```dart
/// Only fields that differ from [current] are included; an emptied field maps to ''.
/// The baseline comparison treats null and '' as equivalent (a cleared field reads
/// back from the server as '', a never-set one as null — see §2).
Map<String, String> buildProfilePatch(UserProfile current, {required String tagline, required String bio});
```

### 3.3 Entry points

- **Own profile page** (`app/lib/club/ui/profile_page.dart`): in `_header`, where the Follow
  button is suppressed for `p.isOwnProfile`, show instead an **"Edit profile"** `OutlinedButton`
  → `Navigator.push(EditProfilePage(profile: p))`; on return, `ref.read(profileProvider(sqid)
  .notifier).load()` so the header reflects the changes.
- **Account page** (`app/lib/club/ui/club_account_page.dart`, `_AccountView`): an **"Edit
  profile"** `OutlinedButton` above "Manage account". This page holds a `ClubMe`, not a
  `UserProfile`, so it fetches first: `profileApiProvider.profile(me.user.sub)` (busy state on the
  button), then pushes the page. (Reusing `profileProvider(sub)` is also possible, but a one-shot
  fetch avoids holding an autoDispose family alive from a page that doesn't otherwise watch it.)
  `_AccountView` is currently a stateless `ConsumerWidget` — the busy flag needs a small stateful
  button widget (or converting `_AccountView` to `ConsumerStatefulWidget`).

### 3.4 State refresh after mutations

- The signed-in user's avatar also lives in `AuthState.me.user.avatarUrl` (shown on the account
  page). After an avatar upload/delete, call `authControllerProvider.notifier.reloadMe()` — it
  exists (`auth_controller.dart:121`) and same-user reloads deliberately rebuild nothing except
  `me` consumers.
- After Save / avatar change, the profile page reloads via `.load()` on return (3.3); no
  optimistic write into `profileProvider` needed.
- **Caching:** avatar URLs are immutable (fresh UUID per upload), so `avatarImageCache` needs no
  invalidation; the old URL simply ages out (7-day TTL). One known cosmetic wrinkle on **Remove
  photo**: the server best-effort-deletes the old file, but already-loaded feed/detail/comment
  state still carries the old `avatar_url` in `PostOwner`/`CommentAuthor` snapshots, which may
  404 (blank circle) until the next feed refresh — disk-cached copies mask it for up to 7 days.
  Self-healing; accepted. (Upload/replace is safe: the old file is *not* deleted on upload.)

### 3.5 Docs

- `SPEC-CLUB.md` §29 parity matrix: add/mark the "Edit own profile (avatar/tagline/bio)" row as
  app ✅ (tagline/bio/avatar; website + handle-move not included).
- `STATUS.md`: record the new capability honestly (including what's excluded).

## 4. Tests

Dart-only, no network (repo convention: `app/test/*.dart` are pure unit tests):

- `buildProfilePatch`: unchanged → `{}` · tagline-only change → `{tagline: …}` · cleared bio →
  `{bio: ''}` · whitespace-only edits trim to unchanged → `{}` · **current bio `null`, field left
  empty → `{}`** (null ≡ '' baseline, see §3.2) · code-point length validation (48-grapheme emoji
  tagline rejected).
- `ClubUser`/`UserProfile` round-trips already covered by model tests; extend only if the model
  changes (none planned — `UserProfile` already carries `bio`/`tagline`/`avatarUrl`).

Existing Rust engine tests are untouched (this is Dart-only Club work; the engine stays
network-free).

## 5. Verification

1. `flutter analyze` and `flutter test` in `app/` — clean.
2. `./build.ps1 -Run` (Windows, prod backend by default — verify against a real account, or pass
   `-Dev` for `development.makapix.club`): edit tagline/bio → Save → toast → profile header
   updates; pick avatar → immediate upload → avatar swaps on profile + account pages; Remove
   photo → placeholder; back-navigation with dirty text → discard prompt; oversize file → clear
   error toast.
3. Android spot-check via `./build_android.ps1 -Install` (file picker + upload on device).

## 6. Delivery

Single commit (or two: API+helper+tests, then UI) on `main`, message
`feat(club/C4): edit profile — avatar, tagline, bio (SPEC-CLUB §14)`. No server changes; no
version bump / release in this task.
