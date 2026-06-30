/// Pure, client-side mirrors of the server's account validation rules. The server
/// stays the source of truth (these only give instant feedback before a round-trip).
///
/// - Password: ≥8 chars, ≥1 letter, ≥1 digit (`auth.py:validate_password`).
/// - Handle: 3–32 chars, `[A-Za-z0-9_-]`, no leading/trailing `-`/`_`
///   (`utils/handles.py:validate_handle`; case-insensitive uniqueness is server-only).
library;

/// A permissive email shape check (the server does full validation + normalization).
bool isValidEmail(String email) {
  final e = email.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);
}

/// Returns a user-facing error, or null when the password satisfies the rules.
String? validatePasswordError(String password) {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!password.contains(RegExp(r'[A-Za-z]'))) return 'Include at least one letter.';
  if (!password.contains(RegExp(r'[0-9]'))) return 'Include at least one number.';
  return null;
}

/// Returns a user-facing error, or null when the handle satisfies the rules.
String? validateHandleError(String handle) {
  final h = handle.trim();
  if (h.length < 3 || h.length > 32) return 'Handle must be 3–32 characters.';
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(h)) {
    return 'Use letters, numbers, hyphens or underscores.';
  }
  if (RegExp(r'^[-_]').hasMatch(h) || RegExp(r'[-_]$').hasMatch(h)) {
    return "Can't start or end with a hyphen or underscore.";
  }
  return null;
}
