# C2 — Create & Publish (`app/lib/club/publish/`)

**Phase:** C2 of the Makapix Club social pillar (SPEC-CLUB §28, §7–§8).
**Status:** 🟡 in progress — see [Progress](#progress).
**Depends on:** C0 (auth client), C1 (Post model). **Last updated:** 2026-06-26.

---

## 1. Goal & acceptance

From the editor, **publish the current document to Makapix Club**: validate conformance → choose format →
enter metadata/license/visibility → `POST /post/upload`. This replaces the legacy `_uploadToClub()` (old
`/api/v1/artifacts` provisional contract + manual URL/token) with the real, authenticated flow.

**Acceptance:**
- **Tier-1:** conformance logic tested (whitelist / 128–256 band / >256 reject / format / size).
- **Build:** `flutter analyze` clean for lib/club; `flutter build apk --debug` green.
- **Device (user):** draw → **Post to Club** → metadata → upload → the post appears on `development.makapix.club`
  (or shows "awaiting moderator approval" when the account lacks `can_post_public`).

**Non-goals (deferred):** auto **scale-to-conformant** (needs a new engine `ScaleCanvas` op — see §6; for now
the gate blocks non-conformant art and points to the existing Resize/crop-pad op); WebP/BMP export (we ship
PNG for static, GIF for animated — both already in the engine); idempotency-key retries (brief §2.6, when the
server adds it); the editor's own draft autosave already exists (`.mkpx`), we add a small metadata draft.

---

## 2. Key decision: reuse the existing engine export (no engine rebuild)

The editor's FFI already exposes `exportPng(frame)` and `exportGif()` (STATUS.md). So:
- **static** art (`frame_count == 1`) → **PNG**; **animated** → **GIF**. Both server-accepted.
- **content hash** for the duplicate pre-warn is computed **in Dart** (`crypto` sha256) over the exported bytes.
- **conformance** is computed **in Dart** from `engine.width/height/frameCount` + the byte length.

⇒ C2 touches **only the Dart layer**; the Rust engine/codec/FFI stay as-is. (SPEC-CLUB §7.4 proposed
`conformance_check`/`export_for_club` FFI; reusing the existing export is the pragmatic equivalent and avoids a
DLL/.so rebuild. The dedicated FFI can come later if WebP/BMP export or engine-side scaling is wanted.)

## 3. Conformance (mirror of `vault.py`; prefer server `/config`)

Rules (server source of truth; the app will **fetch `GET /api/v1/config/upload` if it exists**, else use these
hardcoded constants and log the fallback — brief §6.1):
- formats: png, gif, webp, bmp; **max 5 MiB**.
- dims: **128–256** inclusive any (square/rect); **<128** only the whitelist `{8×8, 8×16, 8×32, 16×16, 16×32,
  32×32, 32×64, 64×64, 64×128}` + 90° rotations; **>256** rejected.

`ClubConformance.check(width, height, frameCount, byteLength)` → `ConformanceResult { ok, reasons[],
nearestConformantSize? }`. Pure + unit-tested.

## 4. Modules

- `club/publish/conformance.dart` — rules + `ConformanceResult` + `check(...)` + `nearestConformantSize`.
- `club/publish/upload_api.dart` — `UploadApi(ClubApiClient)`:
  - `uploadArtwork({bytes, filename, title, description, hashtags, hiddenByUser, licenseId}) → Post`
    (`POST /post/upload`, multipart). Maps 413→`file_too_large`, 409→`artwork_duplicate` (with existing
    post sqid in details), 429→`rate_limited`, quota.
  - `licenses() → List<LicenseOption>` (`GET /license`).
- `club/models/license_option.dart` — `LicenseOption { id, identifier, title }`.
- `club/state/publish_providers.dart` — `licensesProvider` (FutureProvider) + `PublishController`
  (StateNotifier: idle/validating/uploading/success(Post)/error) reading bytes from the engine via a callback.
- `club/ui/publish_page.dart` — the publish sheet:
  - conformance status banner (ok / fixable / blocked + reasons);
  - format (auto: PNG/GIF, shown read-only) + live file size vs 5 MiB;
  - title (≤128), description (≤5000), hashtags (comma → lowercased ≤64), license dropdown, "post as hidden",
    "allow others to edit" (for C3 remix);
  - submit → progress → success (links to the new post) / typed errors;
  - metadata **draft** saved to `shared_preferences`, restored on reopen.

## 5. Editor integration

- `main.dart`: replace `_uploadToClub()` (and its `http` dialog, `_clubUrl`/`_clubToken` fields) with a
  **Post to Club** action that:
  1. reads `engine.width/height/frameCount`;
  2. exports bytes (`exportPng`/`exportGif`) — passed into the publish flow via a callback so `lib/club` never
     imports the engine;
  3. opens `PublishPage`.
- The AppBar's cloud-upload icon now routes here. The engine handle stays in the editor; `lib/club` receives
  only bytes + dims (clean boundary, engine stays network-free).

## 6. Deferred: scale-to-conformant

True auto-scale needs an engine **`ScaleCanvas(w,h, filter)`** (nearest-neighbor) op + FFI. Out of scope for
C2 (would require a DLL/.so rebuild). For now: non-conformant art is **blocked with a clear message** naming the
nearest conformant size, and the user is pointed to the editor's existing **Resize** (crop/pad). Tracked as a
future engine task; when added, the publish gate gains a one-tap "Scale to {w×h}".

## 7. Tests (Tier-1)
- `conformance_test` — conformant 128×128 / 256×256 / 200×50; whitelisted 32×64 + rotation 64×32; rejected
  100×100 (<128 non-whitelist), 300×300 (>256); oversize bytes; nearestConformantSize suggestions.

## 8. Risks
- `/config/upload` may not exist yet → hardcoded fallback (noted in-app + plan); verify via curl at start.
- `/post/upload` field names/῾multipart shape: confirm `image`, `title`, `description`, `hashtags`,
  `hidden_by_user`, `license_id` (from the server router) — re-verify; the upload is auth-gated so can't be
  curled anonymously (device/test-account verifies).
- Removing the legacy uploader must keep the editor compiling (drop its fields + dialog cleanly).

---

## Progress
- [ ] Plan written + self-reviewed
- [ ] conformance.dart + tests
- [ ] license_option model + upload_api (+ licenses) + publish_providers
- [ ] publish_page UI
- [ ] editor integration (replace legacy uploader)
- [ ] analyze + test + Android build; C2 acceptance

### Notes / findings
- (none yet)
