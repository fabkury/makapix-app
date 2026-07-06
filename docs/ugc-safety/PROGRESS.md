# UGC safety (app) — Progress

Tracks the implementation of `PLAN.md`. Status as of 2026-07-06.

## Code-complete (Dart-only; engine untouched)

All against the frozen contract v1; `flutter analyze` clean, `flutter test`
green (174 total, 27 new in `test/ugc_safety_test.dart`).

- [x] **Config gate** — `ModerationRules` + `ReportReason` on `ClubServerConfig`
  (nullable `moderation`, `moderationEnabled`); empty `report_reasons` ⇒
  feature-off (A18). `models/server_config.dart`.
- [x] **Models** — `Report` + `ReportTarget` (D9 id mapping in one place),
  `BlockedUser`, `UserProfile.isBlockedByViewer` (+ `copyWith`).
- [x] **Errors** — `ClubError.isBlocked` + `kBlockedInteractionMessage`.
- [x] **API** — `SafetyApi` (report/block/unblock/blocks) + `safetyApiProvider`.
- [x] **State** — `safety_providers.dart`: `blockedUsersProvider`
  (`BlockedUsersNotifier` with `remove`), `blockUser`/`unblockUser` helpers.
- [x] **Report page** — `report_page.dart` (full-screen, reasons from config,
  notes, footer links, 201 dialog with "Also block" offer, error mapping).
- [x] **Entry points** — post overflow menu, per-comment action, profile menu
  (all signed-out capable; self/playlist/deleted guards).
- [x] **Blocking UI** — profile block confirm + blocked profile banner +
  Unblock; `blocked_users_page.dart` (scroll load-more + per-row unblock).
- [x] **Settings** — Blocked-users tile + Community section (rules/policy/
  contact via `url_launcher`), both gated on `moderationEnabled`.
- [x] **403 blocked** — mapped at all five sites: detail reaction, grid like,
  comment create/reply, comment like (un-swallowed), follow.
- [x] **Notifications** — `new_report` / `report_resolved` copy + shield
  avatar; `new_report` tap forced inert pending the payload answer.
- [x] **Rules gate** — `rules_gate.dart` (reactive, fail-open, versioned) +
  `rules_gate_page.dart`; inserted in `club_home_page` and `publish_page` (R1).
- [x] **Dependency** — `url_launcher: ^6.3.0` + shared launch/clipboard helper.
- [x] **Copy helpers** — pure `safety_copy.dart` (429 + block-error copy).
- [x] **Tests** — `test/ugc_safety_test.dart` (config gate, models, D9 mapping,
  `isBlocked`, copy helpers, notification parsing, rules-gate logic).
  `shell_test.dart` updated to override `serverConfigProvider` (the Club root
  now reads config to arm the gate).
- [x] **Docs** — `SPEC-CLUB.md` §22 + §29 matrix; `STATUS.md` row.

## Pending (needs the server's dev flip)

- [ ] Manual verification matrix (`PLAN.md` "Manual verification") on
  development.makapix.club — the `moderation` config key must be live.
- [ ] Server team answers (from reply `0002`): playlist report targets;
  `new_report` payload (to enable its tap deep-link).
- [ ] Prod build + joint prod flip; Play Console UGC questionnaire update.

## Notes

- No push work (no FCM/MQTT client — notifications are a polled list).
- No client-side block filtering (server-side per contract §5).
- Rules-gate acceptance persists in `shared_preferences`
  (`club.rules_accepted_version`, `kRulesVersion = 1`).
