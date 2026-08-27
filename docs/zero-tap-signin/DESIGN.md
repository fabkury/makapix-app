# Zero-Tap Sign-In (Android Restore Credentials) — design

**Status:** design only, nothing implemented. Written 2026-08-27 in response to the Google Play
"Elevating app quality" announcement of 2026-08-26.

**Deadline:** April 2027 (Play enforcement). Not urgent; this document exists so the work is scoped
before it becomes urgent, and so the measured baseline below is not re-discovered from scratch.

---

## 1. Why

Google Play is introducing a device-migration onboarding standard. Apps that support sign-in must
implement the **Android Restore Credentials API** so that a user who moves to a new device is silently
signed back in on first launch. Non-compliance is penalized with reduced store visibility and
publishing capability.

Makapix Club has sign-in (server-brokered GitHub OAuth, Apple, and the `/auth/token` grants), so it is
in scope. Games are exempt; we are not a game. Mobile and tablet only — the Windows build is unaffected.

Separately enforced from February 2027, and **already satisfied by construction**, are the memory and
code-optimization requirements:

- *Dynamic memory* (anon RSS + swap, p90 over 28 days): the floor is 2 GB foreground on a 4 GB device.
  Our enforced budgets (96 MiB history + 256/320 MiB document + 48 MiB replay checkpoints) sit far
  below that, because we already engineer against the tighter ~1 GiB scudo wall (`docs/memlab/REPORT.md`).
- *Bitmap memory* (>200 MB background / >400 MB cached): measures `android.graphics.Bitmap`. Flutter
  allocates via Skia's `ui.Image`, and we run no background services. Expect ~0 reported.
- *Code optimization* (25% R8 coverage, **only when DEX > 10 MB**): measured on `app-release.aab` —
  a single `classes.dex` of **1.81 MiB**. Dart is AOT-compiled into `libapp.so`, so our DEX is only the
  Flutter embedding plus plugin glue. The requirement never engages. Do **not** enable R8 speculatively;
  it risks reflection breakage in `flutter_secure_storage` / `file_picker` / `flutter_web_auth_2` for
  zero compliance benefit.

One reporting nuance worth remembering: our out-of-memory failure mode is `panic = "abort"` → SIGABRT,
which is not an OS memory kill. It lands in Android vitals as an ordinary native crash, so Play's new
"OOM crash filter" will not surface our real memory failures.

---

## 2. Measured baseline — what a migration does to us today

Reproduced on a Pixel 10 Pro XL (Android 16), 2026-08-27, with the shipped `app-release.apk`.
Method: local-transport Auto Backup, then uninstall (new UID, so the app's Keystore entries are purged
— the faithful analogue of a new device), reinstall the byte-identical APK, `bmgr restore`, relaunch.

**Result — art survives, the session does not.**

| Data | Outcome |
|---|---|
| Drawings, autosave, frames, layers, palette, artwork names | **Fully restored.** "Paws2025+Cat&fishbowl", 128x128, 24 frames came back intact. |
| Auth tokens (`SecureTokenStore`) | **Lost.** User lands on the signed-out welcome screen. |
| Process stability | **No crash.** Degrades gracefully. |

The backup payload was 13.1 MB. The token failure is logged as:

```
E StorageCipher18Impl: unwrap key failed
  java.security.InvalidKeyException: Failed to unwrap key
  Caused by: android.security.KeyStoreException: -30000 ... Finish failed for AppUid(10518)
```

**Mechanism.** `AndroidManifest.xml` declares no `android:allowBackup` and no `dataExtractionRules`, so
the platform default (`allowBackup="true"`) applies and Auto Backup includes `shared_prefs/`. Our
`SecureTokenStore` constructs `FlutterSecureStorage()` with no `AndroidOptions`, which on v9.x selects
the legacy scheme: a Keystore RSA key wraps an AES key, and the ciphertext lives in a `FlutterSecureStorage`
SharedPreferences file. The **ciphertext is backed up; the Keystore key is not and cannot be** (it is
hardware-backed and non-exportable). On restore the app finds ciphertext it can never unwrap.

This is not a bug to fix by making the tokens survive — tokens *should not* be transferable that way.
It is exactly the gap Restore Credentials is designed to fill.

### 2.1 Decision: keep the drawings backed up

