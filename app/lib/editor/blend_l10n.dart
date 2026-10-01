// What the blend modes are called on screen. The engine tokens ("Multiply", "HardLight") stay
// in blend_modes.dart: they are what the DSL and the document carry, in every language.
import 'package:makapix_club/l10n/l10n.dart';

import 'blend_modes.dart';

/// The display name of the blend mode whose engine token is [token].
String blendName(AppLocalizations l, String token) => switch (token) {
      'Normal' => l.blendNormal,
      'Multiply' => l.blendMultiply,
      'Screen' => l.blendScreen,
      'Overlay' => l.blendOverlay,
      'Darken' => l.blendDarken,
      'Lighten' => l.blendLighten,
      'Addition' => l.blendAddition,
      'Subtract' => l.blendSubtract,
      'Difference' => l.blendDifference,
      'Exclusion' => l.blendExclusion,
      'HardLight' => l.blendHardLight,
      _ => token,
    };

/// The heading of a picker section of [kBlendGroups].
String blendGroupName(AppLocalizations l, String group) => switch (group) {
      'Normal' => l.blendNormal,
      'Darken' => l.blendGroupDarken,
      'Lighten' => l.blendGroupLighten,
      'Contrast' => l.blendGroupContrast,
      'Compare' => l.blendGroupCompare,
      _ => group,
    };

/// The short tile badge of a non-Normal mode (two letters; one character in Japanese and
/// Chinese); '' for Normal and for an unknown token.
///
/// One message holds the ten badges, comma-separated in wire order: they are only meaningful
/// as a set (all different), and test/l10n checks that for every language.
String blendBadgeText(AppLocalizations l, String token) {
  final i = kBlendModes.indexOf(token);
  if (i <= 0) return '';
  final badges = l.blendBadges.split(',');
  return i - 1 < badges.length ? badges[i - 1] : '';
}
