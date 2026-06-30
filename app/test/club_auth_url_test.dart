import 'package:flutter_test/flutter_test.dart';
import 'package:makapix_club/club/auth/github_oauth.dart';
import 'package:makapix_club/club/auth/pkce.dart';
import 'package:makapix_club/club/config/club_config.dart';

void main() {
  test('GithubOAuth builds the authorize URL with the agreed params', () {
    const oauth = GithubOAuth(ClubConfig(ClubEnvironment.dev));
    const pkce = Pkce(verifier: 'v', challenge: 'CHAL', state: 'ST');
    final uri = oauth.buildAuthorizeUrl(pkce);

    expect(uri.toString(),
        startsWith('https://development.makapix.club/api/v1/auth/github/login'));
    final q = uri.queryParameters;
    // The OAuth return is now a per-environment HTTPS App Link (dev host).
    expect(q['redirect_uri'], 'https://app-dev.makapix.club/oauth/github');
    expect(q['code_challenge'], 'CHAL');
    expect(q['code_challenge_method'], 'S256');
    expect(q['state'], 'ST');
  });

  test('prod environment targets makapix.club + the prod App Link redirect', () {
    const oauth = GithubOAuth(ClubConfig(ClubEnvironment.prod));
    final uri = oauth.buildAuthorizeUrl(const Pkce(verifier: 'v', challenge: 'c', state: 's'));
    expect(uri.toString(), startsWith('https://makapix.club/api/v1/auth/github/login'));
    expect(uri.queryParameters['redirect_uri'], 'https://app.makapix.club/oauth/github');
  });
}
