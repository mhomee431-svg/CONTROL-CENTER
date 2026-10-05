import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/business_profile_models.dart';
import '../../domain/shop_details_repository.dart';
import 'shop_details_controller.dart';

/// The business side of a shop profile, resolved from its capabilities.
///
/// WHY THIS IS A SEPARATE PROVIDER
/// ------------------------------
/// The identity request (`shopDetailsProvider`) must stay fast for every
/// business — it is what the header, contact and hours render from. A menu or a
/// provider profile is a SECOND request that only two kinds of business need, so
/// it resolves here, watching the identity and branching on its capabilities:
///
///  * `menu` -> the restaurant profile behind the shop (or nothing, when the
///    backend answers 404 — a normal outcome, not an error);
///  * `service_profile` -> the transport / travel provider behind the shop;
///  * otherwise -> nothing beyond the inventory grid.
///
/// Watches (not reads) the identity provider, so the SAME in-flight request is
/// shared rather than fired twice: the route the screen already opened.
final shopBusinessProfileProvider = FutureProvider.autoDispose
    .family<BusinessProfile, String>((ref, shopId) async {
      final shop = await ref.watch(shopDetailsProvider(shopId).future);
      final capabilities = shop.effectiveCapabilities;
      final repository = ref.watch(shopDetailsRepositoryProvider);

      if (capabilities.supportsMenu) {
        final restaurant = await repository.getRestaurantProfile(shopId);
        if (restaurant == null) return const BusinessProfile.none();
        return BusinessProfile.restaurant(restaurant);
      }
      if (capabilities.supportsServiceProfile) {
        final service = await repository.getTransportServiceProfile(shopId);
        if (service == null) return const BusinessProfile.none();
        return BusinessProfile.service(service);
      }
      return const BusinessProfile.none();
    });

/// Exactly one business-side surface for a shop: a product shop has none here
/// (its surface is the inventory grid on the profile), a restaurant has its
/// menu, a service provider has its profile. A sealed type so a view adding a
/// new case fails the build at the one switch that renders it.
///
/// Deliberately NOT a cart / booking / delivery state: none of those live here.
sealed class BusinessProfile {
  const BusinessProfile();

  const factory BusinessProfile.none() = BusinessProfileNone;
  const factory BusinessProfile.restaurant(RestaurantProfile restaurant) =
      BusinessProfileRestaurant;
  const factory BusinessProfile.service(TransportServiceProfile service) =
      BusinessProfileService;
}

/// No business-side surface: a product shop, or a capability whose record the
/// backend has not published yet.
final class BusinessProfileNone extends BusinessProfile {
  const BusinessProfileNone();
}

/// The restaurant (with its display-only menu) behind this shop.
final class BusinessProfileRestaurant extends BusinessProfile {
  final RestaurantProfile restaurant;
  const BusinessProfileRestaurant(this.restaurant);
}

/// The transport / travel provider behind this shop.
final class BusinessProfileService extends BusinessProfile {
  final TransportServiceProfile service;
  const BusinessProfileService(this.service);
}
