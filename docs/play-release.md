# Releasing to Google Play

The app is **live in production** on Google Play (since 2026-07-27):
<https://play.google.com/store/apps/details?id=club.makapix.app>. One command cuts a release
end-to-end; the script is track-agnostic and **production is the normal destination** for a
public release:

```powershell
./release_android.ps1 -Track production            # gates → next versionCode from Play → prod AAB →
                                                   #   upload+rollout → commit+tag+push
./release_android.ps1 -Track production -DryRun    # preflight + gates + plan; changes nothing
./release_android.ps1 -Track alpha                 # closed-testing (alpha) release instead
./release_android.ps1 -VersionName 1.1.0 ...       # also bump the user-visible version (default: keep current)
```

The pipeline: verify clean tree on `main` → `cargo test` + `flutter analyze` + `flutter test` →
ask the Play API for the next free `versionCode` → write it to `app/pubspec.yaml` →
`./build_android.ps1 -Bundle` (**prod** is the backend default everywhere; dev requires `-Dev`) →
upload + roll out to the chosen track with notes from `distribution/whatsnew/whatsnew-en-US` →
commit `chore(release)`, tag `v<name>+<code>`, push with tags.

Update `distribution/whatsnew/whatsnew-en-US` before each release (≤500 chars; Play's limit).

Notes on tracks:

- `-Track` defaults to **production** (since 2026-08-10; it was `internal` before). Use
  **`alpha`** when a build is meant for the closed-testing group first, and **`internal`** for an
  instant, review-free smoke-test upload (internal is the only track that skips Google review).
- A build released to alpha can later be copied to production without a re-upload:
  `python tools/play_publish.py promote --from-track alpha --to-track production` (the exact
  same versionCodes roll out on the destination track). This is how the first production release
  (1.0.18+23) went out — except that first one was promoted by hand in the Play Console, because
  the production track's **Countries/regions started empty** (testing-track country selections do
  not carry over) and needed a one-time Console selection (all 177 countries + rest of world).
  That's done; subsequent production rollouts are API-only.

## One-time setup: Play API service account

The upload runs through the Google Play Developer API with a service-account key. Creating it
(once, ~10 minutes):

1. **Play Console → Setup → API access** — link (or create) a Google Cloud project.
2. In that GCP project (console.cloud.google.com):
   - enable the **Google Play Android Developer API**;
   - **IAM & Admin → Service Accounts → Create** (e.g. `play-publisher`), no GCP roles needed;
   - on the account: **Keys → Add key → JSON** — download it.
3. **Play Console → Users and permissions → Invite new users** — invite the service account's
   email address and grant it app-level release permission for Makapix Club. **"Release to
   testing tracks" only covers internal/alpha/beta — production releases need the "Release to
   production" (Release Manager–level) permission.** If a production upload or promote fails
   with a permission error, upgrade the grant here first (unverified whether the current grant
   already includes it — the first production rollout went through the Console UI, not the API).
4. Save the JSON as **`app/android/play-service-account.json`** (git-ignored, like
   `key.properties`).
5. Deps for the publisher script: `pip install google-api-python-client google-auth`.

The publisher itself is `tools/play_publish.py` (`next-code`, `publish`, and `promote`
subcommands); the orchestrator normally calls it, but it can be run by hand for debugging.

## Troubleshooting

- **"Version code N has already been used"** — should not happen: the script asks Play for
  `max(all track releases, all uploaded bundles) + 1` before building. If it still does, check
  **Play Console → Release → App bundle explorer** for codes the API can't see and bump
  `app/pubspec.yaml` past them manually.
- **404 / "The caller does not have permission" right after setup** — the service-account grant
  can take a few minutes to propagate; also confirm the invite was accepted under *Users and
  permissions* and that the API is enabled in the *linked* GCP project. For production
  specifically, see the permission note in step 3 above.
- **Upload succeeded but push failed** — the release is live on Play; the script says so. Push
  manually (`git push origin main --follow-tags`).
- **Signing** — the AAB is signed with the upload key from `app/android/key.properties`
  (Play re-signs for distribution with the app-signing key it holds).
