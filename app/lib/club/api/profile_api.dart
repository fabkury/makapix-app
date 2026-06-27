import 'package:dio/dio.dart';

import '../models/club_error.dart';
import '../models/page.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import 'club_api_client.dart';

/// Profiles + the follow graph. (Reuses [PostOwner] as a lightweight user card
/// for follower/following lists, whose shape matches.)
class ProfileApi {
  final ClubApiClient client;
  ProfileApi(this.client);

  Future<UserProfile> profile(String sqid) async {
    try {
      final resp = await client.dio.get('/user/u/${Uri.encodeComponent(sqid)}/profile');
      return UserProfile.fromJson((resp.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// Follow → returns the new follower_count (or -1 if absent).
  Future<int> follow(String sqid) => _followCall('post', sqid);
  Future<int> unfollow(String sqid) => _followCall('delete', sqid);

  Future<int> _followCall(String method, String sqid) async {
    final path = '/user/u/${Uri.encodeComponent(sqid)}/follow';
    try {
      final resp = method == 'post' ? await client.dio.post(path) : await client.dio.delete(path);
      return ((resp.data as Map?)?['follower_count'] as num?)?.toInt() ?? -1;
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  /// Posts the user reacted to (favourites). Tolerates either a Page or a bare
  /// `{items:[...]}` response.
  Future<List<Post>> reactedPosts(String sqid) async {
    try {
      final resp = await client.dio.get('/user/u/${Uri.encodeComponent(sqid)}/reacted-posts');
      return Page<Post>.fromJson((resp.data as Map).cast<String, dynamic>(), Post.fromJson).items;
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }

  Future<List<PostOwner>> followers(String sqid, {String? cursor}) =>
      _people('/user/u/${Uri.encodeComponent(sqid)}/followers', cursor);
  Future<List<PostOwner>> following(String sqid, {String? cursor}) =>
      _people('/user/u/${Uri.encodeComponent(sqid)}/following', cursor);

  Future<List<PostOwner>> _people(String path, String? cursor) async {
    try {
      final resp = await client.dio.get(path, queryParameters: {'cursor': ?cursor});
      return Page<PostOwner>.fromJson((resp.data as Map).cast<String, dynamic>(), PostOwner.fromJson)
          .items;
    } on DioException catch (e) {
      throw ClubError.fromDio(e);
    }
  }
}
