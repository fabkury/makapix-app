import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/blocked_user.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/models/club_notification.dart';
import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/page.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/report.dart';
import 'package:makapix_club/club/models/safety_copy.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/models/user_profile.dart';
import 'package:makapix_club/club/state/publish_providers.dart';
import 'package:makapix_club/club/state/rules_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UGC safety (contract v1, frozen 2026-07-06) — client-side pieces: the
/// `moderation` config gate, report/blocked-user models, the D9 target-id
/// mapping, the `403 blocked` accessor, copy helpers, and the reactive
/// rules gate. Pure unit tests — no engine, no network.
void main() {
  Map<String, dynamic> moderationBlock({List<Map<String, String>>? reasons}) => {
        'report_reasons': reasons ??
            [
              {'code': 'spam', 'label': 'Spam or misleading'},
              {'code': 'harassment', 'label': 'Harassment or bullying'},
              {'code': 'future_code', 'label': 'A code the app has never seen'},
            ],
        'contact_email': 'acme@makapix.club',
        'guidelines_url': 'https://makapix.club/about?tab=rules',
        'terms_url': 'https://makapix.club/terms',
        'moderation_policy_url': 'https://makapix.club/about?tab=moderation',
        'max_blocks_per_user': 1000,
      };

  group('Config discovery (moderation block)', () {
    test('present → reasons parsed in order, incl. unknown codes; fields read', () {
      final cfg = ClubServerConfig.fromJson({'moderation': moderationBlock()});
      expect(cfg.moderationEnabled, isTrue);
      final m = cfg.moderation!;
      expect(m.reportReasons.map((r) => r.code), ['spam', 'harassment', 'future_code']);
      expect(m.reportReasons.first.label, 'Spam or misleading');
      expect(m.contactEmail, 'acme@makapix.club');
      expect(m.guidelinesUrl, 'https://makapix.club/about?tab=rules');
      expect(m.termsUrl, 'https://makapix.club/terms');
      expect(m.moderationPolicyUrl, 'https://makapix.club/about?tab=moderation');
      expect(m.maxBlocksPerUser, 1000);
    });

    test('absent key → moderation null, feature off (no default!)', () {
      final cfg = ClubServerConfig.fromJson({'max_hashtags_per_post': 64});
      expect(cfg.moderation, isNull);
      expect(cfg.moderationEnabled, isFalse);
    });

    test('present block with empty report_reasons → feature off (A18)', () {
      final cfg = ClubServerConfig.fromJson({
        'moderation': moderationBlock(reasons: const []),
      });
      expect(cfg.moderation, isNull);
      expect(cfg.moderationEnabled, isFalse);
    });

    test('present block with missing report_reasons → feature off (A18)', () {
      final cfg = ClubServerConfig.fromJson({
        'moderation': {'contact_email': 'x@y.z'},
      });
      expect(cfg.moderationEnabled, isFalse);
    });

    test('offline fallback → feature off', () {
      expect(ClubServerConfig.fallback.moderationEnabled, isFalse);
    });

    test('missing sub-fields → defensive defaults', () {
      final cfg = ClubServerConfig.fromJson({
        'moderation': {
          'report_reasons': [
            {'code': 'spam', 'label': 'Spam'}
          ],
        },
      });
      final m = cfg.moderation!;
      expect(m.contactEmail, 'acme@makapix.club');
      expect(m.maxBlocksPerUser, 1000);
      expect(m.guidelinesUrl, '');
      expect(m.termsUrl, ''); // server msg 0006: absent terms_url → empty, gate falls back
    });
  });

  group('Report / BlockedUser models', () {
    test('Report.fromJson (201 body from the contract)', () {
      final r = Report.fromJson({
        'id': 'r-uuid',
        'target_type': 'post',
        'target_id': '1234',
        'reason_code': 'harassment',
        'notes': null,
        'status': 'open',
        'action_taken': null,
        'created_at': '2026-07-06T12:00:00Z',
        'updated_at': null,
      });
      expect(r.id, 'r-uuid');
      expect(r.targetType, 'post');
      expect(r.targetId, '1234');
      expect(r.reasonCode, 'harassment');
      expect(r.status, 'open');
      expect(r.createdAt, isNotNull);
    });

    test('BlockedUser + Page<BlockedUser> paging shape', () {
      final page = Page<BlockedUser>.fromJson({
        'items': [
          {
            'public_sqid': 'x9k2',
            'handle': 'someuser',
            'avatar_url': null,
            'blocked_at': '2026-07-06T12:00:00Z',
          }
        ],
        'next_cursor': null,
      }, BlockedUser.fromJson);
      expect(page.items, hasLength(1));
      expect(page.items.first.publicSqid, 'x9k2');
      expect(page.items.first.handle, 'someuser');
      expect(page.atEnd, isTrue);
    });

    test('UserProfile.isBlockedByViewer present / absent(→false) / copyWith', () {
      UserProfile parse(Object? v) => UserProfile.fromJson({
            'user_key': 'u',
            'public_sqid': 's',
            'handle': 'h',
            'is_blocked_by_viewer': ?v,
          });
      expect(parse(true).isBlockedByViewer, isTrue);
      expect(parse(false).isBlockedByViewer, isFalse);
      expect(parse(null).isBlockedByViewer, isFalse); // absent field
      // copyWith retains the field (optimistic toggleFollow relies on it).
      final blocked = parse(true);
      expect(blocked.copyWith(isFollowing: false).isBlockedByViewer, isTrue);
    });
  });

  group('ReportTarget (D9 id mapping)', () {
    Post post() => Post.fromJson({
          'id': 1234,
          'public_sqid': 'psq',
          'title': 'My art',
          'owner': {'user_key': 'ok', 'public_sqid': 'osq', 'handle': 'artist'},
        });

    test('post → decimal integer id as string; offender is the owner', () {
      final t = ReportTarget.post(post());
      expect(t.type, 'post');
      expect(t.id, '1234');
      expect(t.offenderSqid, 'osq');
      expect(t.offenderHandle, 'artist');
      expect(t.label, contains('My art'));
    });

    test('comment → UUID; offender handle from flat author fields', () {
      final c = Comment.fromJson({
        'id': '7d9f-uuid',
        'body': 'hi',
        'author_handle': 'bob',
      });
      final t = ReportTarget.comment(c);
      expect(t.type, 'comment');
      expect(t.id, '7d9f-uuid');
      // Server comment payloads carry no author sqid, so block-by-sqid is
      // unavailable from a comment report until the server adds one.
      expect(t.offenderSqid, isNull);
      expect(t.offenderHandle, 'bob');
      expect(t.label, contains('@bob'));
    });

    test('anonymous comment → no offender (nothing to block), "guest" label', () {
      final c = Comment.fromJson({'id': 'c1', 'body': 'x'}); // no author
      final t = ReportTarget.comment(c);
      expect(t.offenderSqid, isNull);
      expect(t.label, contains('guest'));
    });

    test('user → public_sqid', () {
      final u = UserProfile.fromJson({'user_key': 'u', 'public_sqid': 't5', 'handle': 'carol'});
      final t = ReportTarget.user(u);
      expect(t.type, 'user');
      expect(t.id, 't5');
      expect(t.offenderSqid, 't5');
      expect(t.label, '@carol');
    });
  });

  group('ClubError.isBlocked', () {
    test('403 + blocked → true', () {
      expect(ClubError(status: 403, code: 'blocked', message: 'x').isBlocked, isTrue);
    });
    test('403 + other code → false', () {
      expect(ClubError(status: 403, code: 'forbidden', message: 'x').isBlocked, isFalse);
    });
    test('401 → false', () {
      expect(ClubError(status: 401, code: 'blocked', message: 'x').isBlocked, isFalse);
    });
  });

  group('Safety copy helpers', () {
    test('429 report copy interpolates the contact email', () {
      final msg = reportRateLimitMessage('acme@makapix.club');
      expect(msg, contains('acme@makapix.club'));
      expect(msg, contains('too fast'));
    });

    test('block cap copy interpolates maxBlocksPerUser', () {
      final e = ClubError(status: 409, code: 'block_cap_reached', message: 'x');
      expect(blockErrorMessage(e, maxBlocksPerUser: 1000), contains('1000'));
    });

    test('404 → "User not found."', () {
      final e = ClubError(status: 404, code: 'not_found', message: 'x');
      expect(blockErrorMessage(e, maxBlocksPerUser: 1000), 'User not found.');
    });

    test('blocked-interaction constant is direction-neutral (no handle)', () {
      expect(kBlockedInteractionMessage, isNot(contains('@')));
      expect(kBlockedInteractionMessage.toLowerCase(), contains("can't interact"));
    });
  });

  group('Notification data (new types parse; unknown preserved)', () {
    ClubNotification n(String type) =>
        ClubNotification.fromJson({'id': '1', 'notification_type': type});
    test('new_report / report_resolved types parse through', () {
      expect(n('new_report').type, 'new_report');
      expect(n('report_resolved').type, 'report_resolved');
    });
    test('an unknown type is preserved (drives the generic fallback)', () {
      expect(n('something_new').type, 'something_new');
    });
  });

  group('Rules gate (reactive, fail-open)', () {
    ClubServerConfig withModeration() =>
        ClubServerConfig.fromJson({'moderation': moderationBlock()});
    ClubServerConfig without() => ClubServerConfig.fromJson({});

    Future<RulesGate> gateFor({
      int? storedVersion,
      ClubServerConfig? config,
      bool configLoads = true,
    }) async {
      SharedPreferences.setMockInitialValues(
          storedVersion == null ? {} : {kRulesPrefKey: storedVersion});
      final container = ProviderContainer(overrides: [
        serverConfigProvider.overrideWith((ref) async {
          if (!configLoads) await Completer<ClubServerConfig>().future; // never resolves
          return config ?? ClubServerConfig.fallback;
        }),
      ]);
      addTearDown(container.dispose);
      container.listen(rulesGateProvider, (_, _) {}, fireImmediately: true);
      await pumpEventQueue();
      return container.read(rulesGateProvider);
    }

    test('unaccepted + config with moderation → show', () async {
      expect(await gateFor(storedVersion: null, config: withModeration()), RulesGate.show);
    });

    test('unaccepted + config without moderation → passed (fail-open)', () async {
      expect(await gateFor(storedVersion: null, config: without()), RulesGate.passed);
    });

    test('unaccepted + config still loading → passed (never blocks startup)', () async {
      expect(await gateFor(storedVersion: null, configLoads: false), RulesGate.passed);
    });

    test('accepted current version → passed', () async {
      expect(await gateFor(storedVersion: kRulesVersion, config: withModeration()), RulesGate.passed);
    });

    test('stored version older than current → show again', () async {
      expect(await gateFor(storedVersion: 0, config: withModeration()), RulesGate.show);
    });

    test('accepted the previous version → re-prompted once after a bump (Terms adoption)', () async {
      expect(await gateFor(storedVersion: kRulesVersion - 1, config: withModeration()), RulesGate.show);
    });
  });
}
