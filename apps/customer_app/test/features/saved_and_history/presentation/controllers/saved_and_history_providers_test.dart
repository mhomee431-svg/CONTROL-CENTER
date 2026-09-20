import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_client.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:hyperlocal_app/features/saved_and_history/data/api_saved_and_history_repository.dart';
import 'package:hyperlocal_app/features/saved_and_history/data/local_saved_and_history_repository.dart';
import 'package:hyperlocal_app/features/saved_and_history/domain/models/storage_models.dart';
import 'package:hyperlocal_app/features/saved_and_history/domain/saved_and_history_repository.dart';
import 'package:hyperlocal_app/features/saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'saved_and_history_providers_test.mocks.dart';

@GenerateMocks([ApiClient])

/// Auth controller whose status is controlled by the test so repository
/// selection can be flipped between logged-in / logged-out states.
class FakeAuthController extends AuthController {
  FakeAuthController(this.statusFn);
  final AuthStatus Function() statusFn;

  @override
  AuthState build() => AuthState(status: statusFn());
}

void main() {
  late InMemoryStorageDriver driver;
  late ProviderContainer container;
  AuthStatus currentStatus = AuthStatus.guest;

  setUp(() {
    driver = InMemoryStorageDriver();
    currentStatus = AuthStatus.guest;
    // Successful no-op backend by default (no network in unit tests).
    final api = MockApiClient();
    when(api.post(any)).thenAnswer((_) async => null);
    when(api.delete(any)).thenAnswer((_) async => null);
    when(api.get(any)).thenAnswer((_) async => null);
    container = ProviderContainer(
      overrides: [
        localStorageDriverProvider.overrideWithValue(driver),
        authControllerProvider.overrideWith(
          () => FakeAuthController(() => currentStatus),
        ),
        apiClientProvider.overrideWithValue(api),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// Simulates an auth transition: flips the fake controller's status and
  /// forces its rebuild so dependent providers observe the new state.
  void switchTo(AuthStatus status) {
    currentStatus = status;
    container.invalidate(authControllerProvider);
  }

  SavedProductItem product(String id) => SavedProductItem(
        productId: id,
        name: 'Product $id',
        brand: 'Brand',
        lowestPrice: 999,
        imageUrl: '',
        savedAt: DateTime.now(),
      );

  group('repository selection follows auth state', () {
    test('guests use the fully-local repository', () {
      expect(container.read(savedAndHistoryRepositoryProvider),
          isA<LocalSavedAndHistoryRepository>());
    });

    test('authenticated users use the backend-synced repository', () {
      switchTo(AuthStatus.authenticated);

      expect(container.read(savedAndHistoryRepositoryProvider),
          isA<ApiSavedAndHistoryRepository>());
    });

    test('logout switches back to the local repository', () {
      switchTo(AuthStatus.authenticated);
      expect(container.read(savedAndHistoryRepositoryProvider),
          isA<ApiSavedAndHistoryRepository>());

      switchTo(AuthStatus.unauthenticated);
      expect(container.read(savedAndHistoryRepositoryProvider),
          isA<LocalSavedAndHistoryRepository>());
    });
  });


  group('logged-out behavior', () {
    test('saved products are stored locally as pending sync', () async {
      await container
          .read(savedProductsNotifierProvider.notifier)
          .toggleSave(product('guest-1'));

      final stored =
          await LocalSavedAndHistoryRepository(driver).getSavedProducts();
      expect(stored.single.productId, 'guest-1');
      expect(stored.single.isSynced, isFalse);

      // The list notifier reflects the change immediately.
      final listed = await container.read(savedProductsNotifierProvider.future);
      expect(listed.single.productId, 'guest-1');
    });

    test('search history records queries with dedupe through the notifier',
        () async {
      final notifier = container.read(recentSearchesNotifierProvider.notifier);
      await notifier.addQuery('Headphones');
      await notifier.addQuery('headphones');
      await notifier.addQuery('earbuds');

      final searches =
          await container.read(recentSearchesNotifierProvider.future);
      expect(searches.length, 2);
      expect(searches.first.query, 'earbuds');

      await notifier.removeQuery('headphones');
      expect((await container.read(recentSearchesNotifierProvider.future)).length,
          1);

      await notifier.clearAll();
      expect(
          await container.read(recentSearchesNotifierProvider.future), isEmpty);
    });

    test('recently viewed products and shops are recorded and removable',
        () async {
      await container
          .read(recentlyViewedNotifierProvider.notifier)
          .addProduct(RecentlyViewedItem(
            productId: 'p1',
            name: 'P1',
            imageUrl: '',
            price: 10,
            viewedAt: DateTime.now(),
          ));
      await container
          .read(recentlyViewedShopsNotifierProvider.notifier)
          .addShop(RecentlyViewedShopItem(
            shopId: 's1',
            name: 'S1',
            address: '',
            imageUrl: '',
            rating: 4,
            viewedAt: DateTime.now(),
          ));

      await container
          .read(recentlyViewedNotifierProvider.notifier)
          .removeProduct('p1');
      await container
          .read(recentlyViewedShopsNotifierProvider.notifier)
          .removeShop('s1');

      expect(await container.read(recentlyViewedNotifierProvider.future),
          isEmpty);
      expect(await container.read(recentlyViewedShopsNotifierProvider.future),
          isEmpty);
    });
  });

  group('login / logout transitions keep history consistent', () {
    test('device-level history survives a login and a logout', () async {
      // While logged out, the customer searches for something.
      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('power banks');

      // Log in: history must still be readable from the new repository.
      switchTo(AuthStatus.authenticated);
      var searches =
          await container.read(recentSearchesNotifierProvider.future);
      expect(searches.single.query, 'power banks');

      // Log out again: device-local history is intentionally retained.
      switchTo(AuthStatus.unauthenticated);
      searches = await container.read(recentSearchesNotifierProvider.future);
      expect(searches.single.query, 'power banks');
    });


    test('saved favorites made while logged out are cleared once synced',
        () async {
      // Guest saves a favorite.
      await container
          .read(savedProductsNotifierProvider.notifier)
          .toggleSave(product('guest-1'));

      // Simulate a completed login-sync (as performed on login):
      // push then clear the local queue.
      switchTo(AuthStatus.authenticated);
      await container.read(savedAndHistoryRepositoryProvider).syncPendingSaves();

      final queueAfterSync =
          await LocalSavedAndHistoryRepository(driver).getSavedProducts();
      expect(queueAfterSync, isEmpty);
    });
  });
}

