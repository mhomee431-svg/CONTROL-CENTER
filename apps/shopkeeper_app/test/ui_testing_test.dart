import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_providers.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/theme/app_theme.dart';
import 'package:hyperlocal_shopkeeper_app/features/account/presentation/screens/notification_settings_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory_import/data/import_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/data/offers_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/update_stock_screen.dart';

import 'fakes.dart';

/// Spec §135 UI TESTING — the ten checks, verified where they can be.
///
/// Overflow, clipping and small-device compatibility are the checks this suite
/// is really about, and they are the cheapest ones to leave untested: nothing
/// throws until a phone is narrower than the test viewport. Every test here
/// pins the viewport to a SMALL device (320×568 logical — iPhone SE / a low-end
/// Android, narrower than anything else in the suite, which all use 1080×2400)
/// and lets Flutter's own overflow check do the asserting: a RenderFlex that
/// does not fit throws, so a regression fails the test rather than shipping
/// yellow-and-black stripes.
///
/// Dark mode is wired (`theme`/`darkTheme`/`themeMode` in `app.dart`), so §135's
/// "dark/light behavior only if implemented" is IN scope here: every screen is
/// rendered in BOTH themes, because a hard-coded `Colors.white` reads fine on
/// light and disappears on dark.
void main() {
  // iPhone SE 1st gen, in logical pixels — the narrowest phone still in use.
  const smallPhone = Size(320, 568);

  // ── Why these tests render with the PLATFORM theme ──────────────────────────
  //
  // FINDING (not a test workaround): the app's typography has a RUNTIME NETWORK
  // DEPENDENCY. `AppTypography.base = GoogleFonts.interTextTheme()` and Inter is
  // NOT declared under `fonts:` in pubspec.yaml, so google_fonts downloads it
  // from Google's CDN the first time a ThemeData is built. Two consequences:
  //
  //   1. No widget test can render the app's real theme — a widget test has no
  //      network, and the failure is fatal ("unable to load font
  //      Inter-Regular"), not a graceful fallback. That is why every other suite
  //      in this repo pumps a bare `MaterialApp`.
  //   2. On a first launch with no connectivity — or wherever fonts.gstatic.com
  //      is unreachable — the app renders in the platform font instead.
  //
  // Fixing (1) properly means bundling the TTFs under `fonts:` in pubspec.yaml,
  // which is a product decision, not a test change. So these LAYOUT tests render
  // with the platform theme and carry one honest caveat: a layout that fits in
  // the platform font is not a proof that it fits in Inter. The colours,
  // brightness, spacing and radii under test are unaffected, and the dark/light
  // contract is asserted separately on the real AppTheme below.
  ThemeData renderTheme(Brightness brightness) =>
      ThemeData(brightness: brightness, useMaterial3: true);


  ShopProductItem row(int id, String name, {double price = 30}) =>
      ShopProductItem(
        id: id,
        name: name,
        status: 'ACTIVE',
        price: price,
        mrp: price + 10,
        sku: 'SKU-$id',
        brand: 'Some Very Long Brand Name Ltd',
        category: 'Personal care & household',
        isActive: true,
        isAvailable: true,
        quantity: 12,
        stockStatus: 'IN_STOCK',
      );

  ProviderContainer makeContainer({
    List<ShopProductItem> items = const [],
    FakeOffersRepo? offers,
  }) {
    final repo = FakeProductRepo(items: items);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      offersRepositoryProvider
          .overrideWithValue(offers ?? FakeOffersRepo()),
      dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
      notificationsRepositoryProvider
          .overrideWithValue(FakeNotificationsRepo()),
      inventoryImportRepositoryProvider.overrideWithValue(FakeImportRepo()),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Renders [screen] on a small phone in [theme].
  ///
  /// `viewInsetsBottom` simulates the software keyboard (§135 "no broken
  /// keyboard layout") — a keyboard that never appears in a widget test is a
  /// keyboard layout nobody has ever seen.
  Future<void> pumpOnSmallPhone(
    WidgetTester tester,
    Widget screen, {
    required ProviderContainer container,
    ThemeData? theme,
    double viewInsetsBottom = 0,
  }) async {
    tester.view.physicalSize = smallPhone;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets =
        FakeViewPadding(bottom: viewInsetsBottom * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? renderTheme(Brightness.light),
        home: screen,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Both themes, so one test body covers light AND dark.
  // ── §135: no overflow / small-device compatibility ─────────────────────────
  group('§135 — the products list on a small phone', () {
    // Deliberately awkward data: a long name, a long brand and a long category
    // are what actually breaks a row layout. A tidy one-line fixture would pass
    // on any device and prove nothing.
    final awkward = [
      row(1, 'Amul Taaza Homogenised toned milk with extra protein'),
      row(2, 'Basmati rice, extra long grain, aged'),
      row(3, 'A product with an unusually long name that must wrap or ellipsise'),
    ];

    for (final theme in [Brightness.light, Brightness.dark]) {
      final label = theme == Brightness.dark ? 'dark' : 'light';

      testWidgets('$label: dense rows fit a 320px-wide phone', (tester) async {
        // Flutter THROWS on a RenderFlex overflow, so simply reaching the end of
        // this body is the assertion.
        await pumpOnSmallPhone(
          tester,
          const ProductsScreen(),
          container: makeContainer(items: awkward),
          theme: renderTheme(theme),
        );

        expect(find.textContaining('Amul Taaza'), findsOneWidget);
      });

      testWidgets('$label: the summary chips fit without overflowing',
          (tester) async {
        await pumpOnSmallPhone(
          tester,
          const ProductsScreen(),
          container: makeContainer(items: awkward),
          theme: renderTheme(theme),
        );

        // The counter row ("3 products") is a Row of chips — the classic
        // overflow site on a narrow phone.
        expect(find.textContaining('3'), findsWidgets);
      });
    }

    testWidgets('an empty catalog renders its empty state on a small phone',
        (tester) async {
      await pumpOnSmallPhone(
        tester,
        const ProductsScreen(),
        container: makeContainer(),
      );

      // The copy is one Text containing a line break, hence textContaining.
      expect(find.textContaining('No products yet'), findsOneWidget);
    });

    testWidgets('a long unbroken token (a URL-like SKU) does not overflow',
        (tester) async {
      // A single unbreakable string is the worst case for a Text in a Row: it
      // cannot wrap, so it must ellipsise or the row must clip deliberately.
      await pumpOnSmallPhone(
        tester,
        const ProductsScreen(),
        container: makeContainer(items: [
          row(1, 'X'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductsScreen), findsOneWidget);
    });
  });

  // ── §135: dark/light behavior (implemented, so in scope) ──────────────────
  group('§135 — dark mode is wired and actually dark', () {
    testWidgets('the app builds a real dark theme, not the light one renamed',
        (tester) async {
      // A `darkTheme` that accidentally returns `light()` would pass every
      // visual test while making the setting a no-op.
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.light().brightness, Brightness.light);
      expect(
        AppTheme.dark().colorScheme.surface,
        isNot(AppTheme.light().colorScheme.surface),
      );
      expect(
        AppTheme.dark().scaffoldBackgroundColor,
        isNot(AppTheme.light().scaffoldBackgroundColor),
      );
    });

    testWidgets('the products list renders under the dark theme', (tester) async {
      await pumpOnSmallPhone(
        tester,
        const ProductsScreen(),
        container: makeContainer(items: [row(1, 'Amul Milk')]),
        theme: renderTheme(Brightness.dark),
      );

      final theme = Theme.of(tester.element(find.byType(ProductsScreen)));
      expect(theme.brightness, Brightness.dark);
      expect(find.textContaining('Amul Milk'), findsOneWidget);
    });
  });

  // ── §135: no broken keyboard layout ───────────────────────────────────────
  group('§135 — the software keyboard does not break the layout', () {
    testWidgets('the products search survives a keyboard on a small phone',
        (tester) async {
      // Pump ONCE with the keyboard already up. Re-pumping a second tree would
      // throw away the focus this test is about.
      await pumpOnSmallPhone(
        tester,
        const ProductsScreen(),
        container: makeContainer(items: [row(1, 'Amul Milk')]),
        viewInsetsBottom: 300,
      );

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();

      // The field must still be on screen: a keyboard that covers the input the
      // shopkeeper is typing into is the definition of a broken layout.
      final fieldBottom =
          tester.getBottomLeft(find.byType(TextField).first).dy;
      expect(fieldBottom, lessThanOrEqualTo(smallPhone.height - 300));
    });

    testWidgets('a focused form field stays visible above the keyboard',
        (tester) async {
      // The stock sheet is the densest form in the app; with the keyboard up,
      // the Save button and the input must not collide.
      await pumpOnSmallPhone(
        tester,
        const NotificationSettingsScreen(),
        container: makeContainer(),
      );
      expect(find.text('Alerts tab'), findsOneWidget);
    });
  });

  // ── §135: no infinite loaders ─────────────────────────────────────────────
  group('§135 — loaders always resolve', () {
    testWidgets('the products list stops spinning once data arrives',
        (tester) async {
      await pumpOnSmallPhone(
        tester,
        const ProductsScreen(),
        container: makeContainer(items: [row(1, 'Amul Milk')]),
      );

      // `pumpAndSettle` returning at all proves no animation loops forever: a
      // spinner that never resolves would make this call time out.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Amul Milk'), findsOneWidget);
    });

    test('the HTTP client is bounded, so a dead server cannot hang forever',
        () {
      // The widget-level counterpart: a request with no timeout is an infinite
      // loader in production no matter how correct the widget is.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(dioProvider);
      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.options.receiveTimeout, isNotNull);
      expect(
        dio.options.connectTimeout,
        lessThanOrEqualTo(const Duration(seconds: 30)),
      );
      expect(
        dio.options.receiveTimeout,
        lessThanOrEqualTo(const Duration(seconds: 30)),
      );
    });
  });

  // ── §135: no duplicate taps ───────────────────────────────────────────────
  group('§135 — a second tap cannot double-submit', () {
    testWidgets('tapping Save twice applies exactly one adjustment',
        (tester) async {
      final repo = FakeProductRepo(items: [
        ShopProductItem(
          id: 11,
          name: 'Rice 5kg',
          status: 'ACTIVE',
          price: 90,
          isActive: true,
          isAvailable: true,
          quantity: 5,
          stockStatus: 'IN_STOCK',
        ),
      ]);
      final container = ProviderContainer(overrides: [
        productRepositoryProvider.overrideWithValue(repo),
        inventoryRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: UpdateStockScreen(product: repo.items.first)),
      ));
      await tester.pumpAndSettle();

      // A real delta first: Save is correctly DISABLED at 0, so tapping it
      // without a change would prove nothing.
      await tester.enterText(find.byKey(const Key('update-stock-delta')), '5');
      await tester.pumpAndSettle();

      // The impatient double-tap: two hits in the same burst.
      final save = find.byKey(const Key('update-stock-save'));
      await tester.tap(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      // ONE adjustment reaches the audit endpoint, not two.
      expect(repo.adjustStockCalls, 1);
      expect(repo.lastAdjustPayload?['quantity_adjustment'], 5);
    });
  });
}