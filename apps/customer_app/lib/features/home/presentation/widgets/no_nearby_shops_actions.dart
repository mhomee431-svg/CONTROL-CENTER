import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/location/discovery_radius.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../dialogs/area_pin_dialog.dart';

/// The three recoveries, as data.
///
/// Split from [NoNearbyShopsActions] because that widget carries its own
/// `Center` + `SingleChildScrollView` chrome. A screen that already owns a
/// scroll view (like `ComingSoonScreen`) must NOT nest a second one inside it,
/// so it calls this to reuse the same recoveries inside its own layout — same
/// three buttons, same labels, same availability rule, without the extra
/// scroll view.
///
/// A recovery appears only when it can actually be taken: the widen step
/// disappears once the ladder is exhausted at the server's `le=100` cap,
/// because a button that cannot do anything is worse than no button.
List<EmptyStateAction> buildNoNearbyShopsActions({
  required BuildContext context,
  required double? radiusKm,
  required VoidCallback onWidenRadius,
  required String keyPrefix,
}) {
  return [
    if (canWidenDiscoveryRadius(radiusKm))
      EmptyStateAction(
        key: Key('${keyPrefix}SearchWider'),
        icon: Icons.radar_outlined,
        label: nextDiscoveryRadiusLabel(radiusKm),
        onTap: onWidenRadius,
      ),
    EmptyStateAction(
      key: Key('${keyPrefix}ChangeLocation'),
      icon: Icons.place_outlined,
      label: 'Change location',
      onTap: () => context.push('/select-location'),
    ),
    EmptyStateAction(
      key: Key('${keyPrefix}SearchAnotherArea'),
      icon: Icons.pin_drop_outlined,
      label: 'Search another area',
      onTap: () => showAreaPinDialog(
        context,
        onPin: (pin) => context.push('/search-results-by-pin/$pin'),
      ),
    ),
  ];
}
/// The one "no nearby shops" empty state, with the three recoveries the backend
/// genuinely answers.
///
/// WHY ONE SHARED WIDGET
/// ---------------------
/// This state used to be spelled out twice — once in `NearbyShopsSection` and
/// once in `ComingSoonScreen` — and the two copies had already drifted: the
/// section offered all three recoveries while `ComingSoonScreen` offered only
/// two, so a customer who reached the empty state by one path was offered a
/// strictly worse recovery than the customer who reached it by another. Both
/// now render this, so there is one rule and one set of keys.
///
/// Each recovery maps to something the backend actually does:
/// - **widen**     → re-reads the same query with a larger `radius_km`
///                  (real server-side filtering, never a client-side filter).
/// - **change location** → `/select-location`, which sets the customer's own
///                  coordinates and re-reads the feed.
/// - **search another area** → `/search-results-by-pin/:pin`, resolving
///                  `GET /shops/nearby?pincode=`.
///
/// The widen action is rendered ONLY while a wider step exists inside the
/// server's `le=100` cap. At the ceiling it is omitted rather than rendered
/// dead — a button that cannot do anything is worse than no button.
class NoNearbyShopsActions extends StatelessWidget {
  /// The radius currently in force. Null means "whatever the backend defaults
  /// to", which is also where the ladder starts measuring from.
  final double? radiusKm;

  /// Steps the caller's radius provider to the next notch. Passed in rather
  /// than read from a provider here because the home feed and the product
  /// offers screen own separate radius state.
  final VoidCallback onWidenRadius;

  /// Namespaces the action keys so two instances on screen (or in the same
  /// test tree) stay individually addressable: `<keyPrefix>ChangeLocation`.
  final String keyPrefix;

  /// Overrides the headline. Defaults to the shared "no nearby shops" copy.
  final String title;

  /// Overrides the supporting line.
  final String? message;

  const NoNearbyShopsActions({
    super.key,
    required this.radiusKm,
    required this.onWidenRadius,
    required this.keyPrefix,
    this.title = 'No nearby shops found',
    this.message =
        'We could not find any shops around you. Look further afield, or '
        'check a different area.',
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateView(
      icon: Icons.storefront_outlined,
      title: title,
      message: message,
      actions: buildNoNearbyShopsActions(
        context: context,
        radiusKm: radiusKm,
        onWidenRadius: onWidenRadius,
        keyPrefix: keyPrefix,
      ),
    );
  }
}