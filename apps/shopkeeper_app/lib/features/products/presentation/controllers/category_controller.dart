import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/token_store.dart';
import '../../data/category_repository.dart';
import '../../domain/category_taxonomy.dart';

/// Load states for the one-shot taxonomy fetch.
enum CategoryLoadStatus { idle, loading, ready, error }

class CategoryState {
  const CategoryState({
    this.status = CategoryLoadStatus.idle,
    this.taxonomy,
    this.message,
  });

  final CategoryLoadStatus status;
  final CategoryTaxonomy? taxonomy;
  final String? message;

  bool get hasData => taxonomy != null;
}

/// Loads the product taxonomy ONCE and keeps it for the whole session.
///
/// The create form opens far more often than the taxonomy changes, so the
/// result is cached at the provider level: a shopkeeper who adds five products
/// waits for exactly one request, and every later sheet-open renders the
/// dropdowns instantly from memory. A failure is recoverable — the form stays
/// usable (taxonomy fields are optional) and a retry is one tap away.
final categoryControllerProvider =
    NotifierProvider<CategoryController, CategoryState>(CategoryController.new);

class CategoryController extends Notifier<CategoryState> {
  @override
  CategoryState build() => const CategoryState();

  Future<void> ensureLoaded() async {
    // Already fetched (or in flight) — return immediately. This is what makes
    // repeated sheet-opens free.
    if (state.status == CategoryLoadStatus.ready ||
        state.status == CategoryLoadStatus.loading) {
      return;
    }
    state = const CategoryState(status: CategoryLoadStatus.loading);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) {
        state = const CategoryState(
          status: CategoryLoadStatus.error,
          message: 'Not signed in',
        );
        return;
      }
      final taxonomy =
          await ref.read(categoryRepositoryProvider).fetchTaxonomy(token);
      state = CategoryState(
        status: CategoryLoadStatus.ready,
        taxonomy: taxonomy,
      );
    } catch (_) {
      // Never block the form: taxonomy fields are optional by contract.
      state = const CategoryState(
        status: CategoryLoadStatus.error,
        message: 'Could not load categories',
      );
    }
  }
}
