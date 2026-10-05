import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../settings/presentation/controllers/settings_controller.dart';

/// Privacy & data centre.
///
/// ── A rule this screen follows without exception ───────────────────────────
/// Every sentence here is a statement about what the app **actually does
/// today**. Nothing is aspirational. A privacy screen that claims "we never
/// share data" while the app posts search events to the backend is worse than
/// no privacy screen at all — it is a false promise the customer will rely on.
///
/// Specifically, the app DOES send the following to our servers when signed
/// in, so this screen says so plainly rather than burying it:
///   * your profile (name, email, phone number),
///   * the products and shops you search, view, save and share,
///   * your push notification preferences,
///   * your saved addresses.
/// Search events are what power "popular near you", so they are a real part
/// of the product and are disclosed.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isGuest = authState.status != AuthStatus.authenticated;
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          const SectionLabel('Your rights', padding: SectionLabel.tight),
          const _PrivacyCard(
            icon: Icons.policy_outlined,
            title: 'Privacy Policy',
            body:
                'The full policy, kept inside the app so it is always readable '
                'and never behind a dead link.',
          ),
          // The policy is a separate screen: '/privacy' is the legal document,
          // '/privacy-data' (this screen) is the interactive centre.
          ListTile(
            key: const Key('privacyPolicyLink'),
            leading: const Icon(Icons.article_outlined),
            title: const Text('Read the Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            key: const Key('privacyLocationSettingsLink'),
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Location settings'),
            subtitle: const Text(
              'See what location access is allowed, or pick an area manually',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/location-settings'),
          ),
          ListTile(
            key: const Key('privacyNotificationSettingsLink'),
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification preferences'),
            subtitle: const Text(
              'Choose which alerts you receive and where they are sent',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/notification-settings'),
          ),
          const Divider(indent: AppSpacing.md),

          // -- Data use --
          const SectionLabel(
            'How your data is used',
            padding: SectionLabel.tight,
          ),
          const _PrivacyCard(
            icon: Icons.analytics_outlined,
            title: 'What we collect',
            body:
                'Your name, mobile number and email address (if you provide '
                'one), the products and shops you search for, view, save or '
                'share, your saved addresses, and your notification '
                'preferences.',
          ),
          const _PrivacyCard(
            icon: Icons.visibility_outlined,
            title: 'What we do with it',
            body:
                'To show nearby shops, compare prices and availability, keep '
                'your saved items and addresses, and deliver the alerts you '
                'asked for. Searches are used in aggregate to power "popular '
                'near you". We do not sell your personal data.',
          ),
          const _PrivacyCard(
            icon: Icons.location_on_outlined,
            title: 'How location is used',
            body:
                'Location is used to sort shops by distance and to fill in the '
                'area you are searching around. It is requested only when you '
                'tap a control that needs it, and you can always choose your '
                'area manually instead — the app is fully usable without GPS.',
          ),
          // Analytics is opt-in and off by default; show the real switch
          // rather than describing the policy in prose the customer cannot act
          // on.
          SwitchListTile(
            key: const Key('privacyAnalyticsSwitch'),
            secondary: const Icon(Icons.insights_outlined),
            title: const Text('Usage analytics'),
            subtitle: const Text(
              'Off by default. When on, only anonymous usage events are sent — '
              'never your name, number or address',
            ),
            value: settings.analyticsEnabled,
            onChanged: (value) => ref
                .read(settingsControllerProvider.notifier)
                .setAnalytics(value),
          ),
          const _PrivacyCard(
            icon: Icons.delete_sweep_outlined,
            title: 'Erase your data',
            body:
                'Clear browsing history and every local saved item from '
                'Settings → Privacy & data. Deleting your account removes your '
                'profile and synced data from our servers.',
          ),
          const Divider(indent: AppSpacing.md),

          // -- Account deletion --
          const SectionLabel('Your account', padding: SectionLabel.tight),
          if (isGuest)
            const _PrivacyCard(
              icon: Icons.person_outline,
              title: 'Signed out',
              body:
                  'Sign in to view your account, manage your data, or delete '
                  'your account entirely.',
            )
          else ...[
            ListTile(
              key: const Key('privacyDeleteAccountTile'),
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: const Text(
                'Delete account',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text(
                'Permanently remove your account and synced data',
              ),
              trailing: const Icon(Icons.chevron_right, color: AppColors.error),
              onTap: () => context.push('/delete-account'),
            ),
            const _PrivacyCard(
              icon: Icons.verified_user_outlined,
              title: 'What deleting removes',
              body:
                  'Your profile, saved products, saved shops, addresses, '
                  'notification history and preferences are permanently '
                  'removed from our servers. This cannot be undone.',
            ),
          ],
        ],
      ),
    );
  }
}

/// A titled block of plain-language explanation.
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
