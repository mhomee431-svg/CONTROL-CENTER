import '../../../../core/utils/money.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../customer/domain/customer_repository.dart';
import '../../../customer/domain/models/customer_models.dart';
import '../../../saved_and_history/domain/models/storage_models.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../../domain/home_repository.dart';
import '../../domain/models/home_data.dart';
import 'home_radius_controller.dart';

/// The home feed: categories, popular products, nearby shops, recent searches.
///
/// The recovery action for "no nearby shops" widens [homeSearchRadiusProvider]
/// and invalidates THIS provider, so the widening re-reads through exactly one
/// code path — the same repository call, the same coordinates, only a wider
/// `radius_km`. The first load passes null, which is what leaves the backend's
/// own default in charge.
final homeControllerProvider = FutureProvider.autoDispose<HomeData>((
  ref,
) async {
  final radiusKm = ref.watch(homeSearchRadiusProvider);
  final repo = ref.watch(homeRepositoryProvider);
  // Best-effort coordinates: when the customer granted location access or
  // picked a manual location, the backend ranks nearby content by distance.
  final location = ref.watch(locationControllerProvider).location;
  final hasCoords = location != null && location.hasValidCoordinates;
  return repo.fetchHomeFeed(
    latitude: hasCoords ? location.latitude : null,
    longitude: hasCoords ? location.longitude : null,
    radiusKm: radiusKm,
  );
});

/// Customer-specific home content, sourced exclusively from the customer's own
/// account data (saved products/shops and recently-viewed products).
///
/// Every field is a list of real records. Nothing here is ever synthesised:
/// when the backend has nothing, the list is simply empty and the matching
/// section is not rendered.
class HomePersonalization {
  final List<SavedProductItem> savedProducts;
  final List<SavedShopItem> savedShops;
  final List<RecentProduct> recentlyViewed;

  const HomePersonalization({
    this.savedProducts = const [],
    this.savedShops = const [],
    this.recentlyViewed = const [],
  });

  /// The "general discovery" state used for guests and brand-new customers
  /// who have no history yet — identical to an empty personalised feed.
  const HomePersonalization.empty()
    : savedProducts = const [],
      savedShops = const [],
      recentlyViewed = const [];
}

/// Personalisation for the signed-in customer.
///
/// Guests and new users resolve to [HomePersonalization.empty] so the home
/// screen falls back to pure general discovery. Each source is fetched
/// independently and independently fault-tolerant: one failing endpoint hides
/// only its own section rather than blanking the whole personalisation block,
/// and a failure can never be papered over with invented content.
final homePersonalizationProvider =
    FutureProvider.autoDispose<HomePersonalization>((ref) async {
      final auth = ref.watch(authControllerProvider);
      if (auth.status != AuthStatus.authenticated) {
        return const HomePersonalization.empty();
      }

      Future<List<T>> bestEffort<T>(Future<List<T>> Function() fetch) async {
        try {
          return await fetch();
        } catch (_) {
          // Network/auth failure: treat as "no data" so the section hides.
          return const [];
        }
      }

      final savedAndHistory = ref.read(savedAndHistoryRepositoryProvider);
      final customer = ref.read(customerRepositoryProvider);

      // Kick all three off together; each is guarded on its own.
      final savedProducts = bestEffort(savedAndHistory.getSavedProducts);
      final savedShops = bestEffort(savedAndHistory.getSavedShops);
      final recentViews = bestEffort(customer.getRecentlyViewed);

      return HomePersonalization(
        savedProducts: await savedProducts,
        savedShops: await savedShops,
        recentlyViewed: await recentViews,
      );
    });

/// Maps a saved product onto the shared [Product] card model.
///
/// The saved-products endpoint returns a single lowest price rather than a
/// range, so that is shown alone. A missing price renders as an empty string
/// instead of a fabricated range.
Product savedProductToCard(SavedProductItem item) => Product(
  id: item.productId,
  name: item.name,
  brand: item.brand,
  imageUrl: item.imageUrl,
  priceRange: item.lowestPrice > 0 ? '₹${formatInr(item.lowestPrice)}' : '',
);

/// Maps a backend recently-viewed record onto the shared [Product] card model.
///
/// The recently-viewed endpoint carries no price or brand, so those stay
/// empty rather than being invented.
Product recentProductToCard(RecentProduct item) => Product(
  id: item.productMasterId.toString(),
  name: item.name,
  brand: '',
  imageUrl: item.imageUrl ?? '',
  priceRange: '',
);
