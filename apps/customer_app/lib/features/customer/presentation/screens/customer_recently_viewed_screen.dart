import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/network_image_view.dart';
import '../controllers/customer_controller.dart';
import '../../domain/models/customer_models.dart';

/// Recently-viewed products screen — live data from `customer_recent_products`.
class CustomerRecentlyViewedScreen extends ConsumerWidget {
  const CustomerRecentlyViewedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewedAsync = ref.watch(customerRecentlyViewedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Viewed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.invalidate(customerRecentlyViewedProvider),
          ),
        ],
      ),
      body: viewedAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyStateView(
              icon: Icons.history,
              title: 'Nothing viewed yet',
              message: 'Products you open will appear here for quick access.',
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(customerRecentlyViewedProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _RecentCard(item: item);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, st) => const Center(
          child: EmptyStateView(
            icon: Icons.error_outline,
            title: 'Couldn\'t load history',
            message: 'Something went wrong. Please try again.',
          ),
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final RecentProduct item;
  const _RecentCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 52,
          height: 52,
          child: item.imageUrl != null
              ? NetworkImageView(
                  imageUrl: item.imageUrl!,
                  borderRadius: 8,
                )
              : Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: AppColors.primary),
                ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          item.viewCount != null && item.viewCount! > 1
              ? 'Viewed ${item.viewCount} times'
              : 'Viewed once',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/product/${item.productMasterId}'),
      ),
    );
  }
}