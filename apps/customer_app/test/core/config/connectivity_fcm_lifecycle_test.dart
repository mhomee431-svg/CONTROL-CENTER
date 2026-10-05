import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks two "one true implementation" boundaries: connectivity state and the
/// FCM lifecycle.
///
/// ## Why these need enforcing
/// --------------------------
/// Both are the easiest things in a mobile app to duplicate, because the first
/// line of each is trivial (`Connectivity().onConnectivityChanged`,
/// `FirebaseMessaging.onMessage.listen`) and looks harmless in a screen. The
/// damage only appears later:
///
///  * **Connectivity** — a second listener means a second banner, or a screen
///    that still says "offline" after the app came back online. Worse, each copy
///    invents its own idea of when a network is genuinely usable, so the same
///    connection reads as online on one screen and offline on another.
///  * **FCM** — a second `onMessage` listener in a screen means notifications
///    are handled twice: two in-app banners, two navigations on tap, or a tap
///    handler racing the central one and losing the navigation context.
///
/// Both are also silent when broken: nothing crashes, the feature just quietly
/// stops working.
void main() {
  List<File> dartFiles() =>
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

  String nameOf(File f) => f.path.split(RegExp(r'[/\\]')).last;

  String sourceNamed(String name) {
    final hit = dartFiles().where((f) => nameOf(f) == name).toList();
    expect(hit, isNotEmpty, reason: '$name not found — renamed?');
    return hit.first.readAsStringSync();
  }

  group('connectivity state is owned by one service', () {
    // The plugin import is the whole boundary. Everything else reads status.
    const allowedPluginImporters = <String>{'connectivity_service.dart'};

    test('no feature reads connectivity_plus directly', () {
      final offenders = <String>[];
      for (final file in dartFiles()) {
        if (!file.readAsStringSync().contains('package:connectivity_plus')) {
          continue;
        }
        if (allowedPluginImporters.contains(nameOf(file))) continue;
        offenders.add(file.path.replaceAll(r'\', '/'));
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these files read connectivity directly. Observe '
            'connectivityStatusProvider instead, so "is the app online?" has '
            'one answer:\n${offenders.join('\n')}',
      );
    });

    test('the service exposes online, offline and reconnecting', () {
      final source = sourceNamed('connectivity_service.dart');
      expect(source, contains('enum ConnectivityStatus'));
      for (final status in const ['online', 'offline', 'reconnecting']) {
        expect(
          source,
          contains(status),
          reason: 'the spec requires an observable "$status" state',
        );
      }
    });

    test('features observe it through a provider, not a raw stream', () {
      final source = sourceNamed('connectivity_service.dart');
      expect(
        source,
        contains('connectivityStatusProvider'),
        reason: 'the observable surface must be a single provider',
      );
      expect(
        source,
        contains('connectivityServiceProvider'),
        reason: 'there must be one service instance, not one per screen',
      );
    });

    test('the service never reports online before it has checked', () {
      // Defaulting to `online` would flash a healthy banner the app cannot
      // support, and defaulting to `offline` would flash a scary one at every
      // launch. `unknown` is the only honest starting state.
      final source = sourceNamed('connectivity_service.dart');
      expect(
        source,
        contains('ConnectivityStatus.unknown'),
        reason: 'the initial state must be unknown, never a guess',
      );
    });
  });

  group('the FCM lifecycle is owned in one place', () {
    // Each of these registers a FirebaseMessaging stream. Two registrations of
    // the same stream means the notification is handled twice.
    //
    // `pending_deep_link_controller.dart` is in this set because notification
    // deep links are only HALF of what it does — it also queues OS deep links
    // from the earlier work. It is notification-layer code either way, so it
    // belongs to the lifecycle rather than in a screen.
    const lifecycleOwners = <String>{
      'fcm_notification_service.dart', // the SDK wrapper
      'fcm_lifecycle.dart', // the foreground lifecycle
      'fcm_background_handler.dart', // the background isolate
      'pending_deep_link_controller.dart', // tap -> deep link, queued
    };

    // The CURRENT firebase_messaging surface. The older `onMessageReceived` /
    // `onMessageOpenedApp` are deprecated statics; asserting them would pass on
    // an app that had stopped working the day the plugin renamed them.
    const listenerApis = <String>[
      'FirebaseMessaging.onMessage',
      'FirebaseMessaging.onMessageOpenedApp',
      'getInitialMessage',
      'onBackgroundMessage',
    ];

    test('only the notification layer registers FCM listeners', () {
      final offenders = <String>[];
      for (final file in dartFiles()) {
        if (file.path.endsWith('.g.dart') ||
            file.path.endsWith('.freezed.dart')) {
          continue;
        }
        final source = file.readAsStringSync();
        if (!listenerApis.any(source.contains)) continue;

        final name = nameOf(file);
        if (lifecycleOwners.contains(name)) continue;

        offenders.add(file.path.replaceAll(r'\', '/'));
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these files register an FCM listener directly. A second '
            'listener means a notification is handled twice — two banners, two '
            'navigations, or a tap racing the central handler:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the lifecycle is started once, from app bootstrap', () {
      expect(
        sourceNamed('main.dart'),
        contains('registerFcmBackgroundHandler'),
        reason: 'the background handler must be registered before runApp',
      );
      expect(
        sourceNamed('fcm_lifecycle.dart'),
        contains('onTokenRefresh'),
        reason: 'token refresh is part of the central lifecycle',
      );
    });

    test('foreground, background-tap and initial-message are all covered', () {
      final service = sourceNamed('fcm_notification_service.dart');
      for (final api in const [
        'FirebaseMessaging.onMessage',
        'FirebaseMessaging.onMessageOpenedApp',
        'getInitialMessage',
      ]) {
        expect(service, contains(api), reason: 'the service must wire $api');
      }
    });

    test('notification taps are queued, not navigated directly', () {
      // A background or terminated tap arrives BEFORE the router can route, so
      // navigating from the handler loses the context and strands the customer
      // on the splash screen.
      expect(
        sourceNamed('fcm_lifecycle.dart'),
        contains('pendingDeepLinkControllerProvider'),
        reason:
            'notification taps must queue through the pending deep-link '
            'controller and be replayed once routing is ready',
      );
    });
  });
}
