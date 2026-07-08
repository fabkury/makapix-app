# iOS build & Apple App Store release — plan

**Status:** planning · written 2026-07-06 · owner: Fabrício + Claude Code
**Goal:** ship the Makapix Club app to the **Apple App Store** (via TestFlight first), with **Android and
iOS both seamlessly supported from the one Flutter + Rust codebase** — no regressions to the existing
Android/Windows builds.

This doc is the single source of truth for the iOS effort. It is intentionally detailed (matching the
repo's SPEC-style docs). Update the **Decisions** and **Progress** sections as we go.

---

## 0. Decisions locked (2026-07-06)

Collected from the user before writing this plan:

| # | Decision | Choice | Consequence |
|---|----------|--------|-------------|
| D1 | Apple Developer Program | **Not enrolled yet** | Critical-path blocker — user enrolls ASAP (see §2, Phase 0). |
| D2 | Build strategy | **Cloud-Mac bootstrap → then CI** | One short interactive/headless cloud-Mac session to de-risk the first clean build, then move ongoing builds to free-tier CI. |
| D3 | Ongoing CI provider | **Codemagic** | Flutter-first, free macOS minutes, headless iOS signing + TestFlight upload with no Mac. |
| D4 | iOS bundle identifier | **Reuse `club.makapix.app`** | Same identity across stores; Apple bundle IDs are independent of Android's, so reuse is clean. |
| D5 | Cloud-Mac provider | **Claude picks; must be autonomously drivable after setup** → **Scaleway Mac mini (SSH)** primary, **AWS EC2 Mac** fallback | User does one-time provisioning + hands Claude root SSH; Claude then drives the whole build headlessly over SSH. GUI-only options (MacinCloud managed desktop) are excluded — can't be driven autonomously. |
| D6 | Sequencing | **Plan only; wait for user** | This plan is committed now; **implementation is on hold** until the user has (a) enrolled in the Apple Developer Program and (b) received the second-hand iPhone. |

### Open decisions to resolve before Phase 1 execution

- **OD1 — Sign in with Apple — RESOLVED 2026-07-06: add Sign in with Apple.** Apple guideline **4.8**
  requires apps offering a third-party/social login (our **GitHub OAuth**) to **also** offer *Sign in with
  Apple*. **Decision: implement Sign in with Apple alongside GitHub** (keep GitHub). Enable the *Sign in
  with Apple* capability on the App ID; add the `sign_in_with_apple` plugin + the `Runner.entitlements`
  capability; build the small server leg. See §6-R1.
- **OD2 — Universal Links vs custom scheme for the OAuth return on iOS** (see §5). MVP = **custom scheme
  only** (already server-allowlisted, zero server work). Universal Links (Associated Domains + a hosted
  `apple-app-site-association` file) is an optional polish that needs the *server* repo to host the AASA
  file — defer unless the custom-scheme UX is unacceptable.
- **OD3 — Minimum iOS deployment target — RESOLVED 2026-07-08: iOS 12.0** (user's choice for wider device
  reach). Compatible: `sign_in_with_apple` 6.1.4's pod floor is iOS 9, so no CocoaPods conflict; the Apple
  button self-hides below iOS 13 via `AppleOAuth.isAvailable()`. Confirm the second-hand iPhone's iOS
  version once bought (it can only raise the effective floor, never lower it).

---

## 1. Current-state findings (what the repo looks like today)

Verified against the tree on 2026-07-06:

- **No `app/ios/` project exists.** The Flutter app was scaffolded for Android/Windows only. First code
  step is `flutter create --platforms=ios .` inside `app/` to generate the `ios/Runner` Xcode project.
  (This template generation is pure files and *can* run on Windows; **compiling** it needs macOS.)
- **The FFI already anticipates iOS.** `app/lib/engine_ffi.dart` `_open()` returns
  `DynamicLibrary.process()` on iOS — i.e. the Rust engine must be **statically linked into the app
  binary**, not shipped as a loadable `.dylib`. Today `crates/ffi/Cargo.toml` is
  `crate-type = ["cdylib", "lib"]`; iOS needs **`staticlib`** added.
- **OAuth is iOS-ready on prod via the custom scheme.** `ClubConfig` already defines
  `oauthScheme = 'club.makapix.app'` and the prod return `club.makapix.app://oauth/github`, both
  **server-allowlisted byte-for-byte**. On iOS this is registered via `CFBundleURLTypes` in `Info.plist`.
  (Dev currently returns via the `app-dev.makapix.club` HTTPS App Link; on iOS the custom scheme works for
  both envs and is the simplest MVP — see §5.)
- **All 16 pubspec plugins support iOS** — no platform blockers:
  `cupertino_icons, ffi, file_picker, http, shared_preferences, path_provider, path, flutter_riverpod,
  dio, flutter_secure_storage (→ iOS Keychain), flutter_web_auth_2 (→ ASWebAuthenticationSession), crypto,
  share_plus, cached_network_image, flutter_cache_manager, url_launcher`.
- **Launcher icons skip iOS today.** `pubspec.yaml`'s `flutter_launcher_icons` block has
  `# iOS is intentionally omitted (deferred — no ios/ project)`. iOS icons must be **opaque (no alpha
  channel)** — we need an iOS-specific opaque master (see §4, Phase 1).
- **Version:** `1.0.8+13`. iOS maps build-name → `CFBundleShortVersionString`, build-number →
  `CFBundleVersion` (must be unique & monotonically increasing **per App Store Connect app**, tracked
  independently from Play's `versionCode`).
- **Rust engine** is `#![forbid(unsafe_code)]`, zero-dependency, deterministic — cross-compiles cleanly to
  Apple targets (`aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`). **Cross-compiling from
  Windows is impossible** (needs the Apple SDK + linker); this happens on the Mac / Codemagic only.

---

## 2. Phased plan

Five phases. Phase 0 is user-owned and runs **in parallel** with everything. Phases 1→4 are the build-out.
Per §0-D6 we execute nothing past this document until the user green-lights (enrolled + iPhone in hand).

### Phase 0 — Prerequisites (user-owned, start now, parallelizable)

- [ ] **P0.1 — Enroll in the Apple Developer Program** (`developer.apple.com/programs`, $99/yr). Identity
      verification can take hours-to-days; this gates TestFlight *and* App Store, so start immediately.
      Individual enrollment is fine (no D-U-N-S needed).
- [ ] **P0.2 — Buy the second-hand iPhone** (user is handling). Note its iOS version → confirms OD3.
- [ ] **P0.3 — Resolve OD1 (Sign in with Apple).** See §6-R1. Decide before Phase 1 so the auth surface is
      finalized. Recommendation below.
- [ ] **P0.4 — Create the App Store Connect app record** (once enrolled): App Store Connect → Apps → **+** →
      New App, platform iOS, bundle id `club.makapix.app`, SKU (e.g. `makapix-club-ios`), primary language.
- [ ] **P0.5 — Create an App Store Connect API key** (Users and Access → Integrations → App Store Connect
      API → Team Keys, role **App Manager**). Download the `.p8` **once** and store it in the repo's
      secret store (NOT in git). This key lets Codemagic/fastlane sign & upload **fully headlessly** — no
      interactive Apple ID on any Mac.

### Phase 1 — Repo iOS scaffolding (no Mac, no Apple account required to write; needs a Mac to *compile*)

All of this is editable on Windows. It is **on hold** per D6 but fully specified here.

- [x] **P1.1 — Generate the iOS project:** `cd app && flutter create --platforms=ios .`
      Produces `app/ios/` (`Runner.xcodeproj`, `Runner/Info.plist`, `Podfile`, etc.). Review the diff
      carefully; commit as a discrete `feat(ios/scaffold)` commit.
- [x] **P1.2 — Set bundle id & signing style:** `PRODUCT_BUNDLE_IDENTIFIER = club.makapix.app` across all
      build configs in `ios/Runner.xcodeproj/project.pbxproj`; set the deployment target (OD3, iOS 13.0);
      configure for **automatic signing with the App Store Connect API key** (no manual profiles checked in).
- [x] **P1.3 — Rust static lib for iOS.** Add `"staticlib"` to `crates/ffi/Cargo.toml` `crate-type`
      (keep `cdylib`/`lib` for the other platforms). Author `build_ios.sh` (macOS-only) that:
      1. `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`
      2. builds `libmakapix_ffi.a` for device + simulator arches (release),
      3. packages them into an **`MakapixFFI.xcframework`** (device slice + a fat simulator slice),
      4. drops it where the Runner links it.
      Link the xcframework into the Runner target and ensure the C symbols (`mkpx_run`, `mkpx_display`, …)
      resolve via `DynamicLibrary.process()`. Add a bridging/`-ObjC`/force-load flag if the linker
      dead-strips the static symbols.
- [x] **P1.4 — `Info.plist`:**
      - Register the OAuth custom scheme under `CFBundleURLTypes` → `CFBundleURLSchemes = ["club.makapix.app"]`.
      - `CFBundleDisplayName = Makapix` (confirm exact store name).
      - Add usage strings only for what we actually touch: **`NSPhotoLibraryAddUsageString`** (if we let
        users save exported PNG/GIF to Photos) and any picker-related keys `file_picker` needs. Keep the
        set minimal — Apple review rejects unused permission strings.
      - `ITSAppUsesNonExemptEncryption = false` (we use only standard HTTPS) to skip export-compliance
        prompts each upload.
- [x] **P1.5 — iOS launcher icons (opaque).** Add an `assets/icons/icon_ios.png` opaque master (flatten
      the brand icon onto the brand background — no alpha), enable `ios: true` in the
      `flutter_launcher_icons` config pointing at it, and regenerate. Verify no transparency (Apple
      rejects icons with an alpha channel / rounded-corner baked in).
- [x] **P1.6 — Plugin/iOS smoke items:** confirm `share_plus` iPad popover source rect is handled;
      confirm `flutter_secure_storage` Keychain accessibility option is acceptable (default
      `first_unlock`); confirm `flutter_web_auth_2` uses `ASWebAuthenticationSession` (default on iOS).
- [x] **P1.7 — `codemagic.yaml` skeleton** at repo root (full version filled in Phase 3): a macOS-instance
      workflow that installs Rust + iOS targets, runs `build_ios.sh`, `flutter build ipa`, signs via the
      App Store Connect API key, and publishes to TestFlight.
- [x] **P1.8 — Auth decision wiring (depends on OD1).** If Sign in with Apple is required, add
      `sign_in_with_apple` plugin + the **Sign In with Apple** capability/entitlement and the server leg;
      if we instead ship email+password and drop GitHub-on-iOS, gate the GitHub button off on iOS.

### Phase 2 — Cloud-Mac bootstrap (Scaleway Mac mini, headless, Claude-driven)

De-risk the **first clean build** and the first **TestFlight → iPhone** install. Kept short to minimize cost.

- [ ] **P2.1 — User provisions a Scaleway Mac mini** (Elastic Metal / Apple silicon, hourly). One-time:
      create the instance, enable **SSH**, and hand Claude the host + private key (store in the session's
      secret store). *Autonomy:* after this, Claude drives everything over SSH via the Bash tool
      (`xcodebuild`, `flutter`, `fastlane`, `git` — all CLI, no GUI/VNC needed).
      - *Alternative if Scaleway capacity/region is a problem:* **AWS EC2 Mac** (`mac2.metal`, dedicated
        host, 24-h min) — same SSH-driven flow, higher floor cost.
- [ ] **P2.2 — Toolchain install on the Mac** (Claude, over SSH): Xcode + command-line tools (or a
      preinstalled Xcode image), Homebrew, Flutter SDK matching `sdk: ^3.12.1`, Rust + iOS targets,
      CocoaPods, fastlane. Place the App Store Connect `.p8` key.
- [ ] **P2.3 — Clone + build** (Claude): clone the repo, run `build_ios.sh`, `flutter pub get`,
      `flutter build ipa --export-options-plist …` (or fastlane `gym`). Fix whatever breaks —
      linker/symbol issues on the static FFI, Pod versions, entitlements — committing fixes back.
- [ ] **P2.4 — Sign & upload to TestFlight** (Claude): fastlane `pilot`/`deliver` or
      `xcrun altool`/`notarytool` via the API key → build appears in App Store Connect → TestFlight.
- [ ] **P2.5 — Install on the iPhone** (user): install **TestFlight** from the App Store, accept the
      internal-tester invite, install the build **over-the-air** (no cable, no Mac). Smoke-test: editor
      draws, engine renders, Club feed loads, GitHub (or Apple/email) sign-in returns cleanly, publish +
      remix work. Log results in Progress.
- [ ] **P2.6 — Decommission the Mac** once CI (Phase 3) reproduces the build green. Snapshot/note anything
      non-obvious (Xcode version, Pod pins) into this doc.

> Note: with the App Store Connect API key, Phase 2 is technically *optional* — Codemagic (Phase 3) can do
> the first build too. We keep the cloud-Mac step per D2 to have an interactive escape hatch the first time
> the static-FFI linking meets the iOS toolchain. If P1 + a Codemagic dry run go green on their own, we may
> collapse Phase 2 into Phase 3 and save the rental entirely.

### Phase 3 — CI migration (Codemagic; the durable pipeline)

- [ ] **P3.1 — Connect Codemagic** to the GitHub repo; add the App Store Connect API key
      (`.p8` + key id + issuer id) and the bundle id as Codemagic integrations/secrets.
- [ ] **P3.2 — Flesh out `codemagic.yaml`:** macOS instance; cache Flutter/Pods/Cargo; steps =
      install Rust targets → `build_ios.sh` (xcframework) → `flutter build ipa` with **automatic code
      signing** via the API key → publish to **TestFlight** (and later App Store). Trigger on tags/manual.
- [ ] **P3.3 — Green CI build → TestFlight**, matching the Phase 2 artifact. Install the CI build on the
      iPhone to confirm parity.
- [ ] **P3.4 — Decommission the cloud Mac** (if still up). Document the versioning rule: bump
      `CFBundleVersion` per upload (App Store Connect rejects duplicates), tracked independently of Play's
      `versionCode`.
- [ ] **P3.5 — (Optional) unify release tooling.** Decide whether to add an `release_ios` path mirroring
      `release_android.ps1`'s ergonomics, or keep iOS release fully in Codemagic. Likely the latter.

### Phase 4 — App Store submission & release

- [ ] **P4.1 — Store metadata:** name, subtitle, description, keywords, support URL, marketing URL,
      **privacy policy URL** (reuse the community-rules / moderation / Terms-of-Service pages already
      linked in-app via `url_launcher`).
- [ ] **P4.2 — App Privacy "nutrition label"** in App Store Connect: declare data collected (account
      identifiers via GitHub/email auth, user content = uploaded artwork, any analytics). Be accurate — a
      mismatch with runtime behavior is a common rejection.
- [ ] **P4.3 — Screenshots** for required device sizes (6.7" and 6.5"/6.1" iPhone; iPad only if we claim
      iPad support). Generate from the simulator or the iPhone.
- [ ] **P4.4 — Age rating & category** (Social Networking or Photo & Video); **UGC compliance**: Apple
      1.2 requires content filtering, reporting/blocking, and a EULA for user-generated content — the app
      already ships the rules gate + moderation/report surfaces (see the ugc-safety work); confirm they're
      reachable on iOS.
- [ ] **P4.5 — Submit for review** from a TestFlight-verified build. Budget **1–3 days** for first review;
      expect at least one round of feedback (Sign in with Apple and UGC are the usual first-timers' snags).
- [ ] **P4.6 — Release** (manual or phased). Then keep iOS + Android release cadence in step.

---

## 3. Provider choice — why Scaleway (autonomous control)

The user's requirement is that **Claude can drive the Mac autonomously after a one-time setup**. That rules
in **SSH-first, CLI-drivable** hosts and rules out GUI/remote-desktop-only rentals:

| Option | Autonomous (SSH/CLI)? | Cost shape | Verdict |
|--------|----------------------|-----------|---------|
| **Scaleway Mac mini** (Apple silicon, elastic metal) | ✅ full root SSH | hourly, low floor (short min commitment) | **Primary.** Cheapest real machine Claude can fully drive headlessly. |
| **AWS EC2 Mac** (`mac2.metal`) | ✅ SSH | 24-h dedicated-host minimum (higher floor) | **Fallback** if Scaleway capacity/region blocks. Robust, pricier. |
| MacinCloud managed / MacStadium desktop | ⚠️ mostly RDP/VNC GUI | monthly/managed | Excluded — Claude can't drive a remote desktop autonomously. |
| Xcode Cloud / Codemagic | ✅ (but non-interactive) | free tiers | These are the **CI** (Phase 3), not the interactive bootstrap. |

The entire iOS pipeline (Rust cross-compile → xcframework → `flutter build ipa` → sign → TestFlight) is
CLI-scriptable, so SSH is sufficient — no VNC. The App Store Connect **API key** means even signing needs
no interactive Apple ID on the box, so the Mac stays fully headless.

---

## 4. Concrete repo changes (checklist for when we execute)

- `app/ios/**` — new, from `flutter create --platforms=ios .` (bundle id, deployment target, Info.plist,
  URL types, Podfile, entitlements).
- `crates/ffi/Cargo.toml` — add `"staticlib"` to `crate-type`.
- `build_ios.sh` — new (macOS) Rust→xcframework builder.
- `codemagic.yaml` — new, root.
- `pubspec.yaml` — enable `flutter_launcher_icons: ios: true` + `assets/icons/icon_ios.png` (opaque).
- (OD1-dependent) `pubspec.yaml` + auth code + `ios/Runner/Runner.entitlements` — Sign in with Apple, **or**
  iOS gating of the GitHub button in favor of email+password.
- `README.md` / `CLAUDE.md` — flip the "iOS is deferred" language once the pipeline is live; add iOS build
  commands next to `build.ps1` / `build_android.ps1`.
- **No changes** to the `engine`/`codec`/`cli` crates' logic — only the `ffi` crate-type and a new build
  script. Engine determinism/goldens are unaffected (same integer-exact code path on Apple targets).

---

## 5. OAuth on iOS (the return-leg detail)

Android uses verified **App Links** (`autoVerify` + hosted `assetlinks.json`) with a custom-scheme
fallback. On iOS:

- **MVP (recommended, zero server work): custom scheme.** Register `club.makapix.app` in
  `CFBundleURLTypes`. `flutter_web_auth_2` opens `ASWebAuthenticationSession`; the server's 302 to
  `club.makapix.app://oauth/github` is captured by the session. This is **already server-allowlisted** and
  works for **both** dev and prod on iOS. `oauthCallbackScheme` on iOS should be the custom scheme.
- **Optional polish: Universal Links.** Add the **Associated Domains** entitlement
  (`applinks:app.makapix.club`, `applinks:app-dev.makapix.club`) and have the **server repo host an
  `apple-app-site-association` (AASA)** file (the iOS analogue of `assetlinks.json`). Only pursue if the
  custom-scheme UX proves janky on the test iPhone (OD2). Note the same prod-topology subtlety flagged in
  `ClubConfig`: prefer the custom scheme on prod unless testing shows Universal Links behave better under
  `ASWebAuthenticationSession` than they did under Android's Chrome Custom Tab.

Track this as **OD2**; default to custom-scheme-only for the first submission.

---

## 6. Risks & mitigations

- **R1 — Apple 4.8 "Sign in with Apple" (RESOLVED / OD1).** Decision (2026-07-06): **implement Sign in
  with Apple** alongside GitHub. Work: enable the capability on the App ID; add `sign_in_with_apple`
  plugin + `Runner.entitlements`; add the server verification leg (Apple identity-token → session).
  Residual risk is only execution, not approval-blocking ambiguity.
- **R2 — Static-FFI linking on iOS (MEDIUM).** `DynamicLibrary.process()` needs the Rust symbols statically
  linked and *not* dead-stripped. Mitigation: xcframework + explicit link flags / a keep-symbols shim;
  this is exactly what the Phase 2 cloud-Mac session de-risks interactively.
- **R3 — UGC review (Apple 1.2) (MEDIUM).** Social apps must have content filtering, report/block, and a
  EULA. Mitigation: the app already ships the rules gate + moderation/report surfaces; verify they're
  reachable and functional on iOS before P4.5.
- **R4 — Version-code collisions (LOW).** App Store Connect rejects a duplicate `CFBundleVersion`.
  Mitigation: track iOS build numbers independently of Play's `versionCode`; auto-increment in Codemagic.
- **R5 — First-review latency (LOW/expected).** Budget 1–3 days and at least one feedback round.
- **R6 — Cost creep on the cloud Mac (LOW).** Mitigation: keep Phase 2 short; decommission as soon as
  Codemagic is green; consider skipping Phase 2 entirely if P1 + a Codemagic dry run pass.

---

## 7. Rough cost estimate

- Apple Developer Program: **$99 / year** (unavoidable).
- Second-hand iPhone: user-provided.
- Scaleway Mac mini bootstrap: **~a few USD** for a 1–2 day headless session (hourly billing); AWS EC2 Mac
  fallback higher (24-h min).
- Codemagic ongoing: **free tier** (macOS minutes) for our cadence; paid only if we exceed it.
- **Likely one-time out-of-pocket beyond the $99: single-digit-to-low-double-digit USD**, or ~$0 extra if we
  skip the cloud Mac and let Codemagic do the first build.

---

## 8. Progress log

_(Append dated entries as phases execute.)_

- 2026-07-06 — Plan written & committed. Implementation on hold per D6 (awaiting Apple enrollment + iPhone).
- 2026-07-06 — Apple Developer Program **paid** ($99); user signed in at developer.apple.com. Enrollment
  in progress. Portal setup steps started (register App ID `club.makapix.app` **with Sign in with Apple
  capability**, create App Store Connect API key, reserve app name / create app record).
- 2026-07-06 — **OD1 resolved: add Sign in with Apple** (keep GitHub). Updated §0, §6-R1, P1.8.
- 2026-07-08 — **Phase 1 repo scaffolding executed** (Flutter 3.44.1, on Windows; compiles only on the Mac).
  Decisions taken this session: Apple sign-in wired **app-side but gated off**; **iOS 12.0** min target;
  home-screen name **"Makapix"**. Commit-ready. Done:
  - **P1.1** `flutter create --platforms=ios .` → `app/ios/` (only `app/.metadata` + `app/pubspec.lock`
    otherwise touched; no Dart/Android source changed).
  - **P1.2** bundle id `club.makapix.app` (+ `.RunnerTests`) across all configs; `IPHONEOS_DEPLOYMENT_TARGET
    = 12.0`; hand-authored `app/ios/Podfile` pinned to `platform :ios, '12.0'`. Signing left **automatic
    with no `DEVELOPMENT_TEAM` hardcoded** (public repo — Codemagic injects the team via the API key).
  - **P1.3** `crates/ffi/Cargo.toml` crate-type now `["cdylib", "staticlib", "lib"]` (verified builds on
    Windows). New root **`build_ios.sh`** (macOS) → `MakapixFFI.xcframework` (device + fat simulator).
    Vendored via new `app/ios/makapix_ffi.podspec` + a `pod 'makapix_ffi', :path => '.'` line; Podfile
    `post_install` adds a `-force_load` so `DynamicLibrary.process()` finds the un-referenced Rust symbols
    (exact path is the R2 item to confirm on the first Mac build). Xcframework is git-ignored.
  - **P1.4** `Info.plist`: `CFBundleURLTypes` scheme `club.makapix.app` (prod GitHub OAuth return leg —
    works with zero server work); `CFBundleDisplayName = Makapix`; `NSPhotoLibraryUsageDescription` (the
    `file_picker` image picker); `ITSAppUsesNonExemptEncryption = false`.
  - **P1.5** `flutter_launcher_icons` iOS enabled with `remove_alpha_ios` + `background_color_ios #000000`;
    regenerated 21 icons; verified the 1024² marketing icon is RGB/opaque (Apple-compliant).
  - **P1.6** reviewed: Podfile platform set; `flutter_secure_storage` → Keychain (default OK);
    `flutter_web_auth_2` → `ASWebAuthenticationSession` (default). **Caveat noted:** `share_plus` needs a
    `sharePositionOrigin` on **iPad** or the share sheet throws; the test device is an iPhone and the share
    API is context-free, so deferred (add before any iPad claim).
  - **P1.7** root **`codemagic.yaml`** skeleton: mac instance → install Rust+iOS targets → `build_ios.sh` →
    `flutter build ipa` (auto-increment `CFBundleVersion` from TestFlight; R4) → API-key signing →
    TestFlight. No secret IDs committed (ASC key = Codemagic integration `makapix_ci`; Apple app id via a
    Codemagic secret var). Has an inline pre-first-build CHECKLIST.
  - **P1.8** Sign in with Apple, **gated off** (`ClubConfig.kAppleSignInEnabled = false`): `sign_in_with_apple`
    ^6.1.0 (resolved 6.1.4) dep; `app/lib/club/auth/apple_oauth.dart` (native flow + SHA-256 nonce);
    `ClubSession.loginApple(...)` (plugin-free `apple_identity_token` grant); `AuthController.loginApple()` +
    `appleOAuthProvider`; Apple's official `SignInWithAppleButton` in `club_account_page.dart` (renders only
    when the flag is on **and** `AppleOAuth.isAvailable()`); `app/ios/Runner/Runner.entitlements`
    (`com.apple.developer.applesignin`) wired into all 3 Runner configs. Server contract fully specified in
    `docs/ios-release/apple-signin-server.md`. **Flip `kAppleSignInEnabled` once the server grant ships.**
  - **Validation:** `flutter analyze` clean; **236 Dart tests green**; `cargo build -p makapix-ffi` OK.
    iOS **compilation** is unvalidated by design (needs the Mac — Phase 2).
  - **iOS OAuth note (→ OD2):** the **prod** GitHub return works as-is on iOS via the custom scheme. The
    **dev** env (`app-dev.makapix.club` HTTPS App Link) would need Associated Domains + AASA on iOS; left
    for later since store builds are prod. Shared `ClubConfig` deliberately untouched (avoids Android/test
    regressions).
