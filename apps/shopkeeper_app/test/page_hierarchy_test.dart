import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/primary_cta_bar.dart';

/// DESIGN CONTRACT — the predictable page hierarchy.
///
///     TOP     Back / Title / contextual action
///     BODY    sections · cards · forms
///     BOTTOM  Primary CTA where necessary
///
///     AVOID   multiple competing CTAs
///
/// Three layers, in the same order on every screen. This file is the tripwire:
/// it fails the build when a screen grows a second competing primary, loses its
/// Title layer, or hand-rolls its own bottom bar instead of the shared one.
///
/// ⚠️ SCOPE BOUNDARY — `apps/customer_app` is OUT OF SCOPE for every check in
/// this file, by explicit product direction:
///   DO NOT rebuild / redesign / change Customer screens, DO NOT duplicate
///   Customer features into the Shopkeeper app. Only shared, technically
///   required, backward-compatible changes may cross that line.
///
/// These scans cover the Shopkeeper app because they enforce ITS contracts. A
/// scan is not an edit, but widening its blast radius into an app we must not
/// touch would make it slower and — worse — could start failing on Customer
/// code, which then tempts someone to "fix" the wrong app. So the boundary is
/// ASSERTED below, not merely assumed.
const List<String> kInScopeRoots = <String>['lib', 'test'];

void main() {
  group('SCOPE — the Customer app is out of scope', () {
    test('no contract scan may reach outside the Shopkeeper app', () {
      // Every scan in this suite (and the button/state/data contract suites)
      // resolves its roots relative to `apps/shopkeeper_app`. If one ever
      // starts walking `../..` it would begin reading the Customer app and
      // failing builds on code this work must not touch.
      final shopkeeperRoot = Directory.current.path.replaceAll('\\', '/');
      expect(
        Directory.current.existsSync(),
        isTrue,
        reason: 'the contract scans are cwd-relative to apps/shopkeeper_app',
      );
      expect(
        shopkeeperRoot,
        isNot(contains('/customer_app')),
        reason:
            'a Shopkeeper contract scan is running from inside the '
            'Customer app — the scope boundary has been crossed',
      );
    });

    test('the roots these scans resolve stay inside the Shopkeeper app', () {
      for (final root in kInScopeRoots) {
        expect(
          root,
          isNot(startsWith('..')),
          reason: '"$root" would escape the Shopkeeper app',
        );
        expect(
          root,
          isNot(contains('customer')),
          reason: 'Customer app is out of scope',
        );
      }
      expect(
        Directory('lib').existsSync(),
        isTrue,
        reason: 'sanity: the Shopkeeper lib/ root resolves',
      );
    });
  });

  group('TOP layer — Back / Title / contextual action', () {
    test('no registered route is a dead end', () {
      // A route registered in `app_router.dart` that NOTHING in `lib/` ever
      // navigates to is a dead end: the screen exists, the URL works, and no
      // user can ever reach it. The real finding was `/expired-offers` —
      // `ExpiredOffersScreen` was fully built and registered, yet a shopkeeper
      // whose offer had finished had no doorway to the history.
      //
      // Counted as "used" when a `Routes.<name>` reference appears anywhere
      // besides the single registration in the router itself. Templates
      // (`…Template`) and non-route constants (`shellTabPaths`) are excluded:
      // they are route-building helpers / data, not navigable destinations.
      final routeNames = File('lib/core/router/route_names.dart')
          .readAsStringSync();
      final router = File('lib/core/router/app_router.dart').readAsStringSync();

      final declared = RegExp(r'static\s+const\s+(\w+)\s*=')
          .allMatches(routeNames)
          .map((m) => m.group(1)!)
          .where((n) => !n.endsWith('Template') && n != 'shellTabPaths')
          .toList();

      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.contains('route_names.dart'),
          )
          .toList();

      final deadEnds = <String>[];
      for (final name in declared) {
        final pattern = RegExp(r'Routes\.' + RegExp.escape(name) + r'\b');
        var inAppRefs = 0;
        for (final file in sources) {
          if (file.path.endsWith('app_router.dart')) continue;
          inAppRefs += pattern.allMatches(file.readAsStringSync()).length;
        }
        if (inAppRefs > 0) continue;
        // Not pushed anywhere. Is it at least a redirect / boot target?
        // 1 = the `buildRoute` registration alone; >1 means the router itself
        // points at it.
        final routerRefs = pattern.allMatches(router).length;
        if (routerRefs <= 1) deadEnds.add(name);
      }

      expect(
        deadEnds,
        isEmpty,
        reason:
            'These routes are registered but nothing navigates to them — a '
            'built screen no user can reach. Wire a doorway (an AppBar action / '
            'list entry), or make the router redirect/boot to it, or drop the '
            'registration.\n${deadEnds.join('\n')}',
      );

      expect(
        router,
        contains('buildRoute'),
        reason: 'sanity: the router really registers routes',
      );
    });
    test('every route is classified by the access gate (deny by default)', () {
      // The redirect's shop gate used to be allow-by-default: a route not named
      // in `needsShop` was simply permitted. That is how a newly registered
      // screen silently becomes reachable with NO shop selected — the guard
      // fails open. The gate is now default-DENY, and that only holds if every
      // registered route sits in exactly one bucket:
      //
      //   handled-earlier | alwaysOpen | needsShop | userScoped
      //
      // Anything unclassified bounces a legitimate user to Home for no reason,
      // so a missing entry must be a visible omission, not an invisible one.
      final router = File('lib/core/router/app_router.dart').readAsStringSync();

      final registered = RegExp(r'buildRoute\(\s*Routes\.(\w+)')
          .allMatches(router)
          .map((m) => m.group(1)!)
          .toSet();

      /// Pulls one bucket out of the redirect by slicing its own block, so the
      /// lists are read from the real source rather than duplicated here.
      Set<String> bucket(String name) {
        final start = router.indexOf('const $name = [');
        if (start < 0) return <String>{};
        final end = router.indexOf('];', start);
        final body = end < 0
            ? router.substring(start)
            : router.substring(start, end);
        return body
            .split('\n')
            .map((l) => RegExp(r'Routes\.(\w+)').firstMatch(l)?.group(1))
            .whereType<String>()
            .toSet();
      }

      final alwaysOpen = bucket('alwaysOpen');
      final needsShop = bucket('needsShop');
      final userScoped = bucket('userScoped');

      // Public/auth destinations are handled by the EARLIER redirect branches
      // (splash hold, signed-out bounce, restricted account), not by the shop
      // gate, so they are exempt from classification here.
      const handledEarlier = <String>{
        'splash',
        'welcome',
        'login',
        'register',
        'forgotPassword',
        'resetPassword',
        'phoneOtp',
        'accountStatus',
      };

      expect(alwaysOpen, isNotEmpty, reason: 'alwaysOpen parsed');
      expect(needsShop, isNotEmpty, reason: 'needsShop parsed');
      expect(userScoped, isNotEmpty, reason: 'userScoped parsed');

      final classified = <String>{...alwaysOpen, ...needsShop, ...userScoped};
      final unclassified =
          registered.difference(classified).difference(handledEarlier);

      expect(
        unclassified,
        isEmpty,
        reason: 'These routes are registered but appear in NO access bucket, so '
            'the default-DENY guard will bounce a signed-in user to Home. Add '
            'each to alwaysOpen / needsShop / userScoped deliberately.\n'
            '${unclassified.join('\n')}',
      );

      // A route cannot need a shop AND be user-scoped: the gate reads the
      // lists in order, so an overlap means one list is dead code.
      final overlap = needsShop.intersection(userScoped);
      expect(
        overlap,
        isEmpty,
        reason: 'A route is in two buckets, so one entry can never be reached.\n'
            '${overlap.join('\n')}',
      );
    });

    test('every screen with a Scaffold declares an AppBar', () {
      // Full-bleed surfaces are the ONLY sanctioned exceptions, and each is a
      // deliberate composition decision rather than an omission:
      //
      //   splash        — the launch surface, shown before any chrome exists;
      //   welcome       — the approved auth entry (illustration + one CTA);
      //   accountStatus — a dead-end gate: a Back affordance would be a lie,
      //                   and its headline IS the title.
      const fullBleed = {
        'splash_screen.dart',
        'welcome_screen.dart',
        'account_status_screen.dart',
      };

      final offenders = <String>[];
      for (final file in _libFiles()) {
        if (!file.path.endsWith('_screen.dart')) continue;
        final name = file.path.split(Platform.pathSeparator).last;
        if (fullBleed.contains(name)) continue;
        final source = file.readAsStringSync();
        if (source.contains('Scaffold(') && !source.contains('appBar:')) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A screen renders a Scaffold with no Top layer. Add an AppBar '
            '(title, plus Back via the router, plus any contextual action), or '
            'add the file to `fullBleed` with a reason.\n${offenders.join('\n')}',
      );
    });

    test('the scan actually resolved screen files', () {
      // A hierarchy test whose file list is empty passes for the wrong reason.
      final screens = _libFiles()
          .where((f) => f.path.endsWith('_screen.dart'))
          .toList();
      expect(screens.length, greaterThan(40));
    });
  });

  group('BOTTOM layer renders exactly ONE primary', () {
    testWidgets('a lone primary is one filled button and no outline', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        PrimaryCtaBar(primaryLabel: 'Apply import', onPrimary: () {}),
      );

      expect(find.widgetWithText(FilledButton, 'Apply import'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('the secondary is DEMOTED, never a second primary', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        PrimaryCtaBar(
          primaryLabel: 'Sign out',
          onPrimary: () {},
          secondaryLabel: 'Stay signed in',
          onSecondary: () {},
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign out'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Stay signed in'),
        findsOneWidget,
      );
    });

    testWidgets('loading disables BOTH actions and shows progress copy', (
      tester,
    ) async {
      var fired = 0;
      await _pumpBar(
        tester,
        PrimaryCtaBar(
          primaryLabel: 'Sign out',
          onPrimary: () => fired++,
          loading: true,
          loadingLabel: 'Signing out',
          secondaryLabel: 'Stay signed in',
          onSecondary: () => fired++,
        ),
      );

      expect(find.text('Signing out'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(fired, 0, reason: 'one tap must never start two operations');
    });

    testWidgets('a destructive primary keeps its single-primary hierarchy', (
      tester,
    ) async {
      await _pumpBar(
        tester,
        PrimaryCtaBar(
          primaryLabel: 'Delete offer',
          onPrimary: () {},
          destructive: true,
          secondaryLabel: 'Cancel',
          onSecondary: () {},
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    test('the API has ONE primary slot and no list of buttons', () {
      final source = File('lib/core/ui/primary_cta_bar.dart')
          .readAsStringSync();

      expect(
        source,
        isNot(contains('List<Widget>')),
        reason: 'A button list is how competing primaries get in.',
      );
      expect(
        source,
        contains('required this.primaryLabel'),
        reason: 'the primary is required; a bar cannot be built with no CTA',
      );
      expect(
        RegExp(r'final\s+String\?\s+secondaryLabel').hasMatch(source),
        isTrue,
        reason: 'the secondary is nullable; it is optional by contract',
      );
    });
  });

  group('BOTTOM layer adoption', () {
    test('the logout confirmation pins its CTAs instead of floating them', () {
      final source = File(
        'lib/features/account/presentation/screens/'
        'logout_confirmation_screen.dart',
      ).readAsStringSync();

      expect(source, contains('bottomNavigationBar: PrimaryCtaBar('));
      expect(source, contains("Key('logout_confirm_button')"));
      expect(source, contains("Key('logout_cancel_button')"));
      expect(source, isNot(contains('FilledButton(')));
      expect(source, isNot(contains('OutlinedButton(')));
    });

    test('every screen bottom bar is the SHARED bar, never hand-rolled', () {
      // The recurring failure is not a missing bar but a bespoke one: a
      // hand-rolled Material+SafeArea+Padding+FilledButton footer that quietly
      // renders a second filled primary next to whatever the body already
      // offers. One component makes that unrepresentable, so forbid the
      // alternative outright.
      //
      // `shopkeeper_shell.dart` is exempt: its bottom layer is the tab bar
      // (`NavigationBar`), which is navigation, not a CTA.
      const exempt = {'shopkeeper_shell.dart'};

      final offenders = <String>[];
      for (final file in _libFiles()) {
        if (!file.path.endsWith('_screen.dart')) continue;
        final name = file.path.split(Platform.pathSeparator).last;
        if (exempt.contains(name)) continue;
        final source = file.readAsStringSync();
        if (!source.contains('bottomNavigationBar:')) continue;
        if (!source.contains('PrimaryCtaBar(')) offenders.add(file.path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A screen hand-rolls its bottom bar. Use `PrimaryCtaBar` so the '
            'primary stays filled and there is room for at most one demoted '
            'secondary.\n${offenders.join('\n')}',
      );
    });

    test('the shared bar is what the remaining CTAs actually render', () {
      // Sanity on the guard above: if every screen had deleted its bar, the
      // test would pass for the wrong reason. Confirm the pinned screens still
      // carry the keys their tests tap.
      final setup = File(
        'lib/features/pos/presentation/screens/pos_connection_setup_screen.dart',
      ).readAsStringSync();
      final sync = File(
        'lib/features/pos/presentation/screens/pos_sync_screen.dart',
      ).readAsStringSync();
      final offer = File(
        'lib/features/pricing/presentation/screens/create_offer_screen.dart',
      ).readAsStringSync();

      expect(setup, contains("Key('pos-setup-submit')"));
      expect(setup, contains("Key('pos-setup-sync-now')"));
      expect(setup, contains("Key('pos-setup-done')"));
      expect(sync, contains("Key('pos-sync-start')"));
      expect(offer, contains("Key('offer-submit')"));

      // The bars are thin now — each just delegates, so a screen cannot smuggle
      // a second filled button back in through its footer.
      for (final source in [setup, sync, offer]) {
        expect(source, isNot(contains('FilledButton(')));
        expect(source, isNot(contains('OutlinedButton(')));
      }
    });
  });
}

List<File> _libFiles() =>
    Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

Future<void> _pumpBar(WidgetTester tester, Widget bar) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: const SizedBox.shrink(), bottomNavigationBar: bar),
    ),
  );
}
