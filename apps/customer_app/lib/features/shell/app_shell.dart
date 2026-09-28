import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/connectivity_service.dart';
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
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}
