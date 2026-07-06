import 'club_error.dart';

/// Shared user-facing copy for the UGC-safety flows, kept pure (no Flutter) so
/// it is unit-testable. Interpolates config-driven values (contact email, block
/// cap) rather than hardcoding them.

/// The `429 rate_limited` message on `POST /report` (contract §3 copy).
String reportRateLimitMessage(String contactEmail) =>
    "You're reporting too fast — try again later, or email $contactEmail.";

/// Maps a block/unblock [ClubError] to user-facing copy (ugc-safety §9). The
/// `bad_request`/self-block case is unreachable (the UI hides self-block) and
/// falls through to the generic message.
String blockErrorMessage(ClubError e, {required int maxBlocksPerUser}) {
  if (e.status == 409 || e.code == 'block_cap_reached') {
    return "You've reached the limit of $maxBlocksPerUser blocked users.";
  }
  if (e.status == 404 || e.code == 'not_found') return 'User not found.';
  if (e.isAuth) return 'Your session has expired. Please sign in again.';
  return 'Could not update the block — try again.';
}
