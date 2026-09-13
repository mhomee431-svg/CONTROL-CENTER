import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth_models.dart';

/// The shop whose business resources are currently being managed.
///
/// Single-shop model: the account has at most ONE business, auto-selected
/// right after login/restore ([AuthController._syncPrimaryShop]). The
/// notifier stays so a future multi-shop rewrite can extend selection
/// without touching screens.
class SelectedShopNotifier extends Notifier<ShopSummary?> {
  @override
  ShopSummary? build() => null;

  void select(ShopSummary? shop) => state = shop;
}

final selectedShopProvider =
    NotifierProvider<SelectedShopNotifier, ShopSummary?>(
        SelectedShopNotifier.new);
