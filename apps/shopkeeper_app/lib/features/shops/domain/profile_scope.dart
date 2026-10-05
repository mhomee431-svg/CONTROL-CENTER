import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ── THE "SINGLE PROFILE" SWITCH ───────────────────────────────────────────
///
/// The current UI assumes **ONE shopkeeper → ONE profile → ONE shop/business**.
///
/// Multi-business is a FUTURE phase. Until it ships, the app must not offer to
/// switch, add or manage multiple businesses: the flows for those do not exist
/// yet and a half-built picker is worse than none. Screens therefore read
/// [multiShopEnabledProvider] — the single chokepoint, exactly like
/// `kEnabledAuthMethods` is for auth methods — instead of hardcoding the
/// check, so flipping this one constant turns every multi-shop affordance back
/// on at once:
///
///   * the `Switch shop` button on the 403 / permission-denied states
///     (`dashboard_screen.dart`, `products_screen.dart`);
///   * the Account tab's `My business` entry (which opens the picker);
///   * the `/shops` screen's list-and-select behaviour;
///   * the router sending a shop-bearing account to `/shops` to choose one.
///
/// NOTHING is deleted. `ShopsScreen`, `ShopsController`, `listMyShops`, the
/// `/shops` route and `SelectedShopNotifier` all stay implemented — the
/// single-shop model already *runs* on them: the primary shop is auto-selected
/// into `selectedShopProvider` right after login / session restore, which is
/// what makes "one profile, one business" true without a picker.
///
/// Enabling multi-business later is deliberately a ONE-LINE change here (plus
/// the future picker UI), because no screen hardcodes the assumption.
const bool kMultiShopEnabled = false;

/// Runtime read of [kMultiShopEnabled]. Screens `watch` this (or the future
/// build flag behind it) so the visible flow changes without touching widgets —
/// and so a test can prove both the current and the future behaviour.
final multiShopEnabledProvider = Provider<bool>((ref) => kMultiShopEnabled);
