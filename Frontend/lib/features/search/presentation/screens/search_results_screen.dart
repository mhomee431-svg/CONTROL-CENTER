import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/search_state.dart';
import '../controllers/search_controller.dart';
import '../widgets/search_filter_sort_bar.dart';
import '../widgets/search_result_states.dart';
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
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  final ScrollController _scrollController = ScrollController();

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
      ref
          .read(searchResultsProvider(widget.query).notifier)
          .fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchResultsProvider(widget.query));
    final controller = ref.read(searchResultsProvider(widget.query).notifier);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(widget.query),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: FilterSortBar(query: widget.query),
        ),
      ),
      body: _buildBody(state, controller),
    );
  }

  Widget _buildBody(
      SearchPaginationState state, SearchResultsController controller) {
    switch (state.stage) {
      case SearchStage.loading:
        return const SearchLoadingView(message: 'Finding products…');
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
      SearchPaginationState state, SearchResultsController controller) {
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
            onRefresh: () async =>
                controller.updateSort(state.sort),
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
                  onTap: () => context.push(
                    '/product/${result.productId}',
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