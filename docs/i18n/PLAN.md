# i18n work plan and live tracker

**Read this first when resuming.** It says where the work stands, what is next, and how to do one
unit of work. The decisions are in [DESIGN.md](DESIGN.md), the test layers in
[TESTING.md](TESTING.md), the terminology in [GLOSSARY.md](GLOSSARY.md).

Started 2026-10-01. Update the status table and the session log at the end of every session.

## Goal

The whole app in eight languages: English, Spanish, Portuguese (pt-BR), French, German, Russian,
Japanese, Simplified Chinese. The language follows the device by default; the user can pick
another in Settings → Language. Nobody tests this by hand: the automated layers in TESTING.md
are the acceptance test.

## Where things stand

| Phase | What | Status |
|---|---|---|
| L0 | Infrastructure, test harness, pilot (Settings, language picker, tool names) | **done 2026-10-01** |
| L1 | Club pillar: extract + translate + sweep, batch by batch | not started |
| L2 | Editor pillar: extract + translate + sweep, batch by batch | not started (tool names done in L0) |
| L3 | Independent translation review (one agent per language), fixes, layout hardening | not started |
| L4 | Seams and periphery, then flip `kTranslationsShipped` | not started |

**Progress number:** the total on line 5 of `app/test/l10n/hardcoded_baseline.txt` — the
hardcoded strings the scanner still finds. 2,670 after L0. Zero means L1 + L2 are done.

**Release safety while this is in progress:** `kTranslationsShipped` is `false`
(`app/lib/l10n/app_locale.dart`), so a release build offers English only and hides the language
row. Releases cut from `main` mid-workstream are unaffected. Debug builds and tests see all eight.
To try a release build with every language: `--dart-define=L10N_PREVIEW=true`.

## One unit of work (a batch)

A batch is a group of related files from the lists below. For each batch:

1. `cd app && dart run tool/l10n/scan.dart --list <file>` — the strings to move.
2. Read the file. For every string decide: **message** (goes to the ARB files), **non-UI**
   (engine DSL name, wire value, log text: add `// l10n-ignore: <why>`), or **server/engine text**
   (stays English for now; add it to the seam list in L4).
3. Write a patch file (Python, see `app/tool/l10n/patch.py`) that edits the source and adds each
   message **in all eight languages** with its description:
   `python tool/l10n/patch.py <patchfile>` then `flutter gen-l10n`.
   Follow GLOSSARY.md for terms and tone. Write the patch file with the Write tool, using raw
   strings (`r'''…'''`); the Bash tool mangles backslashes and apostrophes in heredocs.
4. Add or extend a sweep test for the screens touched (`app/test/l10n/sweep_*_test.dart` for
   Club and shared screens, `app/test_engine/` for anything inside the real editor page).
5. Gates, in this order (never two `flutter` commands at once):
   `flutter analyze --fatal-infos` · `flutter test` · `flutter test test_engine`.
6. `dart run tool/l10n/scan.dart --write-baseline`, tick the batch below, commit
   (`feat(i18n/L1): …` / `feat(i18n/L2): …`). Commits go straight to `main`; no push.

Rules that keep the batches consistent:

- Widgets read strings with `context.l10n.key`. Code with no `BuildContext` (controllers,
  validators, API error mappers) uses `appL10n.key`, at the moment the message is produced.
- Never store a translated string in a `const`, a `static`, or a long-lived field. Data tables
  that held labels (tool catalog, blend modes, patterns, keyboard commands) hold a key or an id,
  and a function maps it to the string at build time — the pattern is `editor/tool_l10n.dart`.
- No sentence is assembled from fragments. Counts use ICU plurals (`{n, plural, …}`); a value
  that changes the wording uses `select`; everything else is one message with placeholders.
- A string that doubles as a state value or an engine name (`'Dots'`, `'Rectangle'`) is split:
  the value stays as it is, the label comes from the ARB.
- Key names are `areaThing` in camelCase with the prefixes in DESIGN.md §3. Reuse a `common*`
  key only when the meaning is identical, not merely the English word.
- Keep English wording unchanged unless it is wrong; existing tests assert on it.

## L1 — Club pillar (≈1,050 findings)

Counts are scanner findings on 2026-10-01; the live number per file is in the baseline.

- [ ] **C1 Shared widgets** — `club/ui/widgets/`: common (4), feed_filter (20), feed_grid (1),
  player_bar (18), comments_section (42), mention_field (4), badges_sheet (3), download_sheet (10),
  mod_hashtags_sheet (20), select_player_overlay (1), external_links (2)
- [ ] **C2 Sign-in and onboarding** — `club/ui/auth/` (create_account 21, account_management 25,
  forgot_password 15, delete_account 14, verify_email 7, onboarding_wizard 18), club_welcome (7),
  club_resolving (5), `club/state/` registration (10), password_reset (6), verify_email (6),
  auth_controller (4), onboarding (2), `club/auth/account_validators` (9)
- [ ] **C3 Home, feeds, search, notifications** — club_home (23), search (15), hashtag_feed (1),
  notifications (20), contribute (8), about_dialog (15)
- [ ] **C4 Profile and account** — profile (52), edit_profile (24), follows (5), reactions (7),
  club_account (28), my_remixes (4), artist_dashboard (21), post_stats (18)
- [ ] **C5 Artwork** — artwork_detail (116), lineage (12)
- [ ] **C6 Publish and manage** — publish (46), edit_post_details (17), post_management (51),
  pending_approval (12), rules_gate (11)
- [ ] **C7 Moderation and safety** — user_management (72), moderation_hub (4), report (17),
  blocked_users (6), monitored_hashtags_page (8), mentions_settings (7), `models/safety_copy` (22),
  `config/monitored_hashtags` (5), `models/report` (3), `edit/mod_hashtag_edit` (4)
- [ ] **C8 Players** — my_players (45), `state/player_providers` (5), `api/player_api` (6),
  `models/player_device` (1)
- [ ] **C9 Errors and context-free text** — `models/club_error` (5), `api/*` (post 13, moderation
  12, profile 5, the rest ≈15), `state/*` (post_providers 8, pmd_providers 7, the rest ≈6),
  `models/` (club_user 6, mention_candidate 5, account 3, mention_markup 4), `share/image_share` (22)

## L2 — Editor pillar (≈1,600 findings, many of them engine names to mark, not translate)

- [x] **E0 Tool names** — short tile label + full name per tool (`tool_l10n.dart`), done in L0
- [ ] **E1 Tool help and row-1 options** — tools.dart tips (≈30), editor_page.controls (258)
- [ ] **E2 Editor chrome** — editor_page.toolgrid (16), .canvas (20), .timeline (64), .sheets (56),
  .dart (59), .engine (78), .layers (5), .frames (4), .keyboard (13)
- [ ] **E3 Files** — editor_page.fileio (103), .persistence (19), open_file (2), gallery (17),
  dialogs: crop (41), place (30), duration (4), rename (4), persistence/drawing_meta (4)
- [ ] **E4 Frames and layers** — frames/ (page 44, more_sheet 44, dialogs 22, action_bar 7,
  layer_name_picker 4, frame_set 4, tile 1, selection 1), layers/ (page 41, more_sheet 61,
  dialogs 27, action_bar 7, select_sheet 4, layer_model 13, row 2)
- [ ] **E5 Color** — palette_page (52), palette_io (7), artwork_colors_page (24),
  color_picker_dialog (6), blend_modes (38), patterns/ (gradient_dither 39, catalog 18, page 14, tile 2)
- [ ] **E6 Keyboard** — keyboard/commands (67; make `CommandDef.label` a per-build lookup —
  the L0 bridge `t.name(appL10n)` in commands.dart is marked TODO), cheat_sheet (18), chords (13)
- [ ] **E7 Replay and timelapse** — editor_page.replay (28), replay/ (page 9, host 4,
  journal_format 5, action_runner 2, timelapse_plan 2, timelapse_export 1), tap_again (1)
