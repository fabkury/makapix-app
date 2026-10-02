# Files for the language flip

Ready to move into place in the commit that sets `kTranslationsShipped = true`, and not before:
they tell the system the app has eight languages, and until the flip a release build shows one.

- `android/locales_config.xml` → `app/android/app/src/main/res/xml/locales_config.xml`, plus
  `android:localeConfig="@xml/locales_config"` on `<application>` in `AndroidManifest.xml`.
  It enables Android 13+ per-app language settings; the list must match the ARB languages.
- `ios/<lang>.lproj/InfoPlist.strings` → `app/ios/Runner/<lang>.lproj/`, added to the Runner
  target's resources, plus `CFBundleLocalizations` in `Info.plist` listing `en` and these seven.
  They translate the two permission prompts (photos, camera); English stays in `Info.plist`.
  First real check: the next Codemagic build on TestFlight.

- `whatsnew/whatsnew-<language>` → `distribution/whatsnew/` (replacing the English file): the
  release notes for the translations release, one per Play listing language (es-419 and es-ES
  share the neutral Spanish text). `release_android.ps1` uploads every file in that folder and
  refuses a translation older than the English one. The App Store's "What's New" takes the same
  text per localization (es-MX and es-ES from the Spanish file, ru, ja, zh-Hans from ru-RU,
  ja-JP, zh-CN), entered with the App Store listing. If the release gains other changes before
  it ships, add them to all nine files. Upload the eight Play listings before releasing: Play may refuse
  release notes in a language the listing doesn't have yet.

The InfoPlist strings were reviewed independently on 2026-10-02 (`review/infoplist.md`: no
high or medium findings; the three polish items are applied). The release notes were reviewed
the same day, one native-level pass per language; the findings are applied.
