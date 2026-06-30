/// Pure, client-side mirrors of the server's account validation rules. The server
/// stays the source of truth (these only give instant feedback before a round-trip;
/// for handles the authoritative check is `/auth/check-handle-availability`).
///
/// - Password: ≥8 chars, ≥1 letter, ≥1 digit (`auth.py:validate_password`).
/// - Handle: stripped, **3–32 code points**, each character a **letter of any
///   script**, a **decimal digit**, a **combining mark**, or `-`/`_`; must contain
///   ≥1 letter or digit; no leading/trailing `-`/`_`. Drops whitespace, emoji,
///   symbols, and arbitrary punctuation. Mirrors
///   `utils/handle_normalize.py:validate_handle`. NFC normalization and the
///   confusable-skeleton **uniqueness** check are server-only — surfaced live via
///   `/auth/check-handle-availability` (which is the authoritative verdict).
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

/// Letters (any script) · decimal digits · combining marks (Mn/Mc) · `-` · `_`.
/// (Server NFC-normalizes first; we only trim — the live availability check is
/// authoritative for the exotic normalization/uniqueness cases.)
final _handleAllowed = RegExp(r'^[\p{L}\p{Nd}\p{Mn}\p{Mc}_-]+$', unicode: true);
final _handleAlnum = RegExp(r'[\p{L}\p{Nd}]', unicode: true);

/// Returns a user-facing error, or null when the handle satisfies the rules.
///
/// Mirrors `utils/handle_normalize.py:validate_handle`: after trimming, 3–32 code
/// points (runes — an astral letter is one); each character a letter of any
/// script, a decimal digit, a combining mark, or `-`/`_`; ≥1 letter or digit; no
/// leading/trailing `-`/`_`. (NFC normalization + confusable-skeleton uniqueness
/// are server-side; see the library doc.)
String? validateHandleError(String handle) {
  final h = handle.trim();
  if (h.isEmpty) return 'Handle cannot be empty.';
  final length = h.runes.length;
  if (length < 3) return 'Handle must be at least 3 characters.';
  if (length > 32) return 'Handle must be at most 32 characters.';
  if (h.startsWith('-') || h.startsWith('_') || h.endsWith('-') || h.endsWith('_')) {
    return 'Handle cannot start or end with a hyphen or underscore.';
  }
  if (!_handleAllowed.hasMatch(h)) {
    return 'Use letters, digits, hyphen, or underscore.';
  }
  if (!_handleAlnum.hasMatch(h)) {
    return 'Handle must contain at least one letter or digit.';
  }
  return null;
}
