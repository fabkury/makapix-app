# Internationalization (i18n) — design & recommendations

**Status: DEFERRED (2026-07-16).** No i18n work is scheduled. This document captures the
codebase assessment and the agreed-on approach so the work can be picked up later without
re-deriving it. Nothing here is implemented.

**Target languages** (decided): English (template), Spanish, Chinese (Simplified), Japanese,
Russian, Portuguese (pt-BR), German, French. Terms of Service and legal documents remain
English-only by decision.

---

## 1. Current state (assessed 2026-07-16)

There is zero i18n infrastructure:

- No `flutter_localizations`, no `intl` in `app/pubspec.yaml`; no `localizationsDelegates` /
  `supportedLocales` / `locale` on the `MaterialApp` in `app/lib/app.dart` (title is a const
  string, needs `onGenerateTitle` eventually).
- All user-facing text is hardcoded English across ~136 Dart files: ~530 `Text(` sites plus
  tooltips, dialog titles/buttons, SnackBars, hint texts, `semanticsLabel`s.

Patterns that are hostile to translation and must be **restructured, not just wrapped**:

- Hand-rolled English plurals: `'post${count == 1 ? '' : 's'}'`
  (`app/lib/club/ui/post_management_page.dart:219` and `:448`), `'frame'/'frames'` in
  `app/lib/editor/editor_page.timeline.dart:143`.
- Hand-rolled relative time: `timeAgo()` (`app/lib/club/ui/widgets/common.dart:35`) and a
  second `_ago()` in `app/lib/editor/gallery/gallery_page.dart`, composed by string
  concatenation (`'Blocked ${timeAgo(...)}'`, `'Requested ${timeAgo(...)} ago'` in
  `post_management_page.dart:451`). Translators must be able to reorder words — every
  concatenated sentence becomes a single ICU message with placeholders.
- Display strings stored in **const data structures**: `ToolDef.label` in
  `app/lib/editor/tools.dart`. Once locale can change at runtime, these cannot hold fixed
  strings; they must become keys resolved at widget build time.
- Server-provided prose shown verbatim: e.g. `errorMessage` from `app/lib/club/models/pmd.dart`
  rendered at `post_management_page.dart:453`. See §4.2.

## 2. Core mechanism: Flutter first-party gen-l10n (ARB + `intl`)

Use `flutter_localizations` (SDK) + `intl` + ARB files + the built-in `flutter gen-l10n`
generator (`l10n.yaml`, `generate: true` in pubspec). `app_en.arb` is the source-of-truth
template with `@key` descriptions for translators; one ARB per locale; the generator emits a
typed `AppLocalizations` class — compile-time-checked accessors, typed placeholders, full ICU
MessageFormat (plurals, select, date/number formats).

Why this and not a third-party package:

- Matches the repo's philosophy (minimal deps, no third-party codegen, nothing that can break
  cross-platform builds — the same reasoning that picked a hand-written C ABI over
  `flutter_rust_bridge`). `gen-l10n` is part of the `flutter` tool itself.
- **ICU plurals are non-negotiable for this language list.** Russian has three plural
  categories with non-trivial rules; Chinese and Japanese have none. The ternary-`'s'`
  approach cannot be patched around.
- ARB is the lingua franca of translation tooling (Crowdin, Lokalise, Weblate, POEditor all
  ingest it directly).

Considered alternative: `slang` (type-safe nested keys, nice ergonomics) — rejected as a
third-party codegen dependency bought for ergonomic gain only. `easy_localization`
(runtime JSON, weaker type safety) — rejected.

The `flutter-setup-localization` Claude Code skill can scaffold the L0 infrastructure when
work starts.

## 3. Key design decisions

**Locale set.** `en` (template) · `es` · `zh` — ship Simplified, declared as
`Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')`; Traditional is a genuinely
separate locale, deferred · `ja` · `ru` · `pt` — **written in pt-BR** (maintainer's variant
and the dominant market; `pt_PT` can be an override file later) · `de` · `fr`. None are RTL,
so no RTL audit is needed now.

**Locale resolution + user override.** Follow the system locale by default; add a Settings →
Language picker ("System default" + the eight languages shown as endonyms: Español, 中文,
日本語, Русский, Português, Deutsch, Français, English). Persist the override in
`shared_preferences` (already a dep); expose it as a Riverpod `StateProvider` feeding
`MaterialApp.locale`. Locale switching is then a plain rebuild — instant, no restart — which
is exactly why const-stored labels must become lookups. Set `Intl.defaultLocale` on change so
bare `DateFormat`/`NumberFormat` instances follow.

**One ARB file, prefixed keys.** Despite the two pillars, use a single ARB with disciplined
key prefixes (`clubFeedTitle`, `editorToolPencil`, `commonCancel`) rather than splitting into
packages with separate localization classes. Estimated 600–800 messages — manageable; the
prefix discipline keeps a future split cheap.

