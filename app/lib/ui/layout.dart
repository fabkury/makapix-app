// Shared form-factor policy for both pillars (editor + Club). This is the single source of truth
// for breakpoints and width caps — nothing else in the app may hardcode a tablet/landscape rule.
import 'package:flutter/material.dart';

/// A viewport whose shortest side reaches this is "tablet-ish" (iPad, wide desktop window):
/// denser editor toolbars by default, scaled-up chrome, scaled profile header.
const double kTabletBreakpoint = 600;

/// The artwork detail page goes two-pane (stage left, info/comments right) at/above this width.
const double kWideDetailBreakpoint = 840;

/// Centered max width for list/form surfaces (publish, settings, notifications, account, …).
const double kContentMaxWidth = 640;

/// Max width for modal bottom sheets (they center within wider viewports).
const double kSheetMaxWidth = 640;

bool isTabletSize(Size size) => size.shortestSide >= kTabletBreakpoint;

/// The editor switches to its landscape arrangement whenever the viewport is wider than tall —
/// a pure function of size (not device orientation), so desktop resizes and iPad Split View
/// behave identically to a physical rotation.
bool editorUsesLandscape(Size size) => size.width > size.height;

bool isTabletish(BuildContext context) => isTabletSize(MediaQuery.sizeOf(context));

/// Centers [child] and caps its width — the standard treatment for list/form surfaces that would
/// otherwise stretch edge-to-edge on tablets. Full-bleed surfaces (feed grids) don't use this.
class CenteredContent extends StatelessWidget {
  const CenteredContent({super.key, this.maxWidth = kContentMaxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// The app-wide replacement for [showModalBottomSheet]: identical behaviour on phones, width-capped
/// (and therefore centered) on wider viewports. Every sheet in the app goes through here.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor,
    constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
    builder: builder,
  );
}
