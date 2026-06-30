# C0b — In-app account creation (`app/lib/club/`)

**Phase:** C0b — a follow-on to C0 (auth foundation, SPEC-CLUB §6). Closes the last gap that made the app
tell users to *"Sign up at makapix.club"*.
**Status:** 🟡 in progress — see [Progress](#progress) at the bottom.
**Owner:** app team. **Last updated:** 2026-06-29.

---

## 1. Goal & acceptance

Let a user **create a Makapix Club account entirely inside the app** — no website detour — and finish onboarding,
recover a lost password, and manage the account afterwards. When C0b is done:

- From the signed-out funnel a user can **Create account** (email), **verify by a 6-digit code**, **sign in**, and
  is dropped into a short **welcome wizard** (set password · pick a handle · optional avatar/bio) before the feeds.
- **Forgot password?** on the sign-in screen runs a numeric-OTP reset.
- **Settings → Account** lets a signed-in user change password, change handle, and view/unlink linked logins.
- **Sign up with GitHub** is surfaced as a first-class path (it already creates accounts server-side).

**Acceptance tests:**
- **Tier-1 (Windows, `flutter test`):** password/handle validators mirror the server; `ClubError` branches the
  register 409s (`pending_verification` vs already-exists) and the OTP envelope codes; the `RegistrationController`
  step machine advances email → code → sign-in → done with a fake `AuthApi`; result models parse.
- **Static:** `flutter analyze` clean for `lib/club`.
- **Device/desktop (user-run):** `build.ps1 -Run` against `development.makapix.club` with a real inbox: register →
  receive the code + temp password → verify → sign in → wizard → land in Club. Re-run forgot-password and the
  Settings change-password/handle/unlink paths.

**Non-goals (deferred):** email **deep-linking** of the verification/reset link (needs hosted `assetlinks.json` +
intent filters — tracked in the handover doc §2/§6); session/device management UI (brief §3.6); account-deletion UI.

---

## 2. The decision that shapes this flow

The server's `POST /auth/register` is **email-only**: it generates a **random password**, emails it together with a
24 h **verification _link_** (not a code), and returns `{ user_id, email, handle }` with **no tokens**. There is no
way to choose a password at signup, and the register email carries a link, not an OTP.

Chosen path (per product decision): **"use the emailed password" + in-app numeric OTP verification**, with no server
changes. Consequences we design around:

- The numeric code is a **separate** call (`/auth/email-otp/request`) → the user receives **two emails**: (A) the
  register email with the *temporary password* + a web link, and (B) the **6-digit code**. The verify screen copy
  makes this explicit. *(A future one-line server tweak — have `register` also issue the OTP, or fold the temp
  password into the OTP email — collapses this to one email; tracked in `club-server-change-requests.md`. Not
  required here.)*
- After verifying, the user signs in with the **temporary password from email A**. The app holds it in memory and
  **pre-fills `current_password`** in the wizard's "set your password" step, so the user types only their new one.

---

## 3. Server contract used (all confirmed in `reference/` `main`)

Base `…/api/v1`. **Unauthenticated** (account lifecycle):

| Step | Endpoint | Notes |
|---|---|---|
| Register | `POST /auth/register { email }` → 201 `{ user_id, email, handle }` | 409 `detail:"pending_verification"` (unverified exists) / 409 `detail:"An account…exists"` (verified). Rate 30/h/IP. |
| Request code | `POST /auth/email-otp/request { email }` → 200 (existence-neutral) | 6-digit, 10-min TTL. Per-IP 30/10 min; per-user 6/h. |
| Verify code | `POST /auth/email-otp/verify { email, code }` → `VerifyEmailResponse` | Sets `email_verified`; returns `handle`, `needs_welcome`. Bad code → `token_invalid` (400). Verify throttle 5/10 min/email, 20/10 min/IP. |
| Forgot → request | `POST /auth/password-otp/request { email }` → 200 (neutral) | 6-digit, 10-min TTL. |
| Forgot → confirm | `POST /auth/password-otp/confirm { email, code, new_password }` → 200 | Does **not** verify email; resets password only. |
| Handle check | `POST /auth/check-handle-availability { handle }` → `{ handle, available, message }` | Works unauthenticated and authenticated (authed excludes own handle). |

**Authenticated** (bearer; goes through `ClubApiClient`):

| Step | Endpoint | Notes |
|---|---|---|
| First sign-in | `POST /auth/token { grant_type:"password", email, password }` | Already wired (`ClubSession.loginPassword`). 403 `email_not_verified` before verify. |
| Set/Change password | `POST /auth/change-password { current_password, new_password }` | New ≥8, ≥1 letter, ≥1 digit. |
| Change handle | `POST /auth/change-handle { new_handle }` → `{ handle }` | Requires verified email; `owner` locked; 3–32, charset `[A-Za-z0-9_-]`, no leading/trailing `-`/`_`, case-insensitive unique. |
| Finish welcome | `POST /auth/complete-welcome` → 204 | Flips `needs_welcome`. |
| Linked logins | `GET /auth/providers` → `{ identities:[…] }`; `DELETE /auth/providers/{provider}/{identity_id}` → 204 | 400 if unlinking the last method. |
| Avatar / bio | `POST /user/{user_key}/avatar` (multipart `image`); `PATCH /user/{user_key} { bio }` | Avatar ≤5 MB; PNG/GIF/WebP/JPEG. |

Mirror client-side (server stays source of truth): **password** ≥8 / ≥1 letter / ≥1 digit; **handle** 3–32 /
`[A-Za-z0-9_-]` / no leading/trailing `-`/`_`.

---

## 4. End-to-end flow

```
Welcome ─▶ Create account (email) ─▶ register {email}
                                       └▶ email-otp/request {email}            (code emailed)
        ─▶ Enter 6-digit code ─▶ email-otp/verify {email, code}               → verified, needs_welcome
        ─▶ First sign-in (temp pw)─▶ token {grant_type:password}              → signed in (temp pw kept in memory)
        ─▶ Welcome wizard (gated by needs_welcome):
              • Set your password   change-password {current=temp, new}        (step shown only when temp pw known)
              • Pick a handle       check-handle-availability → change-handle
              • Avatar + bio (opt)  /user/{key}/avatar · PATCH /user/{key}
              • Finish              complete-welcome                            → reload /auth/me → Club home

Sign-in screen ─▶ Forgot password? ─▶ password-otp/request → password-otp/confirm → back to sign-in
Settings → Account ─▶ change-password · change-handle · linked logins (list/unlink)
```

409 handling on register: `pending_verification` → skip straight to the code step (request a fresh code);
already-exists → route to sign-in with a message.

---

## 5. Architecture (all app-layer; the Rust engine is untouched)

```
app/lib/club/
├─ models/
│  └─ account.dart            RegisterResult · VerifyEmailResult · HandleAvailability · AuthIdentity
├─ auth/
│  └─ account_validators.dart isValidEmail · validatePasswordError · validateHandleError   (pure, tested)
├─ api/
│  ├─ auth_api.dart           UNAUTH lifecycle (plain Dio): register · email-otp/{request,verify} ·
│  │                          password-otp/{request,confirm} · check-handle-availability
│  └─ club_api_client.dart    (+authed) changePassword · changeHandle · checkHandle · completeWelcome ·
│                             listProviders · unlinkProvider · updateBio · uploadAvatar
├─ state/
│  ├─ api_providers.dart      (+) authApiProvider
│  ├─ account_providers.dart  pendingWelcomePasswordProvider · welcomeDismissedProvider
│  ├─ registration_controller.dart  RegistrationController (StateNotifier; step machine + temp-pw stash)
│  ├─ onboarding_controller.dart     OnboardingController (handle availability, change-pw/handle, profile, finish)
│  ├─ password_reset_controller.dart PasswordResetController (request → confirm)
│  └─ auth_controller.dart    (+) reloadMe()
└─ ui/auth/
   ├─ create_account_page.dart   ONE route hosting email → code → sign-in steps; pops on success
   ├─ onboarding_wizard.dart     the welcome wizard (gated render in ClubHomePage)
   ├─ forgot_password_page.dart  OTP reset
   └─ account_management_page.dart  change password / handle / linked logins
```

**Refresh/recursion:** `AuthApi` uses a **plain Dio** (no bearer, no 401 interceptor), like `ClubSession` — the
lifecycle endpoints are unauthenticated, and this avoids any interaction with the refresh interceptor.

**Sign-in reuse:** the "first sign-in" step calls `ClubSession.loginPassword` then `AuthController.reloadMe()`, so
the existing token/secure-storage path is reused verbatim; `AuthController` stays the single signed-in/out source.

**The `needs_welcome` gate** lives in `ClubHomePage.build`: signed-in **and** `me.needsWelcome` **and** not locally
dismissed → render `OnboardingWizard` instead of the feeds. `ClubMe.needsWelcome` already exists.

**Dependency direction:** `models` ← everything; `auth` validators are leaf; `api` ← `state`; controllers ←
`state`/`api`; `ui/auth` ← `state`. No cycles.

---

## 6. UI wiring

- `club_account_page.dart` `_SignInForm`: replace the static *"Sign up at makapix.club…"* line with a **Create
  account** button → `CreateAccountPage`, and add **Forgot password?** → `ForgotPasswordPage`. Keep **Continue with
  GitHub**.
- `create_account_page.dart`: also offers **Sign up with GitHub** (same `AuthController.loginGithub`).
- `club_home_page.dart`: add the `needs_welcome` gate (renders `OnboardingWizard`); add a **Manage account** entry
  to the menu/account view.
- `settings_page.dart`: add an **Account** section → `AccountManagementPage`.

---

## 7. Tests (`app/test/club_account_test.dart`)

- `account_validators`: password (len/letter/digit) and handle (len/charset/edges); email shape.
- `ClubError` register branching: 409 `pending_verification` vs already-exists; OTP `token_invalid`; 429 +
  `Retry-After`.
- `RegistrationController` with a **fake `AuthApi`**: email → (register + request) → code step; verify → sign-in
  step; already-exists → error+stay; resend; pending_verification → jump to code.
- Result-model parsing (`RegisterResult`, `VerifyEmailResult`, `HandleAvailability`, `AuthIdentity`).

---

## 8. Risks / decisions

- **Two emails** (temp password + separate code) is the cost of "use emailed password" + OTP with no server change.
  Mitigated by explicit verify-screen copy; a future server tweak removes it (§2).
- **Temp-password carry-forward:** stored only in memory (`pendingWelcomePasswordProvider`), cleared on wizard
  finish/failure; never persisted or logged. If the app is killed mid-flow, the user falls back to "Forgot
  password?" or signing in with the emailed temp password.
- **Register 409s arrive as FastAPI `{detail}`** (so `ClubError.code=='error'`); branch on `status==409` + message.
  The OTP/token endpoints use the stable-`code` envelope.
- **GitHub-only / returning-unwelcomed users** also hit the wizard (`needs_welcome`); the password step is skipped
  when no temp password is known. `complete-welcome` finalizes; a **Skip for now** sets a session-local dismiss so a
  `complete-welcome` outage can never hard-lock the app.
- **Avatar** uses `file_picker` (already a dep; `FileType.image`, `withData:true`) → bytes → multipart. Optional and
  skippable everywhere.
- **`flutter_web_auth_2` desktop** is unreliable, so GitHub sign-up is an Android-device path; email registration
  works on desktop.

---

## Progress

- [x] Plan written + self-reviewed (this file)
- [x] models/`account.dart` + auth/`account_validators.dart`
- [x] api/`auth_api.dart` + `club_api_client.dart` authed methods + `authApiProvider`
- [x] state: `account_providers.dart`, `registration_controller.dart`, `onboarding_controller.dart`,
      `password_reset_controller.dart`, `auth_controller.reloadMe()`
- [x] ui/auth: create-account, onboarding-wizard, forgot-password, account-management
- [x] wiring: sign-in form buttons, `needs_welcome` gate, settings Account section
- [x] tests + `flutter test` (94 pass, 15 new) + `flutter analyze` clean for lib/club
- [ ] Device/desktop end-to-end (user) — `build.ps1 -Run` against dev

**C0b status: code-complete.** Only the live end-to-end run against `development.makapix.club` (needs a real
inbox to read the OTP + temp password) remains — user-run.

### Notes / findings
- The server's `/auth/register` only issues a **link** token, never an OTP, so the in-app flow makes a second
  `email-otp/request` call → the user gets **two emails** (temp password + 6-digit code). The verify-screen copy
  states this. **Resolved in principle (A2):** the server team accepted a change letting `register` accept an
  optional `password` and send a single OTP email — see `docs/club-server-cr-register-chosen-password.md`
  (✅ accepted) and `inbox/reply-register-chosen-password.md`.

### A2 "one email, chosen password" — ✅ IMPLEMENTED (2026-06-30, live on dev)
The server shipped A2 to `development.makapix.club`; the app now uses it (still version-tolerant — it falls back
to the temp-password flow if a server ever returns `"link"`):
- The create-account screen takes a **password**; `register { email, password }` is sent (`AuthApi.register`).
- `RegisterResult.verificationMethod`: `"otp"` → go straight to the code step (no `email-otp/request` call) and,
  after verify, **auto sign-in** with the chosen password — the temp-password screen is skipped. `"link"`/absent
  or a `pending_verification` 409 → legacy fallback (request OTP, temp-password sign-in).
- The wizard's **"set your password" step is skipped** on the A2 path (`pendingWelcomePasswordProvider` left null);
  only the legacy temp-password path stashes it.
- `RegistrationController` rewritten (`submitDetails(email, password)`, `isLegacy`, `_completeSignIn(stash:)`);
  `RegStep.email` → `RegStep.details`.

### Sign-in recovery: "Email not verified" → verify path — ✅ IMPLEMENTED (2026-06-30)
Device testing surfaced a dead end: signing in with an **unverified** email showed *"Email not verified"* with no
way forward. Fixed:
- `AuthState` now carries `errorCode` + an `isUnverified` helper (tolerant of envelope/message differences).
  `AuthController.loginPassword` threads `ClubError.code`.
- The sign-in form shows a **"Verify your email"** button when `isUnverified`, opening `ui/auth/verify_email_page.dart`
  (enter the OTP they have, or **Resend**), seeded with the typed email + password so a successful verify signs
  them straight in. Backed by `state/verify_email_controller.dart`.

### Still backstopped server-side
- The new **`weak_password`** 400 (v1 envelope; field under `details.field`) is enforced by the server; the app
  also pre-validates client-side.
- The `"link"` / no-password path (website parity, GitHub users) still routes through the wizard.
- The onboarding password step intentionally does **not** clear the stashed temp password (that would shrink the
  gated step list and skip the handle step); it is cleared in `OnboardingController.finish()`.
- file_picker 11 uses the static `FilePicker.pickFiles(...)` (no `.platform` singleton).
- GitHub sign-up reuses the existing C0 `loginGithub` (new GitHub identities are created + pre-verified
  server-side) and also routes through the `needs_welcome` wizard, which skips the password step (no temp pw).
