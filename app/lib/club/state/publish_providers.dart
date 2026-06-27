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

/// Server config (cached); falls back to the baked-in copy on failure.
final serverConfigProvider = FutureProvider<ClubServerConfig>((ref) async {
  try {
    return await ref.read(configApiProvider).fetch();
  } catch (_) {
    return ClubServerConfig.fallback;
  }
});

final licensesProvider = FutureProvider<List<LicenseOption>>((ref) async {
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
          );
      state = PublishState(PublishStatus.success, post: post);
    } on ClubError catch (e) {
      state = PublishState(PublishStatus.error, error: e.message);
    } catch (_) {
      state = const PublishState(PublishStatus.error, error: 'Upload failed. Please try again.');
    }
  }

  void reset() => state = const PublishState(PublishStatus.editing);
}

final publishControllerProvider =
    StateNotifierProvider<PublishController, PublishState>((ref) => PublishController(ref));
