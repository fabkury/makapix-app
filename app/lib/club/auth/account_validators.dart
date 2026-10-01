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

import 'package:makapix_club/l10n/l10n.dart';

/// A permissive email shape check (the server does full validation + normalization).
bool isValidEmail(String email) {
  final e = email.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);
}

/// Returns a user-facing error, or null when the password satisfies the rules.
String? validatePasswordError(String password) {
  if (password.length < 8) return appL10n.passwordTooShort;
  if (!password.contains(RegExp(r'[A-Za-z]'))) return appL10n.passwordNeedsLetter;
  if (!password.contains(RegExp(r'[0-9]'))) return appL10n.passwordNeedsNumber;
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
  final l10n = appL10n;
  if (h.isEmpty) return l10n.handleEmpty;
  final length = h.runes.length;
  if (length < 3) return l10n.handleTooShort;
  if (length > 32) return l10n.handleTooLong;
  if (h.startsWith('-') || h.startsWith('_') || h.endsWith('-') || h.endsWith('_')) {
    return l10n.handleEdgeChars;
  }
  if (!_handleAllowed.hasMatch(h)) {
    return l10n.handleBadChars;
  }
  if (!_handleAlnum.hasMatch(h)) {
    return l10n.handleNeedsAlnum;
  }
  return null;
}
