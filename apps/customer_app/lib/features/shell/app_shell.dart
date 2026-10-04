import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/connectivity_service.dart';
import '../../core/theme/app_theme.dart';
import '../notifications/presentation/controllers/notifications_controller.dart';
import 'offline_banner.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A `null` value means the stream has not produced its first event yet.
    // Mapping that to `online` would be the optimistic claim the tri-state
    // exists to prevent, so it maps to `unknown`, which the banner renders as
    // nothing: the shell appears immediately without a red flash on a healthy
    // connection, and without a false "all good" on a broken one.
    final status =
        ref.watch(connectivityStatusProvider).value ??
        ConnectivityStatus.unknown;

    // `value ?? 0` deliberately: while the first load is in flight there is no
    // count yet, and showing a placeholder "3" would be a fabricated claim.
    // Zero renders no badge, and the count snaps in when data lands.
    final unreadCount = ref.watch(unreadCountProvider);

    // Retry re-probes the platform rather than assuming success. A transport
    // flag alone is not proof — it lies on captive portals and dead uplinks —
    // so the banner keeps saying "Reconnecting…" until a real request works.
    Future<void> retry() async {
      final service = ref.read(connectivityServiceProvider);
      await service.checkConnectivity();
    }

    return Scaffold(
      body: Column(
        children: [
          OfflineBanner(status: status, onRetry: retry),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            // `initialLocation: true` on a re-tap pops that branch back to its
            // root, which is what a bottom bar is expected to do: tapping
            // "Home" while deep inside a shop returns you Home, not nowhere.
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          // The only destination that carries a badge. `unreadCountProvider`
          // already existed and documented itself as "for the shell / app
          // bar" — but nothing read it, so unread alerts were invisible until
          // the customer happened to tap the tab. An alert nobody sees is not
          // delivered; a small dot on the tab costs nothing.
          NavigationDestination(
            icon: _UnreadBadge(
              count: unreadCount,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: _UnreadBadge(
              count: unreadCount,
              child: const Icon(Icons.notifications),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
/// Wraps a nav icon with an unread-count bubble.
///
/// Renders nothing when `count` is 0 so a clean inbox costs no visual weight
/// and the bar does not shift as counts change. Counts above 99 abbreviate to
/// "99+": a four-character label cannot fit a 16dp bubble legibly, and the
/// exact tally is one tap away on the Notifications screen.
class _UnreadBadge extends StatelessWidget {
  final int count;
  final Widget child;

  const _UnreadBadge({required this.count, required this.child});

  /// Above this, the number is long enough that abbreviating is kinder than
  /// trying to render three digits inside a tiny bubble.
  static const int _maxExact = 99;

  /// Badge diameter. Small enough to read as an indicator on a 24dp icon,
  /// large enough that the numeral inside stays legible.
  static const double _badgeHeight = 16.0;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Semantic over brand: the bubble has to read as an "attention" cue and
    // keep its contrast against the bar in both light and dark. `error` and
    // `onError` are a guaranteed-contrast pair in every M3 scheme.
    final label = count > _maxExact ? '$_maxExact+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -AppSpacing.xs,
          top: -AppSpacing.xs,
          child: Semantics(
            // Without this, TalkBack reads the bubble as a bare number sitting
            // next to an icon. With it, the meaning survives.
            label: '$count unread notifications',
            child: Container(
              // Deliberately below `AppTouchTarget.minSize`: this is an
              // indicator riding on an icon, not a tappable control. The
              // tappable target is the whole destination, which the
              // NavigationBar already sizes at 48dp. A 48dp bubble would
              // triple the icon and blow up the bar.
              constraints: const BoxConstraints(minWidth: _badgeHeight),
              height: _badgeHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.error,
                // Fully round so the bubble reads as a circle at one digit and
                // as a pill at three.
                borderRadius: BorderRadius.circular(_badgeHeight),
                // The bar is light in light mode, so the bubble needs its own
                // outline to stay separable from a white surface.
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onError,
                  fontWeight: AppTypography.bold,
                  fontSize: AppTypography.caption,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
