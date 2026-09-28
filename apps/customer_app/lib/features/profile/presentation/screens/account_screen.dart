import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../notifications/presentation/controllers/notifications_controller.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../controllers/profile_controller.dart';

/// The customer account hub.
///
/// Every account entry lives here in one predictable place, grouped by
/// intent:
///
///  * **Account** – who you are and what you have kept (profile, saved
///    products, saved shops, search history, saved addresses)
///  * **Preferences** – notifications and app settings
///  * **Support & legal** – help, privacy, terms
///  * **Session** – log out, isolated at the bottom and styled as the
///    destructive action it is
///
/// Kept deliberately separate from [ProfileScreen]: that screen is the
/// *identity* page (avatar, name, verification state, order history), while
/// this is the *navigation* page. Splitting them stops the two lists from
/// competing for the same space and keeps each short enough to scan.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isGuest = authState.status == AuthStatus.guest;
    final unreadAlerts = ref.watch(unreadCountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          // Identity summary doubles as the entry point to the full profile,
          // so the customer never has to hunt for it.
          const _AccountSummaryCard(),
          const SizedBox(height: AppSpacing.lg),

          const SectionLabel('Account', padding: SectionLabel.tight),
          _AccountTile(
            key: const Key('accountProfileTile'),
            icon: Icons.person_outline,
            title: 'Profile',
            subtitle: 'Your name, photo and account details',
            onTap: () => context.push('/profile'),
          ),
          _AccountTile(
            key: const Key('accountSavedProductsTile'),
            icon: Icons.bookmark_outline,
            title: 'Saved Products',
            subtitle: 'Products you saved to track prices',
            onTap: () => context.push('/saved?tab=products'),
          ),
          _AccountTile(
            key: const Key('accountSavedShopsTile'),
            icon: Icons.storefront_outlined,
            title: 'Saved Shops',
            subtitle: 'Shops you follow',
            onTap: () => context.push('/saved?tab=shops'),
          ),
          _AccountTile(
            key: const Key('accountSearchHistoryTile'),
            icon: Icons.history,
            title: 'Search History',
            subtitle: 'What you have looked for',
            onTap: () => context.push('/saved?tab=search'),
          ),
          _AccountTile(
            key: const Key('accountAddressesTile'),
            icon: Icons.location_on_outlined,
            title: 'Saved Addresses',
            subtitle: 'Home, work and other saved places',
            onTap: () => context.push('/profile/addresses'),
          ),

          const SectionLabel('Preferences', padding: SectionLabel.tight),
          _AccountTile(
            key: const Key('accountNotificationsTile'),
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Price drops, offers and shop updates',
            // Surfaces the live unread count so the customer can tell there
            // is something waiting without opening the list.
            trailingBadge: unreadAlerts > 0 ? '$unreadAlerts' : null,
            onTap: () => context.push('/notifications'),
          ),
          _AccountTile(
            key: const Key('accountSettingsTile'),
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Language, theme and other preferences',
            onTap: () => context.push('/settings'),
          ),

          const SectionLabel('Support & Legal', padding: SectionLabel.tight),
          _AccountTile(
            key: const Key('accountHelpTile'),
            icon: Icons.help_outline,
            title: 'Help',
            subtitle: 'FAQ, contact us and report an issue',
            onTap: () => context.push('/help'),
          ),
          _AccountTile(
            key: const Key('accountPrivacyTile'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy',
            subtitle: 'What we collect and how we use it',
            onTap: () => context.push('/privacy'),
          ),
          _AccountTile(
            key: const Key('accountTermsTile'),
            icon: Icons.gavel_outlined,
            title: 'Terms',
            subtitle: 'Rules for using Hyperlocal',
            onTap: () => context.push('/terms'),
          ),

          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          // Session actions are last and visually distinct: signing out must
          // never sit next to "Privacy" where a stray tap could hit it.
          _LogoutTile(isGuest: isGuest),
        ],
      ),
    );
  }
}

/// Identity summary at the top of the account hub.
///
/// Degrades gracefully: a failed profile fetch must not blank the screen, it
/// just falls back to a neutral avatar. The whole account menu is usable
/// while signed out — none of it requires a loaded profile.
class _AccountSummaryCard extends ConsumerWidget {
  const _AccountSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isGuest = authState.status == AuthStatus.guest;
    final profile = ref.watch(profileControllerProvider).value;

    final name = switch (profile) {
      final UserProfile p when p.name.trim().isNotEmpty => p.name,
      _ => isGuest ? 'Guest' : 'Your account',
    };
    final subtitle = switch (profile) {
      final UserProfile p when p.phoneNumber.trim().isNotEmpty => p.phoneNumber,
      _ => isGuest
          ? 'Sign in to sync across devices'
          : 'Tap Profile to see your details',
    };
    final avatarUrl = profile?.avatarUrl;

    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        key: const Key('accountSummaryCard'),
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.primary,
          child: avatarUrl != null && avatarUrl.trim().isNotEmpty
              ? ClipOval(
                  child: NetworkImageView(
                    imageUrl: avatarUrl,
                    width: 52,
                    height: 52,
                    borderRadius: 0,
                  ),
                )
              : const Icon(Icons.person, color: Colors.white),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/profile'),
      ),
    );
  }
}

/// One row in the account list.
class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingBadge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional count rendered as a pill (used for unread notifications).
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final badge = trailingBadge;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: badge == null
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// Log-out / exit-guest row, deliberately separated from the menu above.
class _LogoutTile extends ConsumerWidget {
  const _LogoutTile({required this.isGuest});

  final bool isGuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: const Key('accountLogoutTile'),
      leading: const Icon(Icons.logout, color: AppColors.error),
      title: Text(
        isGuest ? 'Exit guest mode' : 'Log out',
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        isGuest
            ? 'Sign out of guest browsing on this device'
            : 'Sign out of your account on this device',
      ),
      onTap: () => _confirmLogout(context, ref),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isGuest ? 'Exit guest mode' : 'Log out'),
        content: Text(
          isGuest
              ? 'Your saved items stay on this device.'
              : 'You will need to sign in again to sync your saved items.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmAccountLogout'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(isGuest ? 'Exit' : 'Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Real sign-out through the auth controller so the router redirect and
      // every auth-aware provider react.
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}
