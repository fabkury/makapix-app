import 'package:makapix_club/l10n/l10n.dart';

// Badge names and descriptions in the user's language, keyed by the badge's stable slug. The
// server's labels are English and live only in its database; a badge it adds later shows the
// server's text until the app learns it (messages/0005-localized-text/0003 §4).

/// The badge's name: the app's own for the slugs it knows, else [serverLabel].
String badgeLabel(String slug, String serverLabel) {
  final l = appL10n;
  return switch (slug) {
    'early-adopter' => l.badgeEarlyAdopter,
    'master' => l.badgeMaster,
    'moderator' => l.badgeModerator,
    'roots' => l.badgeRoots,
    'top-contributor' => l.badgeTopContributor,
    _ => serverLabel,
  };
}

/// The badge's description: the app's own for the slugs it knows, else [serverDescription].
String? badgeDescription(String slug, String? serverDescription) {
  final l = appL10n;
  return switch (slug) {
    'early-adopter' => l.badgeEarlyAdopterDesc,
    'master' => l.badgeMasterDesc,
    'moderator' => l.badgeModeratorDesc,
    'roots' => l.badgeRootsDesc,
    'top-contributor' => l.badgeTopContributorDesc,
    _ => serverDescription,
  };
}
