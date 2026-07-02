import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/config_api.dart';
import '../api/upload_api.dart';
import '../models/club_error.dart';
import '../models/license_option.dart';
import '../models/post.dart';
import '../models/server_config.dart';
import 'auth_controller.dart' show clubApiClientProvider;

final configApiProvider = Provider<ConfigApi>((ref) => ConfigApi(ref.watch(clubApiClientProvider)));
final uploadApiProvider = Provider<UploadApi>((ref) => UploadApi(ref.watch(clubApiClientProvider)));

/// Server config; falls back to the baked-in copy on failure. autoDispose so a transient failure
/// isn't cached for the whole session — it retries on next entry to the publish flow. [audit F-19/F-30]
final serverConfigProvider = FutureProvider.autoDispose<ClubServerConfig>((ref) async {
  try {
    return await ref.read(configApiProvider).fetch();
  } catch (_) {
    return ClubServerConfig.fallback;
  }
});

// autoDispose so a transient failure (→ empty license list) isn't cached for the session. [F-19/F-30]
final licensesProvider = FutureProvider.autoDispose<List<LicenseOption>>((ref) async {
  try {
    return await ref.read(uploadApiProvider).licenses();
  } catch (_) {
    return const [];
  }
});

enum PublishStatus { editing, uploading, success, error }

class PublishState {
  final PublishStatus status;
  final Post? post;
  final String? error;
  const PublishState(this.status, {this.post, this.error});
}

class PublishController extends StateNotifier<PublishState> {
  final Ref ref;
  PublishController(this.ref) : super(const PublishState(PublishStatus.editing));

  Future<void> submit({
    required List<int> bytes,
    required String filename,
    required String title,
    required String description,
    required String hashtags,
    required bool hidden,
    int? licenseId,
    List<int>? mkpxBytes,
  }) async {
    state = const PublishState(PublishStatus.uploading);
    try {
      final post = await ref.read(uploadApiProvider).uploadArtwork(
            bytes: bytes,
            filename: filename,
            title: title,
            description: description,
            hashtags: hashtags,
            hiddenByUser: hidden,
            licenseId: licenseId,
            mkpxBytes: mkpxBytes,
          );
      state = PublishState(PublishStatus.success, post: post);
    } on ClubError catch (e) {
      state = PublishState(PublishStatus.error, error: e.message);
    } catch (_) {
      state = const PublishState(PublishStatus.error, error: 'Upload failed. Please try again.');
    }
  }

  /// Replace an existing post's artwork in place (owner).
  Future<void> replace({required int postId, required List<int> bytes, required String filename}) async {
    state = const PublishState(PublishStatus.uploading);
    try {
      final post = await ref.read(uploadApiProvider).replaceArtwork(postId, bytes, filename);
      state = PublishState(PublishStatus.success, post: post);
    } on ClubError catch (e) {
      state = PublishState(PublishStatus.error, error: e.message);
    } catch (_) {
      state = const PublishState(PublishStatus.error, error: 'Replace failed. Please try again.');
    }
  }

  void reset() => state = const PublishState(PublishStatus.editing);
}

final publishControllerProvider =
    StateNotifierProvider<PublishController, PublishState>((ref) => PublishController(ref));
