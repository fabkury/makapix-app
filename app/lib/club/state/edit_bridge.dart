import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../edit/club_edit_request.dart';

/// The club → editor bridge. The Club detail page sets a pending edit request;
/// the editor (app root) watches this, loads the artwork, and clears it.
final pendingClubEditProvider = StateProvider<ClubEditRequest?>((ref) => null);

/// Bumped by a Club surface (the top-bar Contribute button) to ask the shell to open the editor
/// pillar with its current document. The shell listens and switches pillars on any change.
final openEditorProvider = StateProvider<int>((ref) => 0);

/// Bumped by the editor's ☰ menu ("Club") to ask the shell to return to the Club pillar. The shell
/// listens and switches pillars on any change.
final openClubProvider = StateProvider<int>((ref) => 0);

/// A pending local-library action requested from the profile's Private tab (the "My Drawings"
/// content surfaced on your own profile). The shell listens and switches to the editor pillar; the
/// editor consumes it on mount (see editor_page.persistence.dart) and runs its usual open / new flow
/// — including the keep/discard prompt for the current drawing. Rename/Delete are handled in-place
/// in the tab and never travel through here.
sealed class LocalLibraryRequest {
  const LocalLibraryRequest();
}

/// Open the existing library drawing [id] in the editor.
class OpenLocalDrawing extends LocalLibraryRequest {
  final String id;
  const OpenLocalDrawing(this.id);
}

/// Start a brand-new drawing in the editor.
class NewLocalDrawing extends LocalLibraryRequest {
  const NewLocalDrawing();
}

final pendingLocalLibraryProvider = StateProvider<LocalLibraryRequest?>((ref) => null);
