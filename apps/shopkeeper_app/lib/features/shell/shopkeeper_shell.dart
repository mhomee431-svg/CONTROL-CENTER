import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/connectivity_banner.dart';

/// Responsive navigation shell:
///  - narrow (phones): Material 3 bottom NavigationBar
///  - wide (tablets/landscape/desktop): NavigationRail (extended ≥1200px)
class ShopkeeperShell extends StatelessWidget {
  const ShopkeeperShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.inventory_2_outlined, activeIcon: Icons.inventory_2, label: 'Products'),
    (icon: Icons.notifications_outlined, activeIcon: Icons.notifications, label: 'Alerts'),
    (icon: Icons.person_outline, activeIcon: Icons.person, label: 'Account'),
  ];

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  /// ── BACK CONTRACT ───────────────────────────────────────────────────────
  /// System back has three answers, and without this the middle one is undefined:
  ///
  ///   1. A **pushed route** (product details, an insights drill-down) pops
  ///      normally — Flutter handles it above this widget and `PopScope` never
  ///      fires, so the user returns exactly where they came from.
  ///   2. A **non-first tab** returns to the first tab. Without `canPop: false`
  ///      here, back on Products/Alerts/Account pops the whole shell and exits
  ///      the app — the shopkeeper loses their place and, worse, loses the
  ///      navigation context they were working in. This is the platform
  ///      convention on both Android and iOS.
  ///   3. The **first tab** exits the app, which is what the user expects and
  ///      is why `canPop` stays true there.
  ///
  /// Placed on the shell rather than on individual screens so a new tab gets the
  /// behaviour for free instead of re-deciding it.
  Widget _withBackContract(Widget child) {
    return PopScope<Object?>(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // case 3 (or a pushed route already handled it)
        navigationShell.goBranch(0); // case 2
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withBackContract(
      LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= 900) {
          final extended = width >= 1280;
          return Scaffold(
            body: Column(
              children: [
                const ConnectivityBanner(),
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: navigationShell.currentIndex,
                        onDestinationSelected: _goBranch,
                        extended: extended,
                        labelType: extended
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: Icon(Icons.storefront,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        destinations: [
                          for (final item in _items)
                            NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.activeIcon),
                              label: Text(item.label),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: navigationShell),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          // The connectivity bar sits above every tab so Offline/Reconnecting
          // is app-wide knowledge, not per-screen.
          body: Column(
            children: [
              const ConnectivityBanner(),
              Expanded(child: navigationShell),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _goBranch,
            destinations: [
              for (final item in _items)
                NavigationDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ),
            ],
          ),
        );
      },
      ),
    );
  }
}
