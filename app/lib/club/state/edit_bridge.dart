import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/club_edit_request.dart';

/// The club → editor bridge. The Club detail page sets a pending edit request;
/// the editor (app root) watches this, loads the artwork, and clears it.
final pendingClubEditProvider = StateProvider<ClubEditRequest?>((ref) => null);