Confirmed by the test: local art migrates correctly and users would want that. **Keep
`getApplicationSupportDirectory()` in the backup set, replay journals and checkpoints included.**

Two follow-ups, neither blocking:

- The `FlutterSecureStorage` prefs file should be **excluded** from backup via `dataExtractionRules`.
  It can never be decrypted after a restore, so backing it up transfers nothing but a guaranteed error.
  Excluding it also removes the `StorageCipher18Impl` stack trace from first-launch logs.
- 13.1 MB for one active user is fine, but replay checkpoints are the unbounded term. Worth a size
  probe before this ships, not before.

---

## 3. What the API actually is

Restore Credentials is **passkey-shaped**: it uses the same server-side machinery as WebAuthn passkeys.
The restore key is created silently after sign-in, rides the cloud backup or D2D USB transfer, and is
silently asserted on the new device.

```kotlin
// androidx.credentials:credentials:1.5.0+ (1.7.0-alpha03 recommended)
// androidx.credentials:credentials-play-services-auth (same version)

// Create, immediately after a successful sign-in:
val req = CreateRestoreCredentialRequest(
    requestJson = requestJsonFromServer,   // WebAuthn PublicKeyCredentialCreationOptionsJSON
    isCloudBackupEnabled = true,
)
credentialManager.createCredential(context, req)

// Retrieve, on first launch after migration:
val opt = GetRestoreCredentialOption(authenticationJsonFromServer)
val res = credentialManager.getCredential(context, GetCredentialRequest(listOf(opt)))
val credential = res.credential as RestoreCredential

// Clear, on sign-out (required):
credentialManager.clearCredentialState(
    ClearCredentialStateRequest(TYPE_CLEAR_RESTORE_CREDENTIAL))
```

Constraints that shape the design:

- **One account per app.** We are single-account today, so this costs us nothing.
- **Mobile/tablet only**, and restore keys are bound to the package name (`club.makapix.app`).
- `E2eeUnavailableException` when cloud backup or a screen lock is absent — must be caught and retried
  with `isCloudBackupEnabled = false` (local/D2D only).
- `CreateRestoreCredentialDomException` for malformed `requestJson`.

---

## 4. The server leg — DELIVERED 2026-08-27

This was expected to be the long pole (the server did OAuth brokering, not WebAuthn). It was
scoped, built, tested and deployed the same day. **The app is now the only remaining work.**

Exchange: `docs/zero-tap-signin/messages/` in the server repo (`reference/makapix-club`) —
0001 app kickoff, 0002 server decisions, 0003 app confirmation + notes, 0004 endpoints live.
The server's own `PLAN.md` / `PROGRESS.md` sit beside them.

### The live contract

```
POST /api/v1/auth/restore/options     (authenticated)   → creation options JSON
POST /api/v1/auth/restore/register    (authenticated)   → 204
POST /api/v1/auth/restore/challenge   (unauthenticated) → request options JSON
POST /api/v1/auth/token  { "grant_type": "restore_credential", "assertion": … }
                                      (unauthenticated) → standard token envelope

GET    /api/v1/auth/restore/credentials                 (authenticated)
DELETE /api/v1/auth/restore/credentials/{credential_id} (authenticated; id base64url)
```

Errors use the standard v1 envelope: `restore_credential_invalid` (verification failed, including
a replayed challenge) and `restore_credential_unknown` (no such credential/account — **treat as an
ordinary signed-out start, not an error**).

### Settled parameters

| | |
|---|---|
| `rp.id` | prod `makapix.club` · dev `app-dev.makapix.club` — **server-chosen**, sent inside `requestJson`; the app passes it through verbatim and needs no `CLUB_ENV` branching |
| `residentKey` | `required` (discoverable — the get leg is userless) |
| `userVerification` | `discouraged`, and verified with `require_user_verification=False` |
| `attestation` | `none`, and not required on verify |
| `userHandle` | 32 random bytes, minted on first `/restore/options`, stable after |
| Challenges | single-use, 5-minute TTL |
| Re-registration | upserts on `credential_id`, so the `E2eeUnavailableException` retry is safe |
| Rate limit | `/restore/challenge` has its own bucket (30/5min/IP), separate from login, so a probing migrated device can't lock out the sign-in that follows |

