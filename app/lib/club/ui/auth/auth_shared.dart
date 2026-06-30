import 'package:flutter/material.dart';

/// A red error / neutral notice banner shown above auth forms. Returns null when
/// there is nothing to show, so callers can drop it straight into a children list
/// (via a spread or a null-filtering build).
Widget? authBanner({String? error, String? notice}) {
  if (error != null) {
    return _Banner(
      text: error,
      icon: Icons.error_outline,
      fg: Colors.redAccent,
      bg: const Color(0x33F44336),
      border: const Color(0x80FF5252),
    );
  }
  if (notice != null) {
    return _Banner(
      text: notice,
      icon: Icons.info_outline,
      fg: Colors.lightBlueAccent,
      bg: const Color(0x2233A0FF),
      border: const Color(0x6633A0FF),
    );
  }
  return null;
}

class _Banner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Color border;
  const _Banner({
    required this.text,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// A centered, width-constrained, scrollable column — the common auth-form shell.
class AuthFormShell extends StatelessWidget {
  final List<Widget> children;
  const AuthFormShell({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      );
}
