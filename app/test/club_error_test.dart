import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/models/club_error.dart';
import 'package:makapix_club/club/ui/widgets/common.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'l10n/l10n_test_support.dart';

void main() {
  tearDown(debugResetAppL10n);

  group('ClubError.fromBody', () {
    test('a generic code keeps the server text under a headline by status', () {
      final e = ClubError.fromBody(409, {
        'error': {'code': 'conflict', 'message': 'Already exists.'}
      });
      expect(e.status, 409);
      expect(e.code, 'conflict');
      expect(e.serverText, 'Already exists.');
      expect(e.message, "The Club didn't accept that.\nAlready exists.");
    });

    test("a specific code shows the app message in the user's language", () {
      final e = ClubError.fromBody(409, {
        'error': {'code': 'artwork_duplicate', 'message': 'This artwork already exists.'}
      });
      expect(e.code, 'artwork_duplicate');
      expect(e.serverText, isNull);
      expect(e.message, 'This artwork has already been posted.');
    });

    test('parses the FastAPI detail shape', () {
      final e = ClubError.fromBody(422, {'detail': 'Validation failed'});
      expect(e.code, 'error');
      expect(e.serverText, 'Validation failed');
      expect(e.message, "The Club didn't accept that.\nValidation failed");
    });

    test("FastAPI's validation list becomes its msg lines", () {
      final e = ClubError.fromBody(422, {
        'detail': [
          {'loc': ['body', 'bio'], 'msg': 'String should have at most 300 characters'},
          {'loc': ['body', 'name'], 'msg': 'Field required'},
        ]
      });
      expect(e.serverText, 'String should have at most 300 characters\nField required');
    });

    test('the headline follows the status class', () {
      String head(int status) =>
          ClubError.fromBody(status, {'detail': 'x'}).message.split('\n').first;
      expect(head(400), "The Club didn't accept that.");
      expect(head(403), "You don't have permission to do that.");
      expect(head(404), "The Club couldn't find that.");
      expect(head(502), 'The Club ran into a problem. Please try again later.');
    });

    test('an HTML error page or an empty body is no server text', () {
      final html = ClubError.fromBody(502, '<html><body>Bad Gateway</body></html>');
      expect(html.serverText, isNull);
      expect(html.message, 'The Club ran into a problem. Please try again later.');
      expect(ClubError.fromBody(500, '').serverText, isNull);
      expect(ClubError.fromBody(400, {
        'error': {'code': 'bad_request', 'message': '  '}
      }).serverText, isNull);
    });

    test('a download error body arrives as bytes and is still read', () {
      final e = ClubError.fromBody(
          403,
          utf8.encode(jsonEncode({
            'error': {'code': 'not_remixable', 'message': 'Layers are not shared.'}
          })));
      expect(e.code, 'not_remixable');
      expect(ClubError.fromBody(404, utf8.encode('File not found')).serverText,
          'File not found');
    });

    test('very long server text is cut', () {
      final e = ClubError.fromBody(400, {'detail': 'x' * 1000});
      expect(e.serverText!.length, 301);
      expect(e.serverText, endsWith('…'));
    });

    test('isAuth / isRateLimited flags', () {
      expect(ClubError.fromBody(401, const {}).isAuth, isTrue);
      expect(ClubError.fromBody(429, const {}).isRateLimited, isTrue);
      expect(ClubError.fromBody(200, const {}).isAuth, isFalse);
    });
  });

  group('describe', () {
    const headline = 'Could not save your profile.';

    test("puts the server text under the screen's headline", () {
      final e = ClubError.fromBody(400, {'detail': 'Bio must be 300 characters or fewer'});
      expect(e.describe(headline), '$headline\nBio must be 300 characters or fewer');
    });

    test("a known code's own message beats the headline", () {
      final e = ClubError.fromBody(409, {
        'error': {'code': 'handle_taken', 'message': 'Handle taken'}
      });
      expect(e.describe(headline), 'That username is already taken.');
    });

    test('with nothing better to say, the headline alone', () {
      expect(ClubError.fromBody(500, null).describe(headline), headline);
      expect(ClubError.fromBody(400, {
        'error': {'code': 'bad_request', 'message': ''}
      }).describe(headline), headline);
    });

    test('a lost connection keeps its own message', () {
      final e = ClubError.fromDio(DioException(
          requestOptions: RequestOptions(), type: DioExceptionType.connectionError));
      expect(e.describe(headline), 'Network error — check your connection.');
    });

    test('clubErrorText falls back to the headline for other errors', () {
      expect(clubErrorText(StateError('boom'), headline), headline);
      expect(clubErrorText(ClubError.fromBody(404, {'detail': 'Post not found'}), headline),
          '$headline\nPost not found');
    });
  });

  testWidgets("other languages get the headline in their own words", (tester) async {
    late String text;
    await tester.pumpWidget(localizedApp(
        const Locale('es'),
        Builder(builder: (context) {
          text = ClubError.fromBody(404, {'detail': 'Post not found'})
              .describe(context.l10n.artworkLoadError);
          return const SizedBox();
        })));
    expect(text.split('\n').first, isNot(contains('Could not')));
    expect(text.split('\n').last, 'Post not found');
    expect(appL10n.localeName, 'es');
    expect(ClubError.fromBody(404, {'detail': 'x'}).message.split('\n').first,
        appL10n.srvNotFound);
  });

  group('ClubMessageText', () {
    testWidgets('one line is a plain Text', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ClubMessageText('Saved.')));
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('the server text is a smaller, muted second line', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: ClubMessageText('Could not save.\nBio too long',
              style: TextStyle(fontSize: 20, color: Color(0xFFFFFFFF)))));
      final rich = tester.widget<Text>(find.byType(Text));
      final span = rich.textSpan! as TextSpan;
      expect(span.text, 'Could not save.');
      final detail = span.children!.single as TextSpan;
      expect(detail.text, '\nBio too long');
      expect(detail.style!.fontSize, closeTo(17, 0.01));
      expect(detail.style!.color!.a, closeTo(0.7, 0.01));
    });
  });
}
