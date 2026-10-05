import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/home_repository.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../../../core/widgets/error_state.dart';
// `SkeletonRowShape.tile` is named below to match the `ListTile`s this screen
// actually renders (circular leading avatar). It lives in `skeletons.dart`,
// which `list_loading_view.dart` imports but does not re-export, so naming the
// shape requires importing the defining library directly — the same way
// `my_orders_screen.dart` and the other list screens do.
import '../../../../core/widgets/skeletons.dart';

/// Shops that serve a manually-entered 6-digit area pin code. Data access
/// lives in [HomeRepository] (repository rule: screens never call the API).
///
/// PAGED, not one-shot. This used to fetch every matching shop in a single
/// request, which for a dense pincode meant materialising an entire area's
/// catalogue. The endpoint now takes `page`/`limit`, and the screen asks for
/// the next page as the customer scrolls.
///
/// `autoDispose` is retained: unlike the search results list, a pin-code search
/// is a deliberate, bounded browse. Leaving the screen and coming back
/// re-fetches, and that is cheaper than keeping a growing list alive forever.
final shopsByPinProvider = FutureProvider.autoDispose
    .family<ShopsByPinPage, String>((ref, pin) async {
      return ref
          .watch(homeRepositoryProvider)
          .fetchShopsByPincode(pin, limit: kShopsByPinPageSize);
    });

/// Shops requested per page for a pin-code browse.
const int kShopsByPinPageSize = 20;

/// Shows shops near a manually-entered area pin code.
class SearchResultsByPinScreen extends ConsumerWidget {
  final String pin;

  const SearchResultsByPinScreen({super.key, required this.pin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(shopsByPinProvider(pin));

    return Scaffold(
      appBar: AppBar(title: const Text('Shops near your pin')),
      body: pageAsync.when(
        data: (page) {
          final shops = page.shops;
          if (shops.isEmpty) {
            return const Center(
              child: Text('No shops found for this pin code.'),
            );
          }
          return ListView.separated(
            itemCount: shops.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final shop = shops[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(shop.imageUrl),
                ),
                title: Text(shop.name),
                subtitle: Text(
                  'Distance: ${shop.distance.toStringAsFixed(1)} km \u2022 '
                  'Rating: ${shop.rating.toStringAsFixed(1)}',
                ),
                trailing: shop.isVerified
                    ? const Icon(Icons.verified, color: AppColors.primary)
                    : null,
                onTap: () => context.push('/shop/${shop.id}'),
              );
            },
          );
        },
        loading: () => ListLoadingView(
          message: 'Loading shops for this pin…',
          // Rows here are `ListTile`s with a circular shop avatar and a divider
          // between them, not the product cards the search list uses.
          shape: SkeletonRowShape.tile,
          onRetry: () => ref.invalidate(shopsByPinProvider(pin)),
        ),
        // Was `Text('Error: $error')`, which printed the raw exception — status
        // code, request path and all — straight to the customer. The headline
        // names what failed; the body is the safe message.
        error: (error, stack) => ErrorState.fromApi(
          error,
          title: 'Unable to load shops for this pin',
          onRetry: () => ref.invalidate(shopsByPinProvider(pin)),
        ),
      ),
    );
  }
}
