import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth_models.dart';

/// The shop whose business resources are currently being managed.
///
/// A shopkeeper may own or manage MULTIPLE shops; everything downstream
/// (dashboard / products / settings) is scoped to this selection. Only
/// shops returned by the backend's authorized list may ever be placed here.
class SelectedShopNotifier extends Notifier<ShopSummary?> {
  @override
  ShopSummary? build() => null;

  void select(ShopSummary? shop) => state = shop;
}

final selectedShopProvider =
    NotifierProvider<SelectedShopNotifier, ShopSummary?>(
        SelectedShopNotifier.new);
