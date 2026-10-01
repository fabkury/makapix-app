import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';

import 'package:makapix_club/ui/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/club_config.dart';
import '../../models/user_profile.dart';
import '../../state/profile_providers.dart';
import 'common.dart';

/// The user's granted badges, enriched from the `GET /badge` catalog — the
/// website BadgesOverlay as a bottom sheet. Opened by tapping the badge chips
/// on a profile.
void showBadgesSheet(BuildContext context, {required UserProfile profile}) {
  showAppSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Consumer(builder: (ctx, ref, _) {
        final async = ref.watch(badgeCatalogProvider);
        return async.when(
          loading: () =>
              const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => SizedBox(
              height: 160,
              child: Center(
                  child: Text(ctx.l10n.badgesLoadError,
                      style: const TextStyle(color: Colors.white54)))),
          data: (catalog) {
            final defs = {for (final d in catalog) d.badge: d};
            final granted = profile.badges.where((g) => defs.containsKey(g.badge)).toList();
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(ctx.l10n.badgesTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (granted.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(ctx.l10n.badgesEmpty, style: const TextStyle(color: Colors.white54)))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: granted.length,
                    itemBuilder: (ctx, i) {
                      final g = granted[i];
                      final d = defs[g.badge]!;
                      return ListTile(
                        leading: d.iconUrl64.isEmpty
                            ? const Icon(Icons.shield_outlined, size: 32)
                            : SizedBox(
                                width: 32,
                                height: 32,
                                child: CachedNetworkImage(
                                    imageUrl: resolveClubUrl(d.iconUrl64),
                                    filterQuality: FilterQuality.none,
                                    errorWidget: (_, _, _) =>
                                        const Icon(Icons.shield_outlined, size: 32)),
                              ),
                        title: Text(d.label),
                        subtitle: d.description != null && d.description!.isNotEmpty
                            ? Text(d.description!, style: const TextStyle(fontSize: 12))
                            : null,
                        trailing: g.grantedAt != null
                            ? Text(timeAgo(g.grantedAt),
                                style: const TextStyle(fontSize: 11, color: Colors.white38))
                            : null,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ]);
          },
        );
      }),
    ),
  );
}
