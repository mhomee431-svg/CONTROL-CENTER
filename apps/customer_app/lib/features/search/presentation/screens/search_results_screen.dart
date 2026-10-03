import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/product_share.dart';
import '../../../../core/share/share_content.dart';
import '../../domain/search_state.dart';
import '../controllers/search_controller.dart';
import '../widgets/search_filter_sort_bar.dart';
import '../widgets/search_result_states.dart';
import '../widgets/search_results_map_view.dart';
import '../widgets/shop_product_card.dart';

/// Displays search results for a given query.
///
/// Watches [searchResultsProvider] which owns pagination, filters, sorting,
/// loading / empty / error state, and event tracking. The widget stays thin
/// and only maps the state machine to the correct UI.
class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final ScrollController _scrollController = ScrollController();

  /// View mode for results: default list; toggling shows every mappable
  /// shop on the map (SearchResultsMapView) with a peek bar of results.
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200) {
      ref.read(searchResultsProvider(widget.query).notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchResultsProvider(widget.query));
    final controller = ref.read(searchResultsProvider(widget.query).notifier);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        // Spec header: Search Results for "<query>" — long queries ellipsize
        // rather than overflow the toolbar.
        title: Text(
          'Search Results for "${widget.query}"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (state.stage == SearchStage.results)
            IconButton(
              key: const Key('searchViewToggle'),
              tooltip: _showMap ? 'List view' : 'Map view',
              icon: Icon(
                _showMap ? Icons.view_list_outlined : Icons.map_outlined,
              ),
              onPressed: () => setState(() => _showMap = !_showMap),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: FilterSortBar(query: widget.query),
        ),
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(
    SearchPaginationState state,
    SearchResultsController controller,
  ) {
    switch (state.stage) {
      case SearchStage.loading:
        // `retry` is passed because this stage is a real in-flight request that
        // can be re-issued; the `typing` stage is a debounce, not a request, so
        // it explains the wait without offering a button that would have
        // nothing to do.
        return SearchLoadingView(
          message: 'Finding products…',
          onRetry: controller.retry,
        );
      case SearchStage.typing:
        return const SearchLoadingView(message: 'Searching…');
      case SearchStage.empty:
        return SearchEmptyView(
          title: 'No products found',
          message:
              'Try adjusting your search or filters to find what you need.',
          onAction: controller.retry,
          actionLabel: 'Refresh',
        );
      case SearchStage.error:
        return SearchErrorView(
          message: state.error ?? 'Something went wrong while searching.',
          onRetry: controller.retry,
        );
      case SearchStage.idle:
        return const SizedBox.shrink();
      case SearchStage.results:
        return _buildResults(state, controller);
    }
  }

  Widget _buildResults(
    SearchPaginationState state,
    SearchResultsController controller,
  ) {
    // Map view: every result with coordinates rendered around the customer,
    // with a horizontal peek bar; tapping a result opens the product page.
    if (_showMap) {
      return SearchResultsMapView(
        results: state.results,
        onResultTap: (result) => context.push('/product/${result.productId}'),
      );
    }

    // Relevance / result count header.
    final header = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${state.totalResults} results for "${widget.query}"',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.trending_up, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          const Text(
            'Relevance',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        header,
        Expanded(
          child: RefreshIndicator(
            // `controller.refresh()`, not a re-apply of the current sort. The
            // old callback passed `state.sort` back into `updateSort`, which
            // returns early when the sort is unchanged -- and it always was --
            // so pulling to refresh refreshed nothing while the spinner spun
            // over stale rows. `refresh` re-runs the search itself and keeps
            // the customer's sort and filters.
            onRefresh: controller.refresh,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              itemCount: state.results.length + (state.isFetchingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.results.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  );
                }
                final result = state.results[index];
                return ShopProductCard(
                  result: result,
                  onTap: () => context.push('/product/${result.productId}'),
                  onShopTap: () => context.push('/shop/${result.shopId}'),
                  onShare: () => shareProductContent(
                    ref,
                    buildProductShareContent(
                      productName: result.productName,
                      price: result.price,
                      mrp: result.mrp,
                      discountPercent: result.discountPercent,
                      shopName: result.shopName,
                      distanceInKm: result.distanceInKm,
                      variant: result.variant,
                      brand: result.brand,
                      // The card knows the product's id, so the share can carry
                      // a deep link -- but only into the URL, never the prose.
                      productId: result.productId,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
