import '../models/user_profile.dart';

/// Server limits from `schemas.UserUpdate` (pydantic counts **code points**,
/// so validation uses `runes.length`, not the grapheme count a `TextField`
/// `maxLength` enforces).
const kTaglineMaxCodePoints = 48;
const kBioMaxCodePoints = 1000;

/// Builds the `PATCH /user/{user_key}` body for the Edit Profile save: only
/// fields whose trimmed value differs from [current] are included, and an
/// emptied field maps to `''` (the server stores it as an empty string —
/// "cleared"). The baseline comparison treats `null` and `''` as equivalent,
/// because a cleared field reads back from the server as `''` while a
/// never-set one reads back as `null`.
Map<String, String> buildProfilePatch(
  UserProfile current, {
  required String tagline,
  required String bio,
}) {
  final patch = <String, String>{};
  final newTagline = tagline.trim();
  final newBio = bio.trim();
  if (newTagline != (current.tagline ?? '')) patch['tagline'] = newTagline;
  if (newBio != (current.bio ?? '')) patch['bio'] = newBio;
  return patch;
}

/// Returns an error message when [value] exceeds [maxCodePoints], else null.
String? validateCodePointLength(String value, int maxCodePoints, String label) {
  final n = value.trim().runes.length;
  if (n <= maxCodePoints) return null;
  return '$label is too long ($n/$maxCodePoints characters).';
}
