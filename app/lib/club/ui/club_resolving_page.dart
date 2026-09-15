import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/edit_bridge.dart';

/// The Club home while the sign-in state is still being resolved (`AuthStatus.loading`): the
/// token-store read, the Zero-Tap restore attempt on token-less installs (a network round trip,
/// bounded to 8 s), or the `/auth/me` revalidation on installs with tokens but no cached identity.
///
/// It is a *surface*, never a gate: the editor and the local drawing library are one tap away
/// from the first frame, exactly as on the signed-out welcome page. The elevator case (the phone
/// believes it is online but nothing gets through) used to strand the whole app on a full-screen
/// spinner for the connect timeout; the Makapix Editor is promised offline, no login, so nothing
/// on the launch path may wait on the network.
class ClubResolvingPage extends ConsumerWidget {
  const ClubResolvingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Makapix Club'),
        actions: const [NoLoginDrawActions()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(height: 16),
            Text('Connecting to Makapix Club…',
                style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const LocalLibraryButton(),
          ]),
        ),
      ),
    );
  }
}

/// The top-bar pair every not-yet-signed-in Club surface carries: the "no login needed" caption
/// and the Contribute button that opens the editor. Shared by the welcome page and the resolving
/// page so the promise reads the same wherever the app happens to land.
class NoLoginDrawActions extends ConsumerWidget {
  const NoLoginDrawActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // The brush icon alone doesn't say that drawing needs no account, so spell it out.
      // Caption only; the icon beside it is the button.
      const Flexible(
        child: Text(
          'No login needed to draw →',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
      // The editor stays reachable without signing in (mirrors the design's no-login Create).
      IconButton(
        tooltip: 'Contribute (open the editor)',
        icon: const Icon(Icons.brush_outlined),
        onPressed: () => ref.read(openEditorProvider.notifier).state++,
      ),
    ]);
  }
}

/// "My Drawings": opens the editor straight into its local library (the gallery), no sign-in
/// involved. The same drawings the signed-in profile's Private tab lists — this is the route to
/// them when there is no account, or no network to prove one.
class LocalLibraryButton extends ConsumerWidget {
  const LocalLibraryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () =>
          ref.read(pendingLocalLibraryProvider.notifier).state = const BrowseLocalLibrary(),
      icon: const Icon(Icons.collections_outlined, size: 18),
      label: const Text('My Drawings'),
    );
  }
}
