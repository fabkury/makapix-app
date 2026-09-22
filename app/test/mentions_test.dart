// Mentions — everything above the grammar: token detection in the composer,
// the composer's pick bookkeeping, the span builder, the models, and the
// `/config` launch gate.
//
// The `<@SQID>` grammar itself lives in `mention_markup_test.dart`, driven by
// the vector table frozen in `messages/0004-mentions/`.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_user.dart';
import 'package:makapix_club/club/models/comment.dart';
import 'package:makapix_club/club/models/mention_candidate.dart';
import 'package:makapix_club/club/models/mention_markup.dart';
import 'package:makapix_club/club/models/post.dart';
import 'package:makapix_club/club/models/server_config.dart';
import 'package:makapix_club/club/ui/widgets/mention_field.dart';
import 'package:makapix_club/club/ui/widgets/mention_text.dart';

void main() {
  group('findMentionToken — what opens the candidates list', () {
    test('a bare @ at the end of the text opens an empty query', () {
      final t = findMentionToken('hey @', 5);
      expect(t, const MentionToken(start: 4, end: 5, query: ''));
    });

    test('typing into the token narrows the query', () {
      final t = findMentionToken('hey @fa', 7);
      expect(t?.query, 'fa');
      expect(t?.start, 4);
      expect(t?.end, 7);
    });

    test('the token may open the text', () {
      expect(findMentionToken('@fab', 4)?.query, 'fab');
    });

    test('an @ inside a word is not a token', () {
      expect(findMentionToken('mail me at a@fab', 16), isNull);
    });

    test('an email address never opens the list', () {
      expect(findMentionToken('write to me@example.com', 23), isNull);
    });

    test('the caret must be in the token', () {
      // Caret before the @.
      expect(findMentionToken('hey @fab', 3), isNull);
      // Caret after a space that ended the token.
      expect(findMentionToken('hey @fab ', 9), isNull);
    });

    test('the caret mid-token still matches, and the token runs to its end', () {
      final t = findMentionToken('hey @fabkury!', 7);
      expect(t?.query, 'fabkury');
      expect(t?.end, 12);
    });

    test('a run longer than a handle stops matching', () {
      final long = '@${'a' * 40}';
      expect(findMentionToken(long, long.length), isNull);
    });

    test('a handle with a dash or underscore stays one token', () {
      expect(findMentionToken('@pixel_art-99', 13)?.query, 'pixel_art-99');
    });

    test('non-ASCII handles are tokens too', () {
      expect(findMentionToken('привет @мика', 12)?.query, 'мика');
    });

    test('an out-of-range caret is refused rather than thrown', () {
      expect(findMentionToken('hey', 99), isNull);
      expect(findMentionToken('hey', -1), isNull);
    });
  });

  group('MentionComposer', () {
    test('serializes only what was picked', () {
      final c = MentionComposer(initialText: 'hi @fab and @nobody');
      c.add(const PickedMention(handle: 'fab', sqid: 't5'));
      expect(c.serialized(), 'hi <@t5> and @nobody');
      c.dispose();
    });

    test('a pick the user edited away is dropped on send', () {
      final c = MentionComposer(initialText: 'hi @fab');
      c.add(const PickedMention(handle: 'fab', sqid: 't5'));
      c.text.text = 'hi @fabulous';
      expect(c.serialized(), 'hi @fabulous');
      c.dispose();
    });

    test('liveCount counts what would actually be sent', () {
      final c = MentionComposer(initialText: '@fab @mika');
      c.add(const PickedMention(handle: 'fab', sqid: 't5'));
      expect(c.liveCount(), 1);
      c.add(const PickedMention(handle: 'mika', sqid: 'Qx'));
      expect(c.liveCount(), 2);
      c.dispose();
    });

    test('seedFromMarkup fills the field with plain text and keeps the picks', () {
      final c = MentionComposer();
      c.seedFromMarkup('thanks <@t5>!', const [
        MentionRef(sqid: 't5', handle: 'fab'),
      ]);
      expect(c.text.text, 'thanks @fab!');
      expect(c.picked, const [PickedMention(handle: 'fab', sqid: 't5')]);
      c.dispose();
    });

    test('an edit that leaves the handle alone round-trips the mention', () {
      // This is the regression the dual field would otherwise cause: an edit
      // from a client that does not know the markup strips the mentions.
      final c = MentionComposer();
      c.seedFromMarkup('thanks <@t5>!', const [
        MentionRef(sqid: 't5', handle: 'fab'),
      ]);
      c.text.text = 'thanks @fab! great work';
      expect(c.serialized(), 'thanks <@t5>! great work');
      c.dispose();
    });

    test('an edit that removes the handle drops the mention, as it should', () {
      final c = MentionComposer();
      c.seedFromMarkup('thanks <@t5>!', const [
        MentionRef(sqid: 't5', handle: 'fab'),
      ]);
      c.text.text = 'thanks!';
      expect(c.serialized(), 'thanks!');
      c.dispose();
    });

    test('seeding null clears both the text and the picks', () {
      final c = MentionComposer(initialText: 'old');
      c.add(const PickedMention(handle: 'fab', sqid: 't5'));
      c.seedFromMarkup(null, const []);
      expect(c.picked, isEmpty);
      c.dispose();
    });
  });

  group('MentionText', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders plain text when there is no markup', (tester) async {
      await tester.pumpWidget(host(const MentionText(
        markup: null,
        plain: 'no mentions here',
      )));
      expect(find.text('no mentions here'), findsOneWidget);
      // A plain Text, not a span tree: the old path is untouched.
      final w = tester.widget<Text>(find.byType(Text));
      expect(w.data, 'no mentions here');
      expect(w.textSpan, isNull);
    });

    testWidgets('renders the handle, never the sqid', (tester) async {
      await tester.pumpWidget(host(const MentionText(
        markup: 'hi <@t5>!',
        plain: 'hi @fab!',
        mentions: [MentionRef(sqid: 't5', handle: 'fab')],
      )));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan!.toPlainText(), 'hi @fab!');
      expect(text.textSpan!.toPlainText(), isNot(contains('t5')));
    });

    testWidgets('a mention is tappable and reports the sqid', (tester) async {
      MentionedSegment? tapped;
      await tester.pumpWidget(host(MentionText(
        markup: 'hi <@t5>!',
        plain: 'hi @fab!',
        mentions: const [MentionRef(sqid: 't5', handle: 'fab')],
        onTapMention: (m) => tapped = m,
      )));

      final text = tester.widget<Text>(find.byType(Text));
      TapGestureRecognizer? recognizer;
      text.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          recognizer = span.recognizer as TapGestureRecognizer;
        }
        return true;
      });
      expect(recognizer, isNotNull, reason: 'the mention span carries a tap');
      recognizer!.onTap!();
      expect(tapped?.sqid, 't5');
      expect(tapped?.handle, 'fab');
    });

    testWidgets('an unresolved sqid renders as inert placeholder text', (tester) async {
      await tester.pumpWidget(host(const MentionText(
        markup: 'bye <@ZZZZ>',
        plain: 'bye @user',
        mentions: [],
      )));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan?.toPlainText() ?? text.data, 'bye @user');
    });

    testWidgets('rebuilding with new text does not throw on disposed recognizers',
        (tester) async {
      await tester.pumpWidget(host(const MentionText(
        markup: 'one <@t5>',
        plain: 'one @fab',
        mentions: [MentionRef(sqid: 't5', handle: 'fab')],
      )));
      await tester.pumpWidget(host(const MentionText(
        markup: 'two <@Qx>',
        plain: 'two @mika',
        mentions: [MentionRef(sqid: 'Qx', handle: 'mika')],
      )));
      await tester.pumpWidget(host(const SizedBox()));
      expect(tester.takeException(), isNull);
    });
  });

  group('models', () {
    test('Comment carries the markup and the resolved mentions', () {
      final c = Comment.fromJson({
        'id': '9',
        'body': 'hi @fab!',
        'body_markup': 'hi <@t5>!',
        'mentions': [
          {'public_sqid': 't5', 'handle': 'fab', 'avatar_url': 'https://a/1.png'}
        ],
        'author_handle': 'mika',
      });
      expect(c.body, 'hi @fab!');
      expect(c.bodyMarkup, 'hi <@t5>!');
      expect(c.mentions.single.handle, 'fab');
    });

    test('a comment from a server without mentions still parses', () {
      final c = Comment.fromJson({'id': '9', 'body': 'plain'});
      expect(c.bodyMarkup, isNull);
      expect(c.mentions, isEmpty);
    });

    test('markDeleted and withReplies carry the markup through', () {
      final c = Comment.fromJson({
        'id': '9',
        'body': 'hi @fab',
        'body_markup': 'hi <@t5>',
        'mentions': [
          {'public_sqid': 't5', 'handle': 'fab'}
        ],
      });
      expect(c.markDeleted().bodyMarkup, 'hi <@t5>');
      expect(c.withReplies(const []).mentions.single.sqid, 't5');
    });

    test('Post carries description markup', () {
      final p = Post.fromJson({
        'id': 1,
        'public_sqid': 'eDfc',
        'title': 't',
        'description': 'by @fab',
        'description_markup': 'by <@t5>',
        'mentions': [
          {'public_sqid': 't5', 'handle': 'fab'}
        ],
      });
      expect(p.descriptionMarkup, 'by <@t5>');
      expect(p.mentions.single.handle, 'fab');
    });

    test('MentionCandidate parses, and an unknown tier does not crash', () {
      final c = MentionCandidate.fromJson(
          {'handle': 'fab', 'public_sqid': 't5', 'reason': 'owner'});
      expect(c.reason, MentionReason.owner);
      expect(c.reason.label, 'Artist');
      final odd = MentionCandidate.fromJson(
          {'handle': 'x', 'public_sqid': 'y', 'reason': 'future_tier'});
      expect(odd.reason, MentionReason.unknown);
      expect(odd.reason.label, '');
    });

    test('MentionPolicy round-trips the wire values', () {
      for (final p in MentionPolicy.values) {
        expect(MentionPolicy.fromWire(p.wire), p);
      }
    });

    test('an absent or unknown policy reads as everyone', () {
      expect(MentionPolicy.fromWire(null), MentionPolicy.everyone);
      expect(MentionPolicy.fromWire('whatever'), MentionPolicy.everyone);
    });

    test('the policy descriptions state the direction of "following"', () {
      expect(MentionPolicy.following.label, 'People I follow');
      expect(MentionPolicy.following.description, contains('you follow'));
    });

    test('ClubUser reads mention_policy, defaulting to everyone', () {
      final u = ClubUser.fromJson({'handle': 'fab', 'mention_policy': 'nobody'});
      expect(u.mentionPolicy, MentionPolicy.nobody);
      expect(ClubUser.fromJson({'handle': 'fab'}).mentionPolicy,
          MentionPolicy.everyone);
      expect(u.copyWith(mentionPolicy: MentionPolicy.following).mentionPolicy,
          MentionPolicy.following);
    });
  });

  group('the /config launch gate', () {
    test('an absent key leaves the composers off', () {
      final c = ClubServerConfig.fromJson({});
      expect(c.maxMentionsPerText, isNull);
      expect(c.mentionsEnabled, isFalse);
    });

    test('the served cap turns them on', () {
      final c = ClubServerConfig.fromJson({'max_mentions_per_text': 16});
      expect(c.maxMentionsPerText, 16);
      expect(c.mentionsEnabled, isTrue);
    });

    test('a zero cap reads as off, not as a cap of zero', () {
      expect(ClubServerConfig.fromJson({'max_mentions_per_text': 0}).mentionsEnabled,
          isFalse);
    });

    test('the fallback config has mentions off', () {
      expect(ClubServerConfig.fallback.mentionsEnabled, isFalse);
    });
  });
}
