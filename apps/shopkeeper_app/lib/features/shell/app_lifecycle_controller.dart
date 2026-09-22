import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_providers.dart';
import '../../core/state/connectivity_controller.dart';
import '../auth/presentation/controllers/auth_controller.dart';
import '../auth/presentation/controllers/selected_shop.dart';
import '../dashboard/presentation/controllers/dashboard_controller.dart';
import '../shops/presentation/controllers/shops_controller.dart';

/// Injectable clock — tests advance it to simulate a long background stay
/// without waiting for real time.
@visibleForTesting
final lifecycleClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// A snapshot of the app's lifecycle posture, for observability (and any
/// future UI that wants to react to backgrounding).
class AppLifecycleSnapshot {
  const AppLifecycleSnapshot({
    required this.appState,
    this.lastResumeRefreshAt,
    this.lastReconnectRefreshAt,
  });

  final AppLifecycleState appState;
  final DateTime? lastResumeRefreshAt;
  final DateTime? lastReconnectRefreshAt;

  AppLifecycleSnapshot copyWith({
    AppLifecycleState? appState,
    DateTime? lastResumeRefreshAt,
    DateTime? lastReconnectRefreshAt,
  }) =>
      AppLifecycleSnapshot(
        appState: appState ?? this.appState,
        lastResumeRefreshAt: lastResumeRefreshAt ?? this.lastResumeRefreshAt,
        lastReconnectRefreshAt:
            lastReconnectRefreshAt ?? this.lastReconnectRefreshAt,
      );
}

final appLifecycleControllerProvider =
    NotifierProvider<AppLifecycleController, AppLifecycleSnapshot>(
  AppLifecycleController.new,
);

/// App-lifecycle coordinator — background / foreground / reconnect handling.
///
/// Owns the app's ONLY `WidgetsBindingObserver` (mounted by `ShopkeeperApp`,
/// which watches this provider). Nothing else may observe lifecycle changes,
/// so every lifecycle concern funnels through exactly one place:
///
///  * **Resumed** — after the app comes back from the background, refresh the
///    "important stale" data (the dashboard — which also re-reads the
///    unread-notification count through its alert chain — and the
///    authorized-shop list that the router guards and account screens read) —
///    but ONLY when the cached copy is older than [resumeStaleAfter].
///    Screen-scoped lists (products, insights, support tickets, …) stay out
///    on purpose: they re-read on their own screen entry, so a resume
///    refresh would double-fetch them. A short trip to the notification
///    shade must not trigger ANY network traffic.
///  * **Paused / inactive / hidden / detached** — bookkeeping only: the app
///    runs no timers or polling worth cancelling, so backgrounding is a
///    no-op.
///  * **Network reconnect** — when the link returns after a drop, the same
///    refresh runs regardless of age (the offline copy may be arbitrarily
///    stale, and the cached-data notice promises a refresh on reconnect).
///    Flapping links are throttled to one refresh per [reconnectThrottle].
///  * **Token refresh** — reactive by design: [TokenRefreshInterceptor] (in
///    `core/network/api_providers.dart`) retries any 401 with the refresh
///    token and hands unrecoverable expiries to the auth flow, so background
///    refreshes need no pre-emptive token work. After a refresh batch the
///    cached `accessTokenProvider` is invalidated so late readers never see
///    a token the interceptor already rotated.
///
/// Every refresh is SILENT (`DashboardController.refresh` /
/// `ShopsController.refresh` keep the current state visible) and fail-soft:
/// a failed background refresh never shows an error over working data. And
/// nothing here reloads on navigation or frame callbacks — the only triggers
/// are lifecycle transitions and the connectivity edge itself.
class AppLifecycleController extends Notifier<AppLifecycleSnapshot>
    with WidgetsBindingObserver {
  /// Resume refresh fires only when the cached data is older than this.
  static const resumeStaleAfter = Duration(minutes: 5);

  /// At most one reconnect refresh per window — Wi-Fi ↔ mobile flapping
  /// emits many disconnected→connected edges in quick succession.
  static const reconnectThrottle = Duration(seconds: 10);

  @override
  AppLifecycleSnapshot build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));

    // Reconnect handling: `ConnectivityController` (core/state) owns the
    // Online / Offline / Reconnecting machine — a reconnect is only real once
    // its backend probe succeeds, so this listens for the offline/other →
    // ONLINE edge and refreshes the important data then. The in-flight guard
    // also dedupes the case where a resume and a reconnect fire together.
    ref.listen(connectivityControllerProvider, (previous, next) {
      final cameBackOnline =
          previous != null && !previous.isOnline && next.isOnline;
      if (cameBackOnline) {
        unawaited(_refreshOnReconnect());
      }
    });

    return AppLifecycleSnapshot(
      appState:
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  bool _refreshInFlight = false;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshIdle;

  // The parameter is renamed from the override's `state` because the
  // Notifier's own `state` property occupies that name here.
  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState newState) {
    if (newState == state.appState) return;
    state = state.copyWith(appState: newState);
    if (newState == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
    }
    // paused / inactive / hidden / detached: nothing to do — see class doc.
  }

  Future<void> _refreshAfterResume() async {
    if (!_canRefresh) return; // signed-out / no shop: nothing to refresh
    final now = ref.read(lifecycleClockProvider)();
    final last = _lastRefreshAt;
    // A short trip (notification shade, app switch) must not hit the network:
    // only resume-refresh once the cached data has actually gone stale.
    if (last != null && now.difference(last) < resumeStaleAfter) return;
    await _runStaleRefresh(isResume: true);
  }

  Future<void> _refreshOnReconnect() async {
    if (!_canRefresh) return;
    final now = ref.read(lifecycleClockProvider)();
    final last = _lastRefreshAt;
    // Flapping links fire many edges — refresh at most once per window.
    if (last != null && now.difference(last) < reconnectThrottle) return;
    await _runStaleRefresh(isResume: false);
  }

  bool get _canRefresh =>
      ref.read(authControllerProvider).isAuthenticated &&
      ref.read(selectedShopProvider) != null;

  Future<void> _runStaleRefresh({required bool isResume}) {
    if (_refreshInFlight) return Future.value();
    _refreshInFlight = true;
    final work = _doStaleRefresh(isResume: isResume);
    _refreshIdle = work;
    return work;
  }

  Future<void> _doStaleRefresh({required bool isResume}) async {
    try {
      await Future.wait([
        ref.read(dashboardControllerProvider.notifier).refresh(),
        ref.read(shopsControllerProvider.notifier).refresh(),
      ]);
      ref.invalidate(accessTokenProvider);
      _lastRefreshAt = ref.read(lifecycleClockProvider)();
      state = state.copyWith(
        lastResumeRefreshAt:
            isResume ? _lastRefreshAt : state.lastResumeRefreshAt,
        lastReconnectRefreshAt:
            isResume ? state.lastReconnectRefreshAt : _lastRefreshAt,
      );
    } catch (_) {
      // Fail-soft: a failed background refresh must never crash the app or
      // disturb the UI; the next resume/reconnect simply tries again.
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Completes when the refresh batch spawned by the last lifecycle event
  /// (if any) has finished. Tests await this instead of guessing timings.
  @visibleForTesting
  Future<void> get refreshIdle => _refreshIdle ?? Future.value();
}
