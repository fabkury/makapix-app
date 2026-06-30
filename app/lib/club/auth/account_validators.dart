/// Pure, client-side mirrors of the server's account validation rules. The server
/// stays the source of truth (these only give instant feedback before a round-trip;
/// for handles the authoritative check is `/auth/check-handle-availability`).
///
/// - Password: ≥8 chars, ≥1 letter, ≥1 digit (`auth.py:validate_password`).
/// - Handle: stripped of surrounding whitespace, **1–32 code points**, any
///   **printable** Unicode — letters of any script, digits, **emoji, spaces-within,
///   punctuation, symbols** — rejecting only non-printable characters (Unicode
///   categories Cc/Cf/Co/Cs/Cn). Mirrors `utils/handles.py:validate_handle`;
///   case-insensitive uniqueness is server-only.
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
///
/// Matches the server's `validate_handle`: strip surrounding whitespace, then the
/// result must be 1–32 **code points** (Python `len`, so we count runes — an
/// astral emoji is one) of **printable** Unicode. We reject only the
/// non-printable categories we can detect cheaply (Cc control, Cs surrogate, Co
/// private-use); the exotic Cf/Cn cases are left to the server's availability
/// check, which is the authoritative verdict the UI already surfaces.
String? validateHandleError(String handle) {
  final h = handle.trim();
  if (h.isEmpty) return 'Handle cannot be empty.';
  final runes = h.runes.toList(growable: false);
  if (runes.length > 32) return 'Handle must be at most 32 characters.';
  for (final cp in runes) {
    if (_isNonPrintable(cp)) return 'Handle contains a non-printable character.';
  }
  return null;
}

/// True for the non-printable Unicode code points we can range-check without a
/// Unicode database: C0/C1 control (Cc), surrogates (Cs), and the private-use
/// areas (Co). Format (Cf) and unassigned (Cn) are deferred to the server.
bool _isNonPrintable(int cp) =>
    cp <= 0x1F || // C0 control
    (cp >= 0x7F && cp <= 0x9F) || // DEL + C1 control
    (cp >= 0xD800 && cp <= 0xDFFF) || // surrogates
    (cp >= 0xE000 && cp <= 0xF8FF) || // private use area
    (cp >= 0xF0000 && cp <= 0xFFFFD) || // supplementary PUA-A
    (cp >= 0x100000 && cp <= 0x10FFFD); // supplementary PUA-B
