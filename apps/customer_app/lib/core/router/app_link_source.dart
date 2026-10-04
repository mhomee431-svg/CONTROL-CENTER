import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// The platform's incoming-link stream, behind a seam the app can depend on.
///
/// WHY THIS EXISTS
/// ---------------
/// `AppLinks` is a platform channel: it cannot run in a widget test, and a test
/// that reaches for it directly either fails or silently does nothing. Every
/// caller that needs "a link arrived" should depend on this interface instead,
/// so the routing decision can be tested with a fake while production uses the
/// real plugin.
///
/// This is infrastructure, not policy. Deciding whether a link may be opened
/// belongs to `deep_link_guard.dart`; doing it belongs to
/// `deep_link_launcher.dart`.
abstract class AppLinkSource {
  /// Links delivered while the app is running or brought to the foreground.
  Stream<Uri> get incomingLinks;

  /// The link the app was launched with, if any.
  ///
  /// Separate from [incomingLinks] because a COLD START delivers the link
  /// before any listener is attached — reading it from the stream alone would
  /// lose the very link that started the app. That is the single most common
  /// way deep linking silently breaks: it works while the app is open and
  /// fails exactly when a notification from a terminated app is tapped.
  Future<Uri?> initialLink();

  /// Releases the platform subscription.
  Future<void> dispose();
}

/// The production source, backed by the `app_links` plugin.
class PlatformAppLinkSource implements AppLinkSource {
  PlatformAppLinkSource([AppLinks? links]) : _links = links ?? AppLinks();

  final AppLinks _links;

  @override
  Stream<Uri> get incomingLinks => _links.uriLinkStream;

  @override
  Future<Uri?> initialLink() async {
    try {
      return await _links.getInitialLink();
    } catch (error, stackTrace) {
      // A platform channel failure must never stop the app from launching. The
      // customer gets the normal first screen, which is exactly the outcome of
      // having opened no link at all.
      debugPrint('Initial app link could not be read: $error\n$stackTrace');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    // Nothing is retained here: `incomingLinks` is a broadcast stream the
    // platform owns, and the listener is cancelled by whoever attached it.
    // Disposing must therefore be a no-op rather than a throw.
  }
}

/// A test double: emit links on demand, seed a cold-start link.
///
/// Kept in `lib` rather than `test` so any layer can substitute it — including
/// a future `integration_test/` harness — without re-implementing
/// [AppLinkSource].
class FakeAppLinkSource implements AppLinkSource {
  /// Seeded as `initialLink` so a test can declare its cold-start link inline.
  FakeAppLinkSource({Uri? initialLink})
    : _seededInitialLink = initialLink,
      _controller = StreamController<Uri>.broadcast();

  Uri? _seededInitialLink;
  final StreamController<Uri> _controller;

  /// Sets the link the next [initialLink] call reports.
  ///
  /// Deliberately NOT named `initialLink`: the interface declares that as a
  /// method, and a field or setter of the same name would collide with it.
  set coldStartLink(Uri? value) => _seededInitialLink = value;

  /// Simulates the OS handing the app a link.
  void emit(Uri link) {
    if (!_controller.isClosed) _controller.add(link);
  }

  @override
  Stream<Uri> get incomingLinks => _controller.stream;

  @override
  Future<Uri?> initialLink() async => _seededInitialLink;

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }
}