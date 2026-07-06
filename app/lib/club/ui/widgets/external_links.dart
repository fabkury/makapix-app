import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Open [url] in the external browser. Falls back to copying it to the
/// clipboard (with a snackbar) if no handler is available — keeps the
/// published rules/contact reachable even where `url_launcher` can't launch.
Future<void> openExternalUrl(BuildContext context, String url) async {
  if (url.isEmpty) return;
  // Capture the messenger before any await so we don't use context across gaps.
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  }
  await _copyFallback(messenger, url, 'Link copied to clipboard.');
}

/// Open a `mailto:` composer for [email], falling back to clipboard.
Future<void> openEmail(BuildContext context, String email) async {
  if (email.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri(scheme: 'mailto', path: email);
  if (await canLaunchUrl(uri)) {
    if (await launchUrl(uri)) return;
  }
  await _copyFallback(messenger, email, 'Email address copied to clipboard.');
}

Future<void> _copyFallback(ScaffoldMessengerState messenger, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