**Locale-aware formatting replaces the hand-rolled helpers.**

- Rebuild `timeAgo()` on top of generated ICU plural messages (`{n, plural, ...}` per locale).
  `intl` has no relative-time formatter; do **not** add the `timeago` package for this — the
  ICU-message version is ~30 lines and keeps translations in the same ARB pipeline.
- `_fmt(viewCount)`-style compact numbers → `NumberFormat.compact(locale: ...)`.
- Dates → `DateFormat` with locale (or typed `DateTime` placeholders in ARB).

## 4. Boundary rules — what does NOT get translated

1. **The Rust engine stays 100% out of i18n.** No locale ever crosses the FFI. The DSL,
   probes, CLI output, and engine error strings are developer/diagnostic surfaces and stay
   English. Where an engine condition is user-facing (load failure, conformance rejection,
   the memory-budget loader refusal), the **Dart side maps a stable error code/class to a
   localized string at the seam**. Prerequisite work item: where those paths today return
   only prose strings through the FFI, add stable codes to the contract (consistent with the
   "bytes and codes, not presentation" principle of the seam).
2. **Server text needs a contract decision** — cross-repo, since the website client shares
   it. Recommended pattern: the server returns **machine-readable codes + parameters** for
   anything shown prominently (moderation notices, API error `detail`, notification bodies),
   and each client localizes. The alternative (server localizes via `Accept-Language`)
   couples server releases to app copy. Propose via the established `docs/<topic>/messages`
   exchange convention — but do **not** block app i18n on it; server strings remain a
   known-English island until it lands.
3. **User-generated content is never translated** (titles, comments, hashtags, profiles).
4. **ToS/legal stay English** (decided). Same for dev-only surfaces (memlab).
5. **Brand and product terms stay untranslated**: "Makapix Club", "Makapix Editor", `.mkpx`.
   Write a small **terminology glossary** (Contribute, remix, reaction, highlight, …) as a
   translator-facing artifact — cheap, and the difference between coherent and incoherent
   translations across eight languages.

## 5. App-specific risks

- **Text expansion vs. the dense editor UI.** German and Russian run ~30% longer than
  English; the editor's three-row toolbar, dialogs, and timeline are tight. Budget a
  layout-hardening pass (ellipsis + tooltips, `Flexible`, min-width audits); consider
  per-locale overflow/golden tests. This is the biggest hidden cost after extraction itself.
- **CJK rendering on Windows.** Android/iOS fall back to system CJK fonts fine; Windows falls
  back to system fonts (Microsoft YaHei / Yu Gothic) — usually fine but must be explicitly
  smoke-tested. Bundling Noto Sans SC/JP is a large-asset decision to take only if the
  fallback looks bad.
- **Locale-sensitive surfaces beyond `Text(`**: `semanticsLabel`s, `Tooltip`s, file-picker
  dialog titles, and the app title (`onGenerateTitle`, not the const `title:`).

## 6. Phased migration plan (shippable at every step)

- **L0 — infrastructure**: `l10n.yaml`, `app_en.arb`, MaterialApp wiring, locale provider +
  settings picker, `Intl.defaultLocale`, CI gate on gen-l10n's `untranslated-messages-file`
  (runtime falls back to English, so a partial locale never crashes). App still reads
  all-English; migrate one pilot screen to prove the loop.
- **L1 — Club pillar extraction**: the larger, more international-facing surface. Includes
  rebuilding `timeAgo` and all plurals as ICU messages.
- **L2 — Editor pillar extraction**: includes the `ToolDef` restructure and the
  layout-hardening pass.
- **L3 — languages + periphery**: translation procurement per locale, server error-code
  contract, Play/App Store listing localizations (a separate but real part of "offering the
  app in language X").

Ship languages incrementally — English fallback means `es`/`pt` can release first and the
rest follow as they reach acceptable quality; never gate on all eight at once.

## 7. Translation workflow

Realistic indie-scale approach: first pass via MT/LLM against the glossary and the ARB
`@description`s, then native-speaker review prioritized for the highest-visibility strings.
`pt` and `es` are cheapest to validate in-house; `ja`/`zh`/`ru` benefit most from outside
review. Adopt a TMS (Crowdin/Weblate have free tiers) the moment more than one human touches
translations; before that, ARB files in-repo are fine.

**Regression guard**: no off-the-shelf lint flags hardcoded UI strings. Use a lightweight CI
heuristic (grep for string literals inside `Text(`/`SnackBar(` in changed files) or review
discipline to keep extraction from regressing after L1/L2.

## 8. Decisions worth settling before the first ARB file is written

Already settled above, restated as a checklist: key-prefix scheme · `zh-Hans` subtag ·
pt-BR authorship · engine error-code contract at the FFI seam · server codes+params contract
(proposed, not blocking) · terminology glossary · brand terms untranslated.
