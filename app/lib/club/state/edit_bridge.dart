import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/club_edit_request.dart';

/// The club → editor bridge. The Club detail page sets a pending edit request;
/// the editor (app root) watches this, loads the artwork, and clears it.
final pendingClubEditProvider = StateProvider<ClubEditRequest?>((ref) => null);

/// Bumped by a Club surface (the top-bar Contribute button) to ask the shell to open the editor
/// pillar with its current document. The shell listens and switches pillars on any change.
final openEditorProvider = StateProvider<int>((ref) => 0);
