import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/router/os_deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/controllers/auth_controller.dart';
import 'features/notifications/data/device_token_coordinator.dart';
import 'features/notifications/presentation/controllers/fcm_lifecycle.dart';
import 'features/notifications/presentation/controllers/in_app_notification_controller.dart';
import 'features/notifications/presentation/controllers/pending_deep_link_drain.dart';
import 'features/notifications/presentation/widgets/in_app_notification_host.dart';
import 'features/saved_and_history/data/local_saved_and_history_repository.dart';
import 'features/saved_and_history/domain/saved_and_history_repository.dart';
import 'features/search/presentation/controllers/search_controller.dart';
import 'features/settings/presentation/controllers/settings_controller.dart';
import 'core/storage/local_storage_driver.dart';

/// Bridges network-level session-expiry events (401 + failed token refresh)
/// into the auth state machine so the router moves the customer back into a
/// safe guest browsing state. Kept alive for the whole app lifetime by being
/// watched from [HyperlocalApp].
final sessionExpiryBridgeProvider = Provider<void>((ref) {
  final client = ref.watch(apiClientProvider);
  final subscription = client.sessionExpiredEvents.listen((_) {
    ref.read(authControllerProvider.notifier).handleSessionExpired();
  });
  ref.onDispose(subscription.cancel);
});

class HyperlocalApp extends ConsumerWidget {
  const HyperlocalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);
    // Keeps the session-expiry listener subscribed.
    ref.watch(sessionExpiryBridgeProvider);
    ref.watch(fcmLifecycleBootstrapProvider);
    // Replays a notification tap (background or terminated state) once the
    // router's splash/onboarding/auth gates have cleared.
    ref.watch(pendingDeepLinkDrainProvider);
    // Subscribes to OPERATING-SYSTEM deep links — a shared product URL or a
    // marketing link opened from a browser. This is what makes
    // `deep_link_guard` + `DeepLinkLauncher` reachable at all: they were built
    // and tested for exactly this, but until something handed them a platform
    // URL the whole subsystem sat unused.
    //
    // Order matters. The service subscribes and queues links; the drain above
    // replays them. Both must be watched, and neither navigates directly — the
    // service only feeds the queue, and the queue only replays once the gates
    // are clear.
    ref.watch(osDeepLinkServiceProvider);

    // ── Phase 9: personalization sync across auth transitions ──────────
    // ── Phase 10: device-token registration across auth transitions ────
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      final wasAuthenticated = previous?.status == AuthStatus.authenticated;

      if (!wasAuthenticated && next.status == AuthStatus.authenticated) {
        // Login: migrate favorites saved while logged out / as guest into
        // the account and clear them from the local queue.
        unawaited(
          ref.read(savedAndHistoryRepositoryProvider).syncPendingSaves(),
        );
        // Register this device for future push delivery (best-effort,
        // respects the master notification switch).
        unawaited(
          ref
              .read(deviceTokenCoordinatorProvider)
              .syncAfterLogin(pushEnabled: settings.pushNotificationsEnabled),
        );
      } else if (wasAuthenticated && next.status != AuthStatus.authenticated) {
        // Logout: drop account-mirrored favorites from the device so they
        // never leak into another session. Device-level history (recent
        // searches, recently viewed) is capped and intentionally retained.
        unawaited(
          LocalSavedAndHistoryRepository(ref.read(localStorageDriverProvider))
              .purgeSyncedEntries(),
        );
        // Unregister push delivery for this device.
        unawaited(ref.read(deviceTokenCoordinatorProvider).handleLogout());
        // Drop any alert still on screen or queued behind it, so messages
        // belonging to the signed-out account can never surface in the next
        // one's session.
        ref.read(inAppNotificationControllerProvider.notifier).clear();
        // Forget the sort/filter choices remembered for each search. They are
        // session UI state, not device history, so they must not carry over to
        // whoever signs in next.
        ref.read(searchQueryPreferencesProvider).clear();
      } else if (next.status == AuthStatus.sessionExpired) {
        // ── Expiry, not logout ──────────────────────────────────────────
        // The branch above is keyed on `previous == authenticated`, which is
        // the wrong trigger for an expiry and left the account's cached data on
        // the device. Two realistic paths never reach it:
        //
        //  * The app was backgrounded while signed in and a request 401s
        //    before any rebuild restores the visible authenticated state, so
        //    `previous` is whatever the last frame showed (often `guest`).
        //  * The customer is already on a public screen (still
        //    `sessionExpired` → no transition) and expiry fires again.
        //
        // In both cases the favourites cache, push registration and queued
        // alerts from the dead account survived. A different customer signing
        // in on the same device would then see them. So expiry purges the same
        // private state as logout, independent of the previous status.
        unawaited(
          LocalSavedAndHistoryRepository(ref.read(localStorageDriverProvider))
              .purgeSyncedEntries(),
        );
        unawaited(ref.read(deviceTokenCoordinatorProvider).handleLogout());
        ref.read(inAppNotificationControllerProvider.notifier).clear();
        ref.read(searchQueryPreferencesProvider).clear();
      }
    });

    return MaterialApp.router(
      title: 'Hyperlocal Discovery',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Foreground notifications are hosted ABOVE the router rather than in
      // any screen, so a push that lands while the customer is on the map,
      // mid-search, or in a half-typed field still surfaces — and still
      // never forces navigation.
      builder: (context, child) =>
          InAppNotificationHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
