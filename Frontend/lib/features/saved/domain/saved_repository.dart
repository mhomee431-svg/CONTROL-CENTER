/// Saved items repository abstraction.
///
/// The real implementation lives in the `saved_and_history` feature
/// (`lib/features/saved_and_history/`). This file exists to keep the
/// `saved/` screen folder self-contained.
abstract class SavedRepository {
  Future<List<String>> getSavedProductIds();
  Future<void> saveProduct(String productId);
  Future<void> unsaveProduct(String productId);

  Future<List<String>> getSavedShopIds();
  Future<void> saveShop(String shopId);
  Future<void> unsaveShop(String shopId);
}