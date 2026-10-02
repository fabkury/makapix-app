# Internationalization (i18n) — design

**Status: in progress since 2026-10-01** (parked 2026-07-16 to 2026-10-01). The infrastructure
and the test harness are built; the string extraction is under way. Live state and next steps:
[PLAN.md](PLAN.md). How it is tested: [TESTING.md](TESTING.md). Terminology and tone:
[GLOSSARY.md](GLOSSARY.md). The decision record is ADR 0037.

## 1. What the user gets

The whole app in eight languages — English, Spanish, Portuguese (written as pt-BR), French,
German, Russian, Japanese, Simplified Chinese. None is right-to-left.

- **Default:** the device's language. The first of the device's preferred languages that the
  app is translated into wins, matched by language alone (pt-PT gets Portuguese, es-MX Spanish,
  any Chinese gets Simplified); otherwise English.
- **Override:** Settings → Language (Club settings, signed in or out; the editor's ☰ menu). The
  picker lists each language under its own name, so it is usable from a language the user cannot
  read. The pick is device-local, survives restarts, and applies at once with no restart.
  "System default" returns to following the device.

## 2. Mechanism

Flutter's first-party gen-l10n: `flutter_localizations` + `intl`, one ARB file per language in
`app/lib/l10n/`, `app_en.arb` as the template. The generator (`app/l10n.yaml`) emits a typed
`AppLocalizations` class into the same folder; the generated Dart is git-ignored and rebuilt by
`flutter pub get`, `flutter build`, `flutter run`, or `flutter gen-l10n`. `flutter test` and
`flutter analyze` do **not** rebuild it — run `flutter gen-l10n` after editing an ARB (a test
fails on stale output).

Chosen over `slang` and `easy_localization` for the reasons the repo chose a hand-written C ABI
over `flutter_rust_bridge`: no third-party codegen, nothing that can break a platform build. ICU
MessageFormat is required by the language list (Russian has four plural categories, Japanese and
Chinese one), and ARB is what every translation tool reads.

`l10n.yaml` settings that matter:

- `nullable-getter: false`, and every message needs an `@description`
  (`required-resource-attributes`): the description is the translator's only context.
- `use-escaping: false`: apostrophes are literal (English and French are full of them). The
  price is that a message cannot contain a literal `{` or `}`.

## 3. How code reaches a string

| Where | How |
|---|---|
| A widget | `context.l10n.key` (`lib/l10n/l10n.dart`). Rebuilds when the language changes. Falls back to English in a tree with no delegate (bare `MaterialApp`s in tests). |
| Code with no `BuildContext` — controllers, validators, API error mappers | `appL10n.key`, read when the message is produced. `L10nBinding`, mounted under the app's `Localizations`, keeps it and `Intl.defaultLocale` on the current language. |
| Data tables that used to hold labels — tool catalog, blend modes, patterns, keyboard commands | The table holds an id; a function maps id → string at build time. Model: `lib/editor/tool_l10n.dart`. |

A translated string is never stored in a `const`, a `static`, or a long-lived field.

**Keys** are one flat ARB with prefixes: `common*`, `language*`, `settings*`, `tool*`, then one
prefix per screen or area (`publish*`, `layers*`, …). A `common*` key is reused only when the
meaning is the same, not merely the English word.

**Language state** (`lib/l10n/app_locale.dart`): `kAppLanguages` (locale + endonym),
`resolveAppLocale`, `AppLocalePrefs` (shared preferences key `app.locale_v1`), and
`appLocaleProvider`. `main()` reads the saved pick before the first frame, bounded at 2 s, so
the app never opens in one language and flips to another. `MakapixApp` feeds the provider into
`MaterialApp.locale`.

**`zh` is Simplified Chinese**, declared as plain `Locale('zh')` (the generator requires a base
`app_zh.arb` in any case). Traditional would be added as `app_zh_Hant.arb`.

**Release switch:** `kTranslationsShipped`. While the extraction was in progress a release build
offered English only; it was flipped to `true` at L4 (2026-10-02, release 1.12.0). Debug builds
and tests always see every language; `--dart-define=L10N_PREVIEW=true` forces them on in a
release build.

## 4. What is not translated

1. **The Rust engine.** No locale crosses the FFI. The DSL, probes, CLI output, and engine error
   strings stay English. Where an engine condition reaches the user (a load failure, a
   conformance rejection, the memory-budget refusal), Dart maps a stable code to a message at
   the seam; where the engine returns only prose today, the seam gets a code first (PLAN.md L4).
2. **Server text.** Anything the server sends as prose — API error `detail`, the moderation
   report-reason labels, composed notification text — stays English until the server offers
   codes and parameters the app can translate. Proposal thread: `messages/0005-localized-text/`
   (PLAN.md L4). App i18n does not wait for it.
3. **User-written content**: titles, comments, handles, hashtags, profile text.
4. **Legal**: Terms of Service and policy pages. Developer surfaces (memlab).
5. **Brand and technical tokens** — the list is in GLOSSARY.md.

## 5. The tight spots

- **Row-3 tool tiles.** 54 px wide, one line of 8.5 px type. Every tool has two messages: a
  full name (lists, tooltips) and a `…Short` tile label, which each language words to fit a
  48 px budget measured in Roboto — the 6 px under the tile width is reserve for wider platform
  fonts. A test pumps the real tile widget in every language and fails on an over-budget label.
  A label that does not fit gets a shorter word, never a smaller font.
- **Row-1 tool options** and other option names that double as state values (`'Dots'`,
  `'Rectangle'`): the value stays, the label comes from the ARB.
- **Text expansion.** German and Russian run about 30% longer than English. The screen sweeps
  fail on any cut-off or overflowing text on five screen sizes; the fix is in the layout
  (`Flexible`, wrapping, a shorter wording), per finding.
- **Plurals and assembled sentences.** Every `count == 1 ? '' : 's'` and every concatenated
  sentence becomes one ICU message. `timeAgo()` is rebuilt on ICU plurals; `intl` has no
  relative-time formatter and the `timeago` package is not worth a dependency for it.
- **Numbers and dates** go through `NumberFormat` / `DateFormat` with the current locale.
- **CJK rendering.** Android and iOS fall back to system CJK fonts. Windows falls back to
  Microsoft YaHei / Yu Gothic — to be confirmed in the live pass. No font is bundled.
- **Platform declarations.** Android `locales_config.xml` (per-app language in system settings),
  iOS `CFBundleLocalizations` and localized permission prompts. Added when the switch flips.

## 6. Phases

L0 infrastructure and harness · L1 Club extraction · L2 editor extraction · L3 independent
translation review and layout hardening · L4 seams, platform declarations, store listings, live
pass, flip the switch. Each batch of L1/L2 lands translated in all eight languages with its
sweep test, so every commit is complete across languages. Detail and checklists: PLAN.md.

## 7. Translation workflow

Written by Claude against GLOSSARY.md and the ARB descriptions, batch by batch. In L3 one
independent review agent per language — given only the English template, the glossary, and the
translation — back-translates and critiques; fixes are applied and the changed messages
re-reviewed. No human native review is planned; adopt a translation platform (Crowdin, Weblate)
if human translators ever join — both read ARB directly.
