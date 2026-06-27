# C0 — Auth Foundation (`app/lib/club/`)

**Phase:** C0 of the Makapix Club social pillar (SPEC-CLUB §28).
**Status:** 🟡 in progress — see [Progress](#progress) at the bottom.
**Owner:** app team. **Last updated:** 2026-06-26.

---

## 1. Goal & acceptance

Stand up the **authentication foundation** for the Club social layer so every later phase (C1–C3) can make
authenticated calls. When C0 is done:

- A user can **sign in with email + password** and **with GitHub** (the server-brokered PKCE flow, already live
  on `development.makapix.club`).
- Tokens are **persisted in secure storage**; the access token auto-attaches to requests and **silently
  refreshes on 401** (single-flight).
- `GET /api/v1/auth/me` is loaded; a minimal **"signed in as …"** screen shows handle / roles / quotas.
- The editor remains fully usable; auth is reachable via an **Account** button (the app is *not* login-gated
  yet — that IA comes later).

**Acceptance tests:**
- **Tier-1 (Windows, `flutter test`):** PKCE challenge matches the RFC 7636 vector; `ClubError` parses both
  envelopes; the GitHub authorize URL is built with the agreed params; token (de)serialization round-trips.
- **Static:** `flutter analyze` clean.
- **Device (user-run):** `build_android.ps1 -Install` → Account → "Continue with GitHub" → complete on device →
  land back signed-in showing `/auth/me`. Email+password also testable from the Windows desktop build.

**Non-goals (deferred):** push notifications (needs `/me/push-tokens`); session/device management UI; the full
login-gated bottom-nav IA; capabilities-driven UI gating beyond display; account deletion UI.

---

## 2. The server contract (confirmed, live on dev)

Base: `https://development.makapix.club/api/v1` (default for now; prod `https://makapix.club/api/v1`).

- **Token endpoint** `POST /auth/token` (JSON), three grants:
  - `{ "grant_type":"password", "email":…, "password":… }`
  - `{ "grant_type":"authorization_code", "code":…, "code_verifier":… }`
  - `{ "grant_type":"refresh_token", "refresh_token":… }`
  - → `200 { access_token, token_type:"Bearer", expires_in, refresh_token, user }`.
- **GitHub flow:** open `GET /auth/github/login?redirect_uri=club.makapix.editor://oauth/github&code_challenge=<S256>&code_challenge_method=S256&state=<rand>` in an in-app browser → returns to
  `club.makapix.editor://oauth/github?code=<makapix_code>&state=<rand>` (or `?error=&error_description=&state=`).
  Code is **single-use, 120 s TTL**, PKCE-bound. Exchange via the token endpoint.
- **Identity:** `GET /auth/me` → `{ user, roles, capabilities, quotas, moderation, needs_welcome }`. The access
  token's `sub` is the user's `public_sqid` and carries `roles`.
- **Errors:** v1 envelope `{ "error": { "code", "message" } }` (also tolerate FastAPI `{ "detail" }`).
- **PKCE:** S256 only; `code_challenge = BASE64URL_NOPAD(SHA256(code_verifier))`; verifier 43–128 chars
  (RFC 7636). `state` is validated by the app on return.
- **Gotchas:** `/api/*` bypasses dev Basic Auth; the OAuth-state HttpOnly cookie must persist across the
  round-trip (use a non-ephemeral web-auth session); nothing to register on GitHub (server-brokered).

---

## 3. Architecture (all app-layer; the Rust engine is untouched)

```
app/lib/club/
├─ config/
│  └─ club_config.dart        ClubEnvironment {dev,prod}; base/api URLs; OAuth scheme + redirect URI
├─ models/
│  ├─ auth_tokens.dart        AuthTokens (access, refresh, expiresAt) + fromJson
│  ├─ club_user.dart          ClubUser (sub/public_sqid, handle, avatarUrl, email?) + ClubMe (user, roles,
│  │                          capabilities, quotas, needsWelcome)
│  └─ club_error.dart         ClubError {status, code, message, retryAfter?} + fromResponse/fromDio
├─ auth/
│  ├─ token_store.dart        SecureTokenStore over flutter_secure_storage (read/write/clear AuthTokens)
│  ├─ pkce.dart               Pkce.generate() -> {verifier, challenge, state}; challengeFor(v) (testable)
│  ├─ github_oauth.dart       GithubOAuth.authorize() -> {code, verifier}; builds URL, runs web-auth,
│  │                          validates state, maps error redirects
│  └─ club_session.dart       Token lifecycle: in-memory tokens + store; loginPassword / exchangeAuthCode /
│                             refresh (single-flight) / logout / load; plain Dio for grant calls
├─ api/
│  └─ club_api_client.dart    Authed Dio (baseUrl=api): bearer interceptor + 401→refresh→retry; ClubError
│                             mapping. Used for /auth/me now and all social endpoints later (C1+).
├─ state/
│  └─ auth_controller.dart    Riverpod providers + AuthController (StateNotifier<AuthState>):
│                             init/loginPassword/loginGithub/logout; AuthState {status, me?, error?}
└─ ui/
   ├─ club_account_page.dart  watches authState → SignInForm or AccountView; entry from editor AppBar
   ├─ sign_in_form.dart       email/password + "Continue with GitHub" + loading/error
   └─ account_view.dart       handle/roles/quotas + Sign out
```

**Refresh without recursion:** `ClubSession` uses a *plain* Dio (no interceptors) for `/auth/token` calls, so a
refresh triggered by the authed client's 401 interceptor never recurses. The 401 interceptor calls
`session.refresh()` (single-flight via a shared `Future`), then retries the original request once (guarded by an
`extra` flag); on refresh failure it clears tokens and surfaces an auth error → controller signs out.

**Dependency direction:** `config` ← everything; `models` ← `auth`,`api`,`state`; `auth` (session/oauth/pkce/
store) ← `state`; `api` ← `state`; `ui` ← `state`. No cycles.

---

## 4. App wiring

- `main()` → `runApp(const ProviderScope(child: MakapixApp()))` (add `flutter_riverpod`).
- `MaterialApp.title` → `'Makapix Club'`.
- `EditorPage` AppBar actions: add an **account** `IconButton` (person icon) → `Navigator.push(ClubAccountPage)`.
- `authControllerProvider` notifier calls `init()` in its constructor: load tokens; if present, fetch `/auth/me`
  → signedIn, else signedOut. Non-blocking; the editor never waits on it.

## 5. Dependencies (`app/pubspec.yaml`)

Add: `flutter_riverpod: ^2.5.1`, `dio: ^5.7.0`, `flutter_secure_storage: ^9.2.2`, `flutter_web_auth_2: ^4.1.0`,
`crypto: ^3.0.5`. (`http` stays for now — the legacy uploader uses it; C2 migrates it to dio.) Pin to the latest
stable compatible with Flutter 3.44; resolve with `flutter pub get` and adjust if the resolver complains.

## 6. Android manifest (flutter_web_auth_2 callback)

Inside `<application>` of `app/android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
    android:exported="true">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="club.makapix.editor" />
    </intent-filter>
</activity>
```

`callbackUrlScheme = 'club.makapix.editor'` (matches the server-allowlisted `club.makapix.editor://oauth/github`).

## 7. Tests (`app/test/`)

- `club_pkce_test.dart` — `Pkce.challengeFor("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")` ==
  `"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"` (RFC 7636 vector); verifier charset/length; challenge is
  base64url **without padding**.
- `club_error_test.dart` — parses `{error:{code,message}}` and `{detail}`; carries status + Retry-After.
- `club_auth_url_test.dart` — `GithubOAuth` builds `…/auth/github/login` with `redirect_uri`,
  `code_challenge`, `code_challenge_method=S256`, `state` (and the redirect URI is exactly the allowlisted one).
- `auth_tokens_test.dart` — `AuthTokens.fromJson` maps the token response; `expiresAt` ≈ now + `expires_in`;
  store round-trip (in-memory fake).

## 8. Risks / decisions

- **`flutter_web_auth_2` desktop:** custom-scheme callback is solid on Android/iOS; on Windows desktop it's
  unreliable. → the **GitHub round-trip is an Android-device test**; email/password works on desktop. Documented.
- **Token response `user` shape** is parsed **defensively** (fields optional); `/auth/me` is the source of truth
  for the full profile. If `user` is thin, we still call `/auth/me`.
- **Secure storage on Android** uses the default (EncryptedSharedPreferences); fine for tokens. Exclude from
  auto-backup is a later hardening item (note only).
- **Logout** clears local tokens only. The existing `/auth/logout` is *cookie-based* (revokes the refresh
  **cookie**), which doesn't apply to our body-delivered refresh token, so we don't call it. Server-side
  revoke-by-body is pending brief §3.6; until then a refresh token lives until expiry — acceptable for now.
- **Identity source of truth:** ignore the token response's `user` field (shape may be thin); always call
  `/auth/me` after a successful grant. `ClubSession` deals only in `AuthTokens`; `AuthController` loads `ClubMe`.
- **Web-auth session is non-ephemeral** (`FlutterWebAuth2Options(preferEphemeral: false)`) so the OAuth-state
  HttpOnly cookie persists from `/github/login` to the callback (server gotcha #2).
- **Clock:** uses `DateTime.now()` (app layer only; the deterministic engine is untouched). `expires_at` drives
  proactive refresh; 401 refresh is the backstop.

## 9. Verification I run here vs. you run on device

- I run: `flutter pub get`, `flutter analyze`, `flutter test`. (A full `flutter build apk` needs the JBR + the
  Rust `.so` from `build_android.ps1`; I'll attempt a build if cheap, else leave it to your device step.)
- You run: `build_android.ps1 -Install`, then the GitHub round-trip on the phone.

---

## Progress

- [x] Plan written + self-reviewed (this file) — 3 refinements folded into §8
- [x] Deps added; `flutter pub get` resolves (39 deps)
- [x] `config/` + `models/` (tokens, user, error)
- [x] `auth/`: pkce, token_store, github_oauth, club_session
- [x] `api/club_api_client.dart` (bearer + single-flight refresh)
- [x] `state/auth_controller.dart` (Riverpod)
- [x] `ui/` sign-in + account; AppBar Account entry; `ProviderScope` + manifest
- [x] Tests written; `flutter test` (13 pass) + `flutter analyze` clean for lib/club
- [ ] Device round-trip (user) — acceptance: `build_android.ps1 -Install`

**C0 status: code-complete.** Only the on-device GitHub round-trip remains (user-run).

### Notes / findings
- `flutter pub get` resolved 39 deps at the pinned ranges (riverpod 2.6.1, dio 5.x,
  flutter_secure_storage 9.x, flutter_web_auth_2 4.x → pulls url_launcher, crypto 3.x). No conflicts.
- `flutter analyze`: **0 issues in lib/club**. 12 pre-existing `info`s remain in the editor's `main.dart`
  (deprecated `Color.red/.green/.blue/.alpha` + one `use_build_context_synchronously`) — predate C0, left
  untouched (out of scope for this phase).
- `flutter test`: **13/13 pass**, including the PKCE S256 RFC 7636 vector
  (`dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` → `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`),
  confirming our challenge generation matches the server's.
- Endpoint independently verified earlier via curl: `/api/v1/auth/github/login` 307s to GitHub carrying our
  state+challenge; a non-allowlisted `redirect_uri` → 400.
- **Android debug build passes**: `flutter build apk --debug` (JBR 21) → `app-debug.apk` built (exit 0). The
  new plugins (flutter_web_auth_2 / flutter_secure_storage / dio / riverpod / crypto) and the manifest
  `CallbackActivity` merge cleanly. Remaining device-bound step (user): the live GitHub sign-in round-trip via
  `build_android.ps1 -Install` (which also bundles the Rust `.so`).
