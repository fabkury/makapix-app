import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/umd.dart';
import 'api_providers.dart';
import 'auth_controller.dart';

/// The UMD payload for one user (moderator-only; the page invalidates this
/// after every action so the UI stays server-true).
// autoDispose: released when the User Management page closes.
final umdUserProvider = FutureProvider.autoDispose.family<UmdUserData, String>((ref, sqid) {
  // Account switches must not leak one moderator session's view into another.
  ref.watch(currentUserSubProvider);
  return ref.watch(moderationApiProvider).getUserManagement(sqid);
});
