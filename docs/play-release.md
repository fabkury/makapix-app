# Releasing to Google Play (internal testing)

One command cuts a release end-to-end:

```powershell
./release_android.ps1              # gates → next versionCode from Play → prod AAB → upload → commit+tag+push
./release_android.ps1 -DryRun      # preflight + gates + plan; changes nothing
./release_android.ps1 -VersionName 1.1.0   # also bump the user-visible version (default: keep current)
```

The pipeline: verify clean tree on `main` → `cargo test` + `flutter analyze` + `flutter test` →
ask the Play API for the next free `versionCode` → write it to `app/pubspec.yaml` →
`./build_android.ps1 -Bundle` (**prod** is the backend default everywhere; dev requires `-Dev`) →
upload + roll out to the **internal** track with notes from `distribution/whatsnew/whatsnew-en-US` →
commit `chore(release)`, tag `v<name>+<code>`, push with tags.

Update `distribution/whatsnew/whatsnew-en-US` before each release (≤500 chars; Play's limit).

## One-time setup: Play API service account

The upload runs through the Google Play Developer API with a service-account key. Creating it
(once, ~10 minutes):

1. **Play Console → Setup → API access** — link (or create) a Google Cloud project.
2. In that GCP project (console.cloud.google.com):
   - enable the **Google Play Android Developer API**;
   - **IAM & Admin → Service Accounts → Create** (e.g. `play-publisher`), no GCP roles needed;
   - on the account: **Keys → Add key → JSON** — download it.
3. **Play Console → Users and permissions → Invite new users** — invite the service account's
   email address and grant it app-level permission **"Release to testing tracks"** for Makapix Club
   (that's sufficient for internal testing; full Release Manager is not needed).
4. Save the JSON as **`app/android/play-service-account.json`** (git-ignored, like
   `key.properties`).
5. Deps for the publisher script: `pip install google-api-python-client google-auth`.

The publisher itself is `tools/play_publish.py` (`next-code` and `publish` subcommands); the
orchestrator normally calls it, but it can be run by hand for debugging.

## Troubleshooting

- **"Version code N has already been used"** — should not happen: the script asks Play for
  `max(all track releases, all uploaded bundles) + 1` before building. If it still does, check
  **Play Console → Release → App bundle explorer** for codes the API can't see and bump
  `app/pubspec.yaml` past them manually.
- **404 / "The caller does not have permission" right after setup** — the service-account grant
  can take a few minutes to propagate; also confirm the invite was accepted under *Users and
  permissions* and that the API is enabled in the *linked* GCP project.
- **Upload succeeded but push failed** — the release is live on Play; the script says so. Push
  manually (`git push origin main --follow-tags`).
- **Signing** — the AAB is signed with the upload key from `app/android/key.properties`
  (Play re-signs for distribution with the app-signing key it holds).