**Origins.** Verified: the server's three `apk-key-hash` values are exactly
`base64url(SHA-256(cert))`, unpadded, of our assetlinks fingerprints. **Prod accepts only the
upload and Play app-signing origins; dev additionally accepts debug.** So a `flutter run` build
authenticates against dev and is refused by prod — which matches how we test, but means a
debug-signed build can never be used to smoke-test prod.

**Assetlinks are live** on both `app-dev.makapix.club` (additive `get_login_creds`, `handle_all_urls`
untouched) and the apex `makapix.club`. The server rode the Caddy change to main and restarted caddy
*before* announcing, so the endpoints and the association became usable at the same moment.

**Prod is already deployed.** Nothing asserts against it until we ship, so the planned "joint flip"
reduces to our app release.

Note there is **no attestation check** on register — deliberately, since `attestation: "none"`
means there is no attestation statement. Verification covers challenge, origin, RP ID hash and
signature.

There is **no Flutter plugin** for Restore Credentials (pub.dev search, 2026-08-27, returned nothing).

---

## 5. App-side architecture

Our Android native surface is currently just `MainActivity`, so this introduces a new one.

1. **Kotlin platform channel** — a small `RestoreCredentialsPlugin` exposing three methods:
   `create(requestJson, allowCloud)`, `get(authenticationJson)`, `clear()`. It wraps `CredentialManager`
   and maps the exception types above onto channel errors. This is the only new native code.
   *Note ADR 0009: commands go through shell methods only. This is a platform channel for a platform
   capability, not a new command surface — keep the seam that narrow.*
2. **Dart side**, in `app/lib/club/auth/`, alongside `SecureTokenStore`:
   - after a successful sign-in, fetch creation options and call `create()`;
   - on cold start, when `SecureTokenStore.read()` returns null, attempt `get()` **before** routing to
     the welcome screen; on success exchange the assertion for tokens and continue signed in;
   - on sign-out, call `clear()` alongside `SecureTokenStore.clear()`.
3. **`dataExtractionRules`** excluding the `FlutterSecureStorage` prefs file, keeping everything else.
4. **Failure is always silent.** Any error path falls through to the existing welcome screen — today's
   behavior. Zero-Tap is an enhancement, never a gate on reaching the app.

Club unit tests must keep running without the engine binary or network; the channel needs a fake.

---

## 6. Risks and open questions

- ~~Server WebAuthn support is a prerequisite and is not scheduled.~~ **Resolved** — delivered and
  live on dev and prod, 2026-08-27. See section 4.
- **The UV assumption is still unconfirmed on real hardware.** We reasoned from mechanism (restore
  assertions are silent → the UV flag is unset), and the server set `discouraged` /
  `require_user_verification=False` on that basis, but Android's guide never pins these fields and
  their tests use a software authenticator. **The M3 device run is the empirical check**, and the
  server explicitly asked for that confirmation in 0004. If it fails, this is the first thing to
  look at — a UV mismatch surfaces as a generic verification error that reads like a signature or
  origin problem.
- `androidx.credentials` was at `1.7.0-alpha03` when this was written. Verify the stable version and
  confirm the minSdk implications before committing; we inherit minSdk from Flutter.
- Adding `credentials` + `credentials-play-services-auth` will grow the DEX. Currently 1.81 MiB against
  a 10 MB trigger, so there is ample headroom, but re-measure after the dependency lands.
- Interaction with the AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20 pinning is unknown; `androidx.credentials`
  may pull a newer AGP expectation. Check before unpinning anything.
- iOS is unaffected by the Play requirement, but Keychain already migrates sessions there. Confirm
  rather than assume.

---

## 7. Explicitly out of scope

- Enabling R8 (see section 1 — the requirement does not apply to us).
- Any memory work motivated by this announcement; the memlab budgets already clear the thresholds.
- Multi-account support.
- Passkeys as a *primary* sign-in method. Restore Credentials reuses the passkey server machinery, but
  offering passkey login in the UI is a separate product decision and is not proposed here.

---

## 8. Reference

- Play Console technical quality requirements: https://support.google.com/googleplay/android-developer/answer/17492799
- Announcement: https://android-developers.googleblog.com/2026/08/app-quality-memory-optimization-secure-onboarding.html
- Restore Credentials: https://developer.android.com/identity/sign-in/restore-credentials
- Implementation guide: https://developer.android.com/identity/sign-in/restore-credentials-implementation