- [ ] **E8 Engine-name files** — replay/visible_index (212): DSL verb names only; confirm and
  mark `// l10n-ignore-file`

## L3 — Review and hardening

- [ ] One independent review agent per language (7), each given only the English ARB (with
  descriptions), the glossary, and the translation: back-translate, flag meaning drift, wrong
  register, inconsistent terms, unnatural phrasing, plural errors. It never sees my reasoning.
- [ ] Apply the fixes; second pass on the changed messages only.
- [ ] Glossary conformance check as a tool (`tool/l10n/glossary_check.dart`).
- [ ] Full screenshot gallery (T6) reviewed per language: every sweep screen.
- [ ] Layout hardening for whatever the sweeps flag in German and Russian.
- [ ] Text scale 1.3× sweep on the phone sizes (accessibility font size).

## L4 — Seams, periphery, release

- [ ] **Engine error text at the FFI**: stable codes where `mkpx_run` and the load/import paths
  return English prose that reaches the user; Dart maps code → message. Inventory first.
- [ ] **Server text**: open `messages/0005-localized-text/` proposing codes + params for API error
  `detail`, moderation report-reason labels (`report_reasons[].label`), and any notification text
  the server composes. The app ships without waiting; until the server answers, those stay English.
- [ ] **Default names stored in documents** ("Layer 1", "Untitled"): decide display-time mapping
  vs. localized-at-creation; ADR.
- [ ] **Android**: `res/xml/locales_config.xml` + `android:localeConfig` (per-app language in
  system settings, Android 13+); confirm the app label stays "Makapix Club".
- [ ] **iOS**: `CFBundleLocalizations` in Info.plist; localized `NSPhotoLibraryUsageDescription` /
  `NSCameraUsageDescription` (`InfoPlist.strings`). First real check is the next Codemagic build
  on TestFlight — record the result here.
- [ ] **Windows**: smoke-test CJK and Cyrillic rendering in the real build (system font fallback).
- [ ] **Material's own strings** (date pickers, text-selection menu, back-button tooltip): confirm
  per language in a sweep.
- [ ] Add `flutter gen-l10n` and `flutter test test_engine` to `release_android.ps1` gates.
- [ ] **Live pass**: Windows build and the Pixel over wireless adb — per language, screenshot the
  key screens; confirm device-language pickup and the override surviving a restart.
- [ ] **Store listings**: title, short and full description, release notes for the seven
  languages (Play + App Store), as files under `docs/marketing/`.
- [ ] **Store screenshots** per language through the store-slide pipeline.
- [ ] Flip `kTranslationsShipped` to `true`; update README, STATUS.md, CLAUDE.md; release notes.

## Open questions and risks

- 8.5 px tile labels in Japanese and Chinese: legible in the 2× screenshots, but dense kanji at
  that size on a real phone is the first thing to look at in the live pass.
- Traditional Chinese devices currently get Simplified (no `zh_Hant` translation). Revisit if
  there is demand.
- `use-escaping` is off, so a message cannot contain a literal `{` or `}`.

## Findings outside i18n

- **Editor unmount during startup.** Unmounting `EditorPage` while `_initPersistence` is still
  restoring the drawing threw `Cannot use "ref" after the widget was disposed`
  (`editor_page.persistence.dart`), found by the engine-backed test harness on 2026-10-01. Fixed
  with a `mounted` guard. A narrower race remains: an unmount in the few milliseconds while
  `_createFreshDrawing` / `_loadDrawingIntoEngine` is awaiting can still run engine calls after
  `engine.dispose()`; in the harness that was a native crash. Not fixed (outside this workstream);
  the harness waits for the first drawing to reach disk before it unmounts.

## Session log

- **2026-10-01** — L0. gen-l10n wired (`l10n.yaml`, eight ARB files, `lib/l10n/`), language
  resolution + saved override + picker, pilot extraction (Settings page, tool names with short
  tile labels), test layers T1–T6 built and self-checked, engine-backed editor test suite
  (`app/test_engine/`), scanner + baseline ratchet. 1,252 Dart tests + 8 engine-backed pass.
