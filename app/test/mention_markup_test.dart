// Mentions — the `<@SQID>` grammar, driven by the frozen test vectors.
//
// The vector table is §6.1 of `docs/mentions/README.md` and §11 of
// `messages/0004-mentions/0001-app-mentions-proposal.md`. The same table goes
// into the server's Python suite and the website's TypeScript suite; three
// implementations of one grammar is this feature's main risk (README §8.4), so
// if a row changes there it changes here.
//
// Fixtures, as in the contract: t5 → @fab, Qx → @mika, ZZZZ → no account.

import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/mention_markup.dart';

const _handles = {'t5': 'fab', 'Qx': 'mika'};

String _plain(String markup) => plainFromMarkup(markup, handles: _handles);

List<MentionSegment> _parse(String markup, {int max = kMaxMentionsPerText}) =>
    parseMentionMarkup(markup, handles: _handles, maxMentions: max);

List<String> _mentionedSqids(String markup) =>
    _parse(markup).whereType<MentionedSegment>().map((m) => m.sqid).toList();

void main() {
  group('§6.1 vectors — plain rendering', () {
    test('single mention', () {
      expect(_plain('hi <@t5>!'), 'hi @fab!');
    });

    test('two mentions', () {
      expect(_plain('<@t5>, <@Qx>.'), '@fab, @mika.');
    });

    test('unresolvable sqid renders the placeholder', () {
      expect(_plain('<@ZZZZ>'), '@user');
      expect(_mentionedSqids('<@ZZZZ>'), isEmpty);
    });

    test('no boundary rule: a mention may sit inside a word', () {
      expect(_plain('a<@t5>b'), 'a@fabb');
      expect(_mentionedSqids('a<@t5>b'), ['t5']);
    });

    test('hand-typed handles are plain text', () {
      expect(_plain('@fab'), '@fab');
      expect(_mentionedSqids('@fab'), isEmpty);
    });

    test('read-time resolution: a rename changes the rendering', () {
      expect(plainFromMarkup('<@t5>', handles: const {'t5': 'fabkury'}),
          '@fabkury');
    });
  });

  group('§6.1 vectors — malformed markup stays literal', () {
    for (final bad in const ['<@t5', '<@>', '<@ t5>', '< @t5>', '<@>x', '@<t5>']) {
      test('"$bad"', () {
        expect(_plain(bad), bad);
        expect(_mentionedSqids(bad), isEmpty);
      });
    }

    test('a sqid longer than the cap is not a mention', () {
      final tooLong = '<@${'a' * 33}>';
      expect(_plain(tooLong), tooLong);
    });

    test('non-alphanumeric characters are not sqids', () {
      expect(_plain('<@t-5>'), '<@t-5>');
      expect(_plain('<@t_5>'), '<@t_5>');
    });
  });

  group('the 16-mention cap', () {
    test('17 valid mentions: the first 16 link, the last is plain text', () {
      final markup = List.filled(17, '<@t5>').join(' ');
      final segments = _parse(markup);
      expect(segments.whereType<MentionedSegment>().length, 16);
      expect(plainFromMarkup(markup, handles: _handles),
          List.filled(17, '@fab').join(' '));
    });

    test('the cap is configurable, since the server owns the real value', () {
      final markup = List.filled(5, '<@Qx>').join();
      expect(_parse(markup, max: 2).whereType<MentionedSegment>().length, 2);
    });
  });

  group('parsing', () {
    test('empty text yields no segments', () {
      expect(_parse(''), isEmpty);
    });

    test('text with no mention is one plain segment', () {
      expect(_parse('just words'), const [PlainSegment('just words')]);
    });

    test('segments come back in order, with no empty or adjacent plain runs', () {
      final segments = _parse('<@t5> and <@Qx>');
      expect(segments, const [
        MentionedSegment(sqid: 't5', handle: 'fab'),
        PlainSegment(' and '),
        MentionedSegment(sqid: 'Qx', handle: 'mika'),
      ]);
    });

    test('an unresolvable sqid merges into the surrounding text', () {
      expect(_parse('a <@ZZZZ> b'), const [PlainSegment('a @user b')]);
    });

    test('newlines survive', () {
      expect(_plain('line 1\n<@t5>\nline 3'), 'line 1\n@fab\nline 3');
    });

    test('hasMentionMarkup detects only valid markup', () {
      expect(hasMentionMarkup('hi <@t5>'), isTrue);
      expect(hasMentionMarkup('hi @fab'), isFalse);
      expect(hasMentionMarkup('hi <@t5'), isFalse);
    });
  });

  group('MentionRef', () {
    test('parses the server array and drops entries without a sqid', () {
      final refs = MentionRef.listFromJson([
        {'public_sqid': 't5', 'handle': 'fab', 'avatar_url': 'https://a/1.png'},
        {'handle': 'ghost'},
        {'public_sqid': 'Qx', 'handle': 'mika'},
      ]);
      expect(refs.map((r) => r.sqid), ['t5', 'Qx']);
      expect(refs.first.avatarUrl, 'https://a/1.png');
      expect(refs.last.avatarUrl, isNull);
      expect(MentionRef.handlesOf(refs), {'t5': 'fab', 'Qx': 'mika'});
    });

    test('a missing or malformed array is empty, not a crash', () {
      expect(MentionRef.listFromJson(null), isEmpty);
      expect(MentionRef.listFromJson('nope'), isEmpty);
      expect(MentionRef.listFromJson([42, null]), isEmpty);
    });

    test('an entry with no handle falls back to the placeholder', () {
      final r = MentionRef.fromJson({'public_sqid': 't5'});
      expect(r.handle, kUnknownMentionHandle);
    });
  });

  group('serialization (composer text → markup)', () {
    const fab = PickedMention(handle: 'fab', sqid: 't5');
    const mika = PickedMention(handle: 'mika', sqid: 'Qx');

    test('a picked handle becomes markup', () {
      expect(serializeMentions('hi @fab!', const [fab]), 'hi <@t5>!');
    });

    test('two picks', () {
      expect(serializeMentions('@fab, @mika.', const [fab, mika]),
          '<@t5>, <@Qx>.');
    });

    test('no picks means no change', () {
      expect(serializeMentions('hi @fab!', const []), 'hi @fab!');
    });

    test('a pick whose token the user edited is dropped', () {
      expect(serializeMentions('hi @fabx!', const [fab]), 'hi @fabx!');
      expect(serializeMentions('hi @fa!', const [fab]), 'hi @fa!');
    });

    test('a pick the user deleted is dropped', () {
      expect(serializeMentions('hi!', const [fab]), 'hi!');
    });

    test('an @ inside a word is not a token', () {
      expect(serializeMentions('mail me at a@fab.com', const [fab]),
          'mail me at a@fab.com');
    });

    test('a mention may open the text or follow punctuation', () {
      expect(serializeMentions('@fab', const [fab]), '<@t5>');
      expect(serializeMentions('(@fab)', const [fab]), '(<@t5>)');
      expect(serializeMentions('\n@fab', const [fab]), '\n<@t5>');
    });

    test('the longer handle wins where both match', () {
      const fabkury = PickedMention(handle: 'fabkury', sqid: 'Zz');
      expect(serializeMentions('@fabkury', const [fab, fabkury]), '<@Zz>');
    });

    test('each occurrence consumes one pick', () {
      expect(serializeMentions('@fab and @fab', const [fab, fab]),
          '<@t5> and <@t5>');
      expect(serializeMentions('@fab and @fab', const [fab]),
          '<@t5> and @fab');
    });

    test('serialization honors the cap', () {
      final picks = List.filled(20, fab);
      final text = List.filled(20, '@fab').join(' ');
      final markup = serializeMentions(text, picks);
      expect(RegExp(r'<@t5>').allMatches(markup).length, kMaxMentionsPerText);
      expect(RegExp(r'@fab').allMatches(markup).length,
          20 - kMaxMentionsPerText);
    });

    test('text that already looks like markup is left alone', () {
      expect(serializeMentions('pasted <@Qx> here', const [fab]),
          'pasted <@Qx> here');
    });

    test('a handle with a dash or underscore serializes whole', () {
      const odd = PickedMention(handle: 'pixel_art-99', sqid: 'Kk');
      expect(serializeMentions('hey @pixel_art-99 ok', const [odd]),
          'hey <@Kk> ok');
    });

    test('a non-ASCII handle serializes whole', () {
      const uni = PickedMention(handle: 'мика', sqid: 'Uu');
      expect(serializeMentions('привет @мика!', const [uni]), 'привет <@Uu>!');
    });
  });

  group('round trip', () {
    test('serialize then parse returns the composer text', () {
      const picks = [
        PickedMention(handle: 'fab', sqid: 't5'),
        PickedMention(handle: 'mika', sqid: 'Qx'),
      ];
      const display = 'hey @fab and @mika, look at this';
      final markup = serializeMentions(display, picks);
      expect(markup, 'hey <@t5> and <@Qx>, look at this');
      expect(plainFromMarkup(markup, handles: _handles), display);
    });

    test('round trip survives punctuation, newlines, and repeats', () {
      const picks = [
        PickedMention(handle: 'fab', sqid: 't5'),
        PickedMention(handle: 'fab', sqid: 't5'),
        PickedMention(handle: 'mika', sqid: 'Qx'),
      ];
      const display = '@fab!\n(@mika) — and @fab again';
      expect(plainFromMarkup(serializeMentions(display, picks),
          handles: _handles), display);
    });

    test('a text with no picks round-trips unchanged', () {
      const display = 'no mentions here, just an email a@b.com';
      expect(plainFromMarkup(serializeMentions(display, const []),
          handles: _handles), display);
    });
  });
}
