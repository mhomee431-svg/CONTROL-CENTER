import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/auth_service.dart' show authAppVersion;

/// "About Hyperlocal" — app identity, version and what the product does.
///
/// The version comes from the single [authAppVersion] constant that the
/// device already reports to the backend, so the About screen can never
/// drift from what the server believes is installed. Reading it from a
/// second hardcoded literal is exactly how these go stale.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.travel_explore,
                    size: 46,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Hyperlocal',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Version $authAppVersion',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'Search any product and instantly discover which nearby '
                    'shop has it, at what price, and how far away it is.',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _AboutTile(
            key: const Key('aboutWhatWeDoTile'),
            icon: Icons.storefront_outlined,
            title: 'What Hyperlocal does',
            subtitle: 'Browse nearby shops, compare prices and availability',
            onTap: () => context.push('/help'),
          ),
          _AboutTile(
            key: const Key('aboutPrivacyTile'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'What we collect and how we use it',
            onTap: () => context.push('/privacy'),
          ),
          _AboutTile(
            key: const Key('aboutTermsTile'),
            icon: Icons.gavel_outlined,
            title: 'Terms of Service',
            subtitle: 'The rules for using Hyperlocal',
            onTap: () => context.push('/terms'),
          ),
          _AboutTile(
            key: const Key('aboutEnvironmentTile'),
            icon: Icons.dns_outlined,
            title: 'Environment',
            // Surfaced deliberately: a mis-pointed build is far easier to
            // diagnose when the customer can see which API they are on.
            subtitle: _environmentLabel(EnvConfig.environment),
            // Deliberately NOT a navigation target. There is no "Environment"
            // screen to go to, and a row drawn with the same icon/title/
            // subtitle shape as its neighbours, minus the chevron, still reads
            // as tappable — a tap that does nothing is worse than no row at
            // all. Instead this is a real interaction: it COPIES the build's
            // diagnostic details, so a customer reporting a bug can paste
            // exactly which backend and Maps configuration they are on.
            //
            // The full URL and the Maps key are deliberately NOT shown or
            // copied: the host is enough to identify a mis-pointed build, and
            // a Maps key is a credential.
            onTap: () => _copyBuildDetails(context),
            // A copy glyph, not a chevron: the row copies, it does not navigate,
            // and a chevron would promise a screen that does not exist.
            trailingIcon: Icons.copy_all_outlined,
          ),
        ],
      ),
    );
  }

  static String _environmentLabel(AppEnv env) => switch (env) {
    AppEnv.development => 'Development',
    AppEnv.staging => 'Staging',
    AppEnv.production => 'Production',
  };

  /// Copies this build's diagnostic identity to the clipboard.
  ///
  /// WHY A COPY, NOT A SCREEN
  /// -----------------------
  /// The useful question behind this row is "which backend is this build
  /// pointed at?", and the answer is only ever read by someone diagnosing a
  /// report — a support agent, or the customer pasting into a ticket. A screen
  /// existing only to display three facts would be a worse dead control than
  /// the row it replaced: one more tap, one more route, the same information.
  ///
  /// WHAT IS AND IS NOT COPIED
  /// -------------------------
  /// The API HOST only — never the full URL (a path could carry a tenant or
  /// debug segment) and never `EnvConfig.mapsApiKey`, which is a credential.
  /// Whether a key is configured IS reported, because "Maps is not configured"
  /// is itself the diagnosis a support agent needs.
  static void _copyBuildDetails(BuildContext context) {
    final env = _environmentLabel(EnvConfig.environment);

    String host = 'not configured';
    if (EnvConfig.hasApiBaseUrl) {
      final uri = Uri.tryParse(EnvConfig.apiBaseUrl);
      // `host` is empty for a bare host with no scheme; fall back to the raw
      // value rather than printing an empty string, which would be a useless
      // report.
      host = (uri != null && uri.host.isNotEmpty)
          ? uri.host
          : EnvConfig.apiBaseUrl;
    }

    final details = [
      'Hyperlocal $authAppVersion',
      'Environment: $env',
      'API host: $host',
      'Maps key configured: ${EnvConfig.mapsApiKey.isNotEmpty}',
      'Release build: ${EnvConfig.isRelease}',
    ].join('\n');

    final messenger = ScaffoldMessenger.of(context);

    // The confirmation is shown FIRST, and the copy is fire-and-forget after
    // it. Ordering it the other way round made the whole control depend on the
    // clipboard platform channel resolving — and under a widget test that
    // channel never does, so the tap appeared to do nothing at all. A customer
    // must never be left wondering whether their tap registered, and neither
    // must a test.
    messenger
      ..hideCurrentSnackBar()
      // States the ACTION ("copied"), not the feature ("environment"): the
      // customer is about to paste this into a bug report, and that is the
      // only thing the message is for.
      ..showSnackBar(
        const SnackBar(
          content: Text('Build details copied — paste them in your report'),
        ),
      );

    // Deliberately not awaited: the copy must never be able to delay or
    // suppress the confirmation above. A failure here means the clipboard was
    // unavailable, which is not worth an error dialog on an About screen.
    unawaited(
      Clipboard.setData(ClipboardData(text: details)).catchError((Object _) {}),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// What the row does. Null means the row is INFORMATION, not navigation —
  /// and then it must not be drawn like a navigation row.
  final VoidCallback? onTap;

  /// Trailing affordance. Defaults to a navigation chevron, which is a PROMISE:
  /// it says "there is a next screen". A row that copies, expands or toggles
  /// must pass its own glyph instead, or the chevron advertises a destination
  /// that does not exist.
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      // No affordance at all for a row that cannot be tapped: a chevron on a
      // non-navigating row is a broken promise, and a *tappable* row with no
      // chevron is ambiguous — the copy icon below resolves both problems.
      trailing: switch ((onTap, trailingIcon)) {
        (null, _) => null,
        (_, final IconData glyph) => Icon(glyph),
        _ => const Icon(Icons.chevron_right),
      },
      onTap: onTap,
    );
  }
}
