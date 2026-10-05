import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract: logout leaves no authenticated customer data behind.
///
/// Required order:
/// `Profile → Logout → Confirm → Firebase signOut → clear session state → Login/Welcome`
///
/// Every step is individually easy to "simplify" away with nothing failing:
///
///  * **Confirm first** — signing out on one tap loses an authenticated session
///    to a mis-tap on a shared device.
///  * **Server revoke must not block local clearing** — if the network is down
///    the user must still end up signed out locally.
///  * **Firebase sign-out, both providers** — Google Sign-In runs *through*
///    Firebase, so clearing only the phone provider leaves the previous user
///    signed in on next launch.
///  * **Clear account-scoped data** — favourites, queued notifications and
///    search filters belong to the account that just left.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('the flow exists, in order', () {
    test('Profile → Logout → Confirm', () {
      final profile = read(
        'lib/features/profile/presentation/screens/profile_screen.dart',
      );

      expect(
        profile.contains("Key('logoutButton')"),
        isTrue,
        reason: 'the logout entry point must be addressable',
      );
      expect(
        profile.contains('_confirmLogout'),
        isTrue,
        reason: 'logout must go through a confirmation step',
      );
      expect(profile.contains('showDialog<bool>'), isTrue);
      expect(profile.contains('AlertDialog'), isTrue);
      expect(
        profile.contains("Key('confirmLogout')"),
        isTrue,
        reason: 'the confirm button must be addressable by a widget test',
      );

      final gateAt = profile.indexOf('confirmed == true');
      final signOutAt = profile.indexOf('.logout()');
      expect(gateAt, greaterThan(-1), reason: 'sign-out must be gated');
      expect(
        signOutAt,
        greaterThan(gateAt),
        reason: 'the repository call must come AFTER confirmation',
      );
    });

    test('revoke happens, and both Firebase providers are cleared', () {
      final repo = read('lib/features/auth/data/api_auth_repository.dart');
      final body = repo.substring(repo.indexOf('Future<void> logout('));

      final postAt = body.indexOf('ApiEndpoints.logout');
      final phoneAt = body.indexOf('_phoneAuth.signOut()');
      final googleAt = body.indexOf('_googleAuth.signOut()');

      expect(postAt, greaterThan(-1), reason: 'must revoke server session');
      expect(phoneAt, greaterThan(-1), reason: 'must sign out of Firebase');
      expect(
        googleAt,
        greaterThan(-1),
        reason: 'Google sign-in runs through Firebase; it must also clear',
      );
      expect(phoneAt, lessThan(googleAt));
    });

    test('a failed revoke cannot strand the user signed in', () {
      final repo = read('lib/features/auth/data/api_auth_repository.dart');
      final start = repo.indexOf('Future<void> logout(');
      final end = repo.indexOf('/// Parse the backend', start);
      final body = repo.substring(start, end);

      expect(
        body.contains('catch'),
        isTrue,
        reason: 'a network failure on logout must be swallowed',
      );
      final catchAt = body.indexOf('catch');
      final phoneAt = body.indexOf('_phoneAuth.signOut()');
      expect(
        phoneAt,
        greaterThan(catchAt),
        reason: 'local sign-out must still run after a failed revoke',
      );
    });
  });

  group('no authenticated customer data survives logout', () {
    late String app;

    setUpAll(() => app = read('lib/app.dart'));

    test('account-scoped favourites are purged', () {
      expect(
        app.contains('purgeSyncedEntries'),
        isTrue,
        reason: 'account-mirrored favourites must leave the device',
      );
    });

    test('queued notifications are cleared', () {
      expect(app.contains('inAppNotificationControllerProvider'), isTrue);
      expect(
        RegExp(r'inAppNotificationControllerProvider\.notifier\)\s*\.clear\(')
            .hasMatch(app),
        isTrue,
        reason:
            'the old account\'s alerts must not surface in the next session',
      );
    });

    test('push registration is released for this device', () {
      expect(
        app.contains('handleLogout'),
        isTrue,
        reason: 'the FCM token must be unregistered',
      );
    });

    test('session UI state is cleared', () {
      expect(app.contains('searchQueryPreferencesProvider'), isTrue);
      expect(
        RegExp(r'searchQueryPreferencesProvider\)\.clear\(').hasMatch(app),
        isTrue,
      );
    });

    test('all of the above run on the logout transition itself', () {
      final branch = app.substring(
        app.indexOf(
          'wasAuthenticated && next.status != AuthStatus.authenticated',
        ),
      );
      for (final step in const [
        'purgeSyncedEntries',
        'handleLogout',
        'inAppNotificationControllerProvider',
        'searchQueryPreferencesProvider',
      ]) {
        expect(
          branch.contains(step),
          isTrue,
          reason: '$step must run in the logout branch, not elsewhere',
        );
      }
    });

    test('session expiry clears the same data as logout', () {
      final expiryAt = app.indexOf('AuthStatus.sessionExpired');
      expect(expiryAt, greaterThan(-1));
      expect(
        app.substring(expiryAt).contains('purgeSyncedEntries'),
        isTrue,
        reason: 'an expired session must purge cached account data too',
      );
    });
  });
}
