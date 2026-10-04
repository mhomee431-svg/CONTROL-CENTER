import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/presentation/controllers/pending_deep_link_controller.dart';
import 'app_link_source.dart';

/// The platform source, swappable in tests.
final appLinkSourceProvider = Provider<AppLinkSource>(
  (ref) {
    final source = PlatformAppLinkSource();
    ref.onDispose(() {
      unawaited(source.dispose());
    });
    return source;
  },
);

/// Turns operating-system deep links into guarded navigation.
///
/// WHY THIS EXISTS
/// ---------------
/// The app could receive a link three ways and had no listener for any of them:
///
///  * **cold start** — the OS launched the app with a URL (a shared product,
///    a marketing link clicked in a browser);
///  * **resume** — the app was backgrounded and the link brought it forward;
///  * **foreground** — a link arrived while the app was already open.
///
/// `parseDeepLink`, `deep_link_guard` and `DeepLinkLauncher` were all built and
/// tested for exactly this, but nothing ever handed them a platform URL, so the
/// whole subsystem was unreachable in production.
///
/// THE COLD-START ORDERING, WHICH IS THE WHOLE PROBLEM
/// ---------------------------------------------------
/// The platform link and the app's own launch gates resolve independently: the
/// URL is available almost immediately, while auth and the onboarding flag are
/// read from storage and can take a moment. Navigating as soon as the URL
/// arrives would be immediately undone by the router's redirect to `/splash`.
///
/// So a link is queued, and `pendingDeepLinkDrainProvider` replays it once the
/// gates are clear. This service only *feeds* that queue — it makes no routing
/// decision and trusts the guard to judge the link when it is finally opened.
final osDeepLinkServiceProvider = Provider<OsDeepLinkService>((ref) {
  final service = OsDeepLinkService(ref);
  unawaited(service.start());
  return service;
});

class OsDeepLinkService {
  OsDeepLinkService(this._ref);

  final Ref _ref;
  StreamSubscription<Uri>? _subscription;
  bool _started = false;

  /// Subscribes to foreground/resume links and seeds the cold-start link.
  ///
  /// Safe to call more than once: the second call is ignored rather than
  /// opening a second subscription, which would double-handle every link.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final source = _ref.read(appLinkSourceProvider);

    // Cold start FIRST, and awaited, so a link that launched the app is queued
    // before any later one can overtake it in the queue.
    final initial = await source.initialLink();
    if (initial != null && _ref.mounted) _queue(initial);

    // Foreground/resume links, now attached. A burst produces several links;
    // each is queued, and the drain takes them in arrival order.
    _subscription = source.incomingLinks.listen(
      (link) {
        if (_ref.mounted) _queue(link);
      },
      // A stream error must not tear the subscription down: the next link
      // should still be handled. The error is reported and the listener stays.
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('App link stream error: $error\n$stackTrace');
      },
      cancelOnError: false,
    );
  }

  /// Hands the link to the pending-link queue, which owns the "when is it safe
  /// to navigate" decision — and which persists it, so a link that arrives
  /// before the gates clear survives even a process restart.
  ///
  /// `notificationId` stays empty for a plain OS link (a browser click, a
  /// shared URL). Only an FCM tap has a notification to mark read.
  ///
  /// `unawaited` because persisting is best-effort inside the controller; the
  /// in-memory queue is already updated by the time this returns, and the drain
  /// reads the in-memory value. Blocking here would delay the stream callback
  /// for a storage write nobody is waiting on.
  void _queue(Uri link) {
    unawaited(
      _ref
          .read(pendingDeepLinkControllerProvider.notifier)
          .enqueue(link.toString()),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}