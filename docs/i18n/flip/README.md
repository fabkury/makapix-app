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

The InfoPlist strings were reviewed independently on 2026-10-02 (`review/infoplist.md`: no
high or medium findings; the three polish items are applied).
