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

/// A pending local-library action requested from a Club surface: the profile's Private tab (the
/// "My Drawings" content surfaced on your own profile), or the "My Drawings" button on the
/// signed-out welcome and the resolving page (no account, or no network to prove one). The shell
/// listens and switches to the editor pillar; the editor consumes it on mount (see
/// editor_page.persistence.dart) and runs its usual open / new / gallery flow — including the
/// keep/discard prompt for the current drawing. Rename/Delete are handled in-place in the tab and
/// never travel through here.
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

/// Open the editor's own library page (the gallery) over the current drawing, so the user picks
/// from there — the offline route to "My Drawings" when the Private tab is out of reach.
class BrowseLocalLibrary extends LocalLibraryRequest {
  const BrowseLocalLibrary();
}

final pendingLocalLibraryProvider = StateProvider<LocalLibraryRequest?>((ref) => null);

/// Which pillar the shell currently has MOUNTED. Written by AppShell on every switch;
/// consumed by providers that should idle while their surface is unmounted (the player
/// poll — battery F8). Read-only signal: to switch pillars, bump [openEditorProvider] /
/// [openClubProvider] instead.
enum AppPillar { club, editor }

final activePillarProvider = StateProvider<AppPillar>((ref) => AppPillar.club);
