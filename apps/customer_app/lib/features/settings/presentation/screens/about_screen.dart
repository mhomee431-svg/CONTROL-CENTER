import 'package:flutter/material.dart';
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
            onTap: null,
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
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
