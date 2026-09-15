# The launch path never waits on the network: cached identity, a resolving surface, and the last pillar

**Decided and implemented 2026-09-15.** Club: the cached identity in `SecureTokenStore`
(`club.me_json`, beside the tokens; `ClubSession.cachedMeJson` / `cacheMe`), the `stale` flag on
`AuthState` and the optimistic branch of `AuthController.init` (`state/auth_controller.dart`),
`ClubResolvingPage` with the shared `NoLoginDrawActions` and `LocalLibraryButton`
(`ui/club_resolving_page.dart`), the offline strip and the wizard gate in `ui/club_home_page.dart`,
the `BrowseLocalLibrary` request (`state/edit_bridge.dart`, consumed in
`editor_page.persistence.dart`). Shell: `LaunchPillarMemory` and `launchPillarProvider`
(`shell/launch_pillar.dart`, `main.dart`, `shell/app_shell.dart`).

The Makapix Editor is promised **fully available offline, no login**. The promise held for the
editor itself, which makes no network call, but not for the path to it: the Club home painted a
full-screen spinner for as long as the sign-in state was `loading`, and that state lasted until
`GET /auth/me` on the stored tokens either answered or timed out. Both screens that carry the
Contribute button — the signed-out welcome and the signed-in home — were built only after that.
On a phone that believes it is online while nothing gets through (an elevator, a dead Wi-Fi with
no upstream, a captive portal), the request cannot fail fast: the TCP handshake gets no reply and
runs to the 15 s connect timeout (which does cover DNS — verified in `dart:io`), a token-less
install adds up to 8 s of Zero-Tap restore, and the app then lands on the welcome page, which
wrongly implies the user was signed out. Fifteen seconds of spinner is a broken promise; the
worse part is that a network gate sat in the launch pillar at all.

**Nothing on the launch path may wait on a request.** Three mechanisms, each cheap on its own:

1. **Cached identity.** The raw JSON of the last successful `/auth/me` is persisted in secure
   storage beside the tokens — it carries the email and the roles, so it lives where they live and
   is cleared with them (one code path: sign-out, a 401 on `/auth/me`, a failed refresh, a
   corrupt store). A cold start with tokens enters the signed-in state **from the cache, at
   once**, flagged `stale`, and `/auth/me` revalidates behind the home. A successful answer
   replaces the state and refreshes the cache; a 401 signs out as before; a failure that never
   reached the server keeps the stale state with the error set, and the home shows a thin strip —
   "Can't reach Makapix Club. Showing your saved sign-in." — with one Retry that refetches the
   feeds and revalidates together. A stale identity unlocks nothing the server would not gate
   anyway, with two deliberate holds: the moderation UI stays hidden until revalidation (a revoked
   moderator must not see the hub offline), and the onboarding wizard waits for the revalidated
   flag (its steps all need the server).
2. **A resolving surface, not a spinner.** What remains of `loading` — the token-store read, the
   Zero-Tap round trip on token-less installs, the no-cache first launch after this change —
   renders `ClubResolvingPage`: the welcome page's "No login needed to draw →" top bar with the
   Contribute button, a small progress indicator, and **My Drawings**. The editor and the local
   library are one tap away from the first frame.
3. **The last pillar, with a time decay.** A cold start mounts the editor if that is where the
   user last was **within the past 24 h**, else the Club. The editor needs no account and no
   network, so a regular drawer who opens the app offline never meets the Club's connecting state
   at all; the decay keeps the Club the landing again after a day away, so the social half never
   quietly disappears. Pillar and an epoch stamp go to shared preferences, stamped on mount, on
   every switch, and on pause/detached (the last reliable moment before an OS kill); the choice is
   read once in `main()` before the first frame — never mid-run — so nothing flashes, bounded at
   2 s and defaulting to the Club on any failure. Back from an editor-first launch still returns
   to the Club.

**My Drawings without an account.** The local drawing library was reachable from the Club side
only through the signed-in profile's Private tab. The welcome page and the resolving page now
carry a My Drawings button that opens the editor straight into its gallery — a new
`BrowseLocalLibrary` request on the existing local-library seam, consumed on the editor's mount
like the Private tab's open/new requests. The Private tab stays as it is.

**Considered and rejected.** *A connectivity plugin*: the OS reported "connected" — that is
precisely the failure — so reachability detection cannot be the mechanism. *A shorter connect
timeout for the boot call only*: moot once nothing waits, and a faltering network would still
have paid it. *An "Open the editor" escape hatch under the spinner*: the cheapest fix, kept only
as the shape of the resolving surface; a spinner as the launch experience was the actual defect.
*Auto-routing to the editor when offline*: the last-pillar memory covers the people it would
have helped, without guessing at reachability. *Editor-first always* and *a Settings choice*:
the app is Club-first by identity; the decayed memory follows habit without a preference to
maintain. *Trusting a cached moderator role*: costs nothing to hold, so it is held.

**What did not change.** The Club's own screens keep their retryable error states; feeds still
fetch on their own, and cached feeds are a separate decision. `AuthStatus.error` without a cache
(tokens present, first launch after this change, server unreachable) still lands on the welcome
page — the cache fills on the first successful `/auth/me`, so the case is one launch per install.
The network timeouts are untouched.
