import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server-emailed temporary password from a just-completed in-app
/// registration, kept **in memory only** so the onboarding wizard's "set your
/// password" step can pre-fill `current_password` (the user types only their new
/// one). Set right before the first sign-in; cleared when the wizard finishes or
/// on any failure. Never persisted or logged.
final pendingWelcomePasswordProvider = StateProvider<String?>((_) => null);

/// Session-local "skip the welcome wizard for now" flag. A safety hatch so a
/// `complete-welcome` outage can never hard-lock a signed-in user out of the app:
/// the `needs_welcome` gate also honours this. Resets each app launch.
final welcomeDismissedProvider = StateProvider<bool>((_) => false);
