import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:makapix_club/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/auth_controller.dart';
import '../state/publish_providers.dart';
import 'widgets/external_links.dart';

/// "About Makapix Club" (☰ menu). App identity + version, a short product
/// blurb, and the outbound links: website, source repositories, the platform's
/// store listing, and the moderators' contact email. Licenses open Flutter's
/// standard [LicensePage].
Future<void> showMakapixAboutDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const MakapixAboutDialog(),
    );

const String _kAppRepoUrl = 'https://github.com/fabkury/makapix-app';
const String _kServerRepoUrl = 'https://github.com/fabkury/makapix';
const String _kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=club.makapix.app';
const String _kAppStoreUrl = 'https://apps.apple.com/app/id6788845118';

class MakapixAboutDialog extends ConsumerWidget {
  const MakapixAboutDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final website = ref.watch(clubConfigProvider).baseUrl;
    // Server-provided moderation contact when available; the documented
    // fallback keeps the tile useful before /config resolves (or offline).
    final contactEmail =
        ref.watch(serverConfigProvider).valueOrNull?.moderation?.contactEmail ??
            'acme@makapix.club';
    // Each platform links to its own store; desktop shows both web listings.
    final platform = defaultTargetPlatform;
    final showPlay = platform != TargetPlatform.iOS;
    final showAppStore = platform != TargetPlatform.android;
    final l10n = context.l10n;
    return AlertDialog(
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/icons/icon.png',
                      width: 48, height: 48, filterQuality: FilterQuality.medium),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Makapix Club', style: theme.textTheme.titleLarge), // l10n-ignore: brand name
                      const _VersionLine(),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Text(l10n.aboutBody, style: theme.textTheme.bodyMedium),
              const Divider(height: 24),
              _LinkTile(
                icon: Icons.language,
                title: l10n.aboutWebsite,
                subtitle: website.replaceFirst('https://', ''),
                onTap: () => openExternalUrl(context, website),
              ),
              _LinkTile(
                icon: Icons.code,
                title: l10n.aboutAppSource,
                subtitle: 'github.com/fabkury/makapix-app', // l10n-ignore: URL
                onTap: () => openExternalUrl(context, _kAppRepoUrl),
              ),
              _LinkTile(
                icon: Icons.dns_outlined,
                title: l10n.aboutServerSource,
                subtitle: 'github.com/fabkury/makapix', // l10n-ignore: URL
                onTap: () => openExternalUrl(context, _kServerRepoUrl),
              ),
              if (showPlay)
                _LinkTile(
                  icon: Icons.shop_outlined,
                  title: l10n.aboutOnGooglePlay,
                  onTap: () => openExternalUrl(context, _kPlayStoreUrl),
                ),
              if (showAppStore)
                _LinkTile(
                  icon: Icons.apple,
                  title: l10n.aboutOnAppStore,
                  onTap: () => openExternalUrl(context, _kAppStoreUrl),
                ),
              _LinkTile(
                icon: Icons.mail_outline,
                title: l10n.aboutContact,
                subtitle: contactEmail,
                onTap: () => openEmail(context, contactEmail),
              ),
              const SizedBox(height: 10),
              Text(l10n.aboutMadeBy,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _showLicenses(context),
          child: Text(l10n.aboutLicenses),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  Future<void> _showLicenses(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'Makapix Club', // l10n-ignore: brand name
      applicationVersion: '${info.version} (${info.buildNumber})',
      applicationIcon: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Image.asset('assets/icons/icon.png', width: 48, height: 48),
      ),
    );
  }
}

/// "Version X.Y.Z (build)" resolved at runtime, so release bumps to
/// `pubspec.yaml` show up with no hand-maintained constant.
class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.outline);
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (_, snap) {
        final info = snap.data;
        if (info == null) return const SizedBox(height: 16);
        return Text(context.l10n.aboutVersion(info.version, info.buildNumber), style: style);
      },
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onTap,
    );
  }
}
