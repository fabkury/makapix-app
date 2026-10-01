# i18n: gen-l10n, eight languages, short tile labels, and a test suite that stands in for a human

**Decided 2026-10-01; infrastructure and harness implemented the same day, extraction in
progress** (`docs/i18n/PLAN.md` is the live tracker). Code: `app/l10n.yaml`, `app/lib/l10n/`
(`app_*.arb`, `l10n.dart`, `app_locale.dart`), `app/lib/ui/language_page.dart`,
`app/lib/editor/tool_l10n.dart`, `app/lib/editor/widgets/tool_tile.dart`,
`app/tool/l10n/` (`scan.dart`, `patch.py`), `app/test/l10n/`, `app/test_engine/`.

The app was English-only, with every string hardcoded: about 2,700 literals across 136 files by
the scanner's count. Localization had been designed and parked on 2026-07-16; on 2026-10-01 it
became a first-class feature, with one constraint that shapes everything else: **nobody will
test the translations by hand.**

**The mechanism is Flutter's own gen-l10n** (ARB files, `intl`, the built-in generator), not a
third-party package — the same reasoning as the hand-written C ABI: no external codegen in the
build. Eight languages: English, Spanish, Portuguese (pt-BR), French, German, Russian, Japanese,
Simplified Chinese. The language follows the device (first preferred language the app has,
matched by language code; else English) unless the user picks one in Settings → Language; the
pick is device-local, read before the first frame, and applied live.

**Every tool has two names.** The row-3 tile is 54 px wide with one line of 8.5 px type; "Gradient"
is "Farbverlauf" in German. Each tool carries a full name and a separate short tile label, and
each language words its short label to fit 48 px measured in Roboto (6 px of reserve for wider
platform fonts). A test pumps the real tile in every language and fails on an over-budget label.

**The tests are the acceptance test.** Eight layers (`docs/i18n/TESTING.md`): string-file
integrity, a scanner that finds hardcoded UI text, language resolution, a screen sweep (every
screen × language × five screen sizes: no overflow, no cut-off text, no leftover English), the
tile-fit test, rendered screenshots for visual review, a live pass on Windows and a phone, and an
independent per-language translation review by agents that never see the translator's reasoning.
Two things make the sweep worth trusting: it measures with real fonts (Roboto plus a system CJK
font — the default test font makes every width wrong), and it has a self-check that feeds the
detectors known-bad input.

**The real editor is now testable.** The Dart suite never loads the engine, so the editor page
had no widget test. A second suite, `app/test_engine/`, mounts the real `EditorPage` against the
release engine DLL; it is what lets the editor's own screens be swept per language. The rule
that `app/test/` runs without the engine binary is unchanged.

**Considered and rejected.** *Auto-shrinking tile labels*: uneven sizes, and already-small type
gets smaller. *Two-line tile labels*: costs canvas height in every language, English included.
*Icons only outside English*: new users lose the labels that teach the tools. *Shipping
languages as they finish*: a release build shows English only until the whole app is extracted
(`kTranslationsShipped`), because a half-translated screen is worse than an English one.
*Holding languages for native-speaker review*: no reviewers are lined up; the independent agent
review is the bar, and a translation platform can be adopted later since ARB is its native
format. *The `timeago` package*: relative times are a handful of ICU plural messages.

**Consequences.** New UI text goes through the ARB files in all eight languages; the scanner
gate fails a hardcoded string. Data tables hold ids, not labels. A release needs
`flutter gen-l10n` before `flutter analyze` (generated code is git-ignored and analyze does not
rebuild it). The engine stays out of i18n: user-visible engine errors get stable codes at the FFI
seam, and server prose stays English until the server offers codes — both tracked in the plan.
