# Moderator hashtags (app) — Progress

## 2026-07-05 — implementation complete, manual verification pending

Server went live on development.makapix.club (message `0002-server-…`),
contract v1 unchanged. Implemented per PLAN.md:

- [x] `Post.modHashtags` + `isModTag` (`models/post.dart`)
- [x] `ClubServerConfig.maxModHashtagsPerPost` (nullable) + `modHashtagsEnabled`
      (`models/server_config.dart`)
- [x] `ModerationApi.setModHashtags` (`api/moderation_api.dart`) +
      `moderationApiProvider` (`state/api_providers.dart`)
- [x] `normalizeHashtags` + `ModHashtagEdit` controller
      (`edit/mod_hashtag_edit.dart`) — guarded add/toggle, set-based `changed`,
      `removedMonitored`
- [x] Detail page (`ui/artwork_detail_page.dart`): shield marker + Semantics +
      tooltip on mod tags for artist/mods, persistent "Tagged by a moderator"
      legend, merged `_overflowMenu` (mkpx entries + "Edit mod hashtags…")
- [x] Editor sheet (`ui/widgets/mod_hashtags_sheet.dart`): Quick add
      (monitored FilterChips) · On this post (InputChips, shield on monitored)
      · add field (Enter/comma, `n/$cap` counter, inline rejections) · optional
      audit note · confirm-on-monitored-removal · error table per plan §6
- [x] Notification (`ui/notifications_page.dart`): `mod_hashtags_updated` case
      (diff from `comment_preview`) + impersonal shield avatar
- [x] Unit tests: `app/test/mod_hashtags_test.dart` (parsing, config gate,
      normalization, controller rules, notification) — full suite 131/131,
      `flutter analyze` clean
- [x] Docs: STATUS.md row, SPEC-CLUB.md §29 parity row
- [ ] Reply `0003-app-…` committed to server repo `develop`
- [ ] **Manual verification matrix (PLAN.md) against development.makapix.club**
      — needs a `-Dev` build + a moderator account + a second regular account;
      owner-driven
- [ ] Prod flip coordination (config key on makapix.club is the launch signal)
      + Play release
