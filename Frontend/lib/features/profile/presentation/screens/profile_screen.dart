import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/user_profile.dart';
import '../controllers/profile_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final profileAsync = ref.watch(profileControllerProvider);
    final isGuest = authState.status == AuthStatus.guest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          if (!isGuest)
            IconButton(
              key: const Key('editProfileButton'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
              onPressed: () => context.push('/profile/edit'),
            ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off_outlined,
                  size: 64, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Couldn\'t load your profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                key: const Key('profileRetryButton'),
                onPressed: () =>
                    ref.read(profileControllerProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
        data: (profile) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (isGuest || profile == null)
              const _GuestHeader()
            else
              _ProfileHeader(profile: profile),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const _SectionLabel('Account'),
            ListTile(
              key: const Key('addressesTile'),
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('My Addresses'),
              subtitle: const Text('Manage saved addresses & default location'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/profile/addresses'),
            ),
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('My Favourites'),
              subtitle: const Text('Products & shops you saved'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/my-favorites'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Recently Viewed'),
              subtitle: const Text('Products you explored recently'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/recently-viewed'),
            ),
            if (!isGuest && profile != null) ...[
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Account state'),
                subtitle: Text(_accountStateLabel(profile.accountStatus)),
                trailing: _AccountStateChip(status: profile.accountStatus),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('App Settings'),
              subtitle: const Text('Notifications, privacy, preferences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(),
            const _SectionLabel('Legal'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy & Data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              key: const Key('logoutButton'),
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout),
              label: Text(isGuest ? 'Exit guest mode' : 'Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error.withValues(alpha: 0.1),
                foregroundColor: AppColors.error,
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _accountStateLabel(AccountStatus status) {
    switch (status) {
      case AccountStatus.active:
        return 'Your account is active and in good standing.';
      case AccountStatus.pendingVerification:
        return 'Verification pending — some features may be limited.';
      case AccountStatus.suspended:
        return 'Your account is suspended. Contact support.';
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirmLogout'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Real sign-out through the auth controller so the router redirect
      // and every auth-aware provider react.
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary,
            child: Text(
              profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'U',
              style: const TextStyle(
                fontSize: 32,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            profile.name,
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        if (profile.email.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              profile.email,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Text(
            profile.phoneNumber,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _GuestHeader extends ConsumerWidget {
  const _GuestHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const Icon(Icons.person_outline, size: 44, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'You are browsing as a guest',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Sign in to sync your favorites, addresses and alerts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              key: const Key('guestSignInButton'),
              onPressed: () => context.push('/login'),
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _AccountStateChip extends StatelessWidget {
  final AccountStatus status;

  const _AccountStateChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AccountStatus.active => ('Active', AppColors.secondary),
      AccountStatus.pendingVerification => ('Pending', AppColors.primary),
      AccountStatus.suspended => ('Suspended', AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
