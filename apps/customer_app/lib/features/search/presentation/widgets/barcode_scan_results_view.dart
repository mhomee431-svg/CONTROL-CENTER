import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../domain/barcode_capability.dart';
import '../../domain/models/search_models.dart';
import '../controllers/search_controller.dart';
import 'freshness_disclaimer.dart';
import 'shop_product_card.dart';

/// Results for a barcode that was just detected by the camera.
///
/// WHY A WIDGET AND NOT A SHEET: the shopkeeper app confirms a scan in a sheet
/// because it is about to WRITE (create a product). A customer scan only READS —
/// "who near me sells this?" — so the answer is the whole point of the screen and
/// gets the full viewport, with the same card, freshness disclaimer and detail
/// routes as a typed search result. A scanned and a typed query must not look
/// like two different features.
///
/// Three kinds of "nothing to show" are kept visibly distinct, because they ask
/// the customer for opposite actions:
///  * empty data → the barcode is real, nobody stocks it → scan again;
///  * a failing request → the answer may exist → retry / scan again;
///  * [BarcodeSupport.unsupported] → the server has no barcode route at all →
///    say so plainly and stop offering a scan that cannot work.
class BarcodeScanResultsView extends ConsumerWidget {
  const BarcodeScanResultsView({
    super.key,
    required this.barcode,
    required this.onScanAnother,
    required this.onEnterManually,
  });

  final String barcode;
  final VoidCallback onScanAnother;
  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookup = ref.watch(barcodeLookupProvider(barcode));
    final routeMissing = ref.watch(barcodeSupportProvider).isHidden;

    return lookup.when(
      // Shops are arriving: a list, so a list placeholder. The old centred spinner
      // told the customer only "wait" and then rebuilt the panel from nothing.
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: SkeletonList(itemCount: 4, shape: SkeletonRowShape.product),
      ),
      error: (error, _) {
        // The route does not exist here: retrying is not a way forward, and the
        // copy must not imply the customer's barcode is the problem.
        if (routeMissing) {
          return _message(
            icon: Icons.cloud_off_outlined,
            title: 'Barcode search unavailable',
            message: kBarcodeUnsupportedMessage,
            onScanAnother: null,
            key: const Key('barcode_results_unavailable'),
          );
        }
        // Transient vs permanent failures get opposite reactions. Offline and
        // timeouts are the phone's problem — retry the SAME code, since the
        // answer may exist. Auth and server failures may also be transient, but
        // hammering them with silent auto-retries hides an outage, so the retry
        // is explicit and one tap away.
        final offline =
            error is ApiException &&
            (error.type == ApiErrorType.offline ||
                error.type == ApiErrorType.timeout);
        final icon = offline
            ? Icons.wifi_off_outlined
            : error is ApiException && error.type == ApiErrorType.serverError
            ? Icons.dns_outlined
            : Icons.wifi_tethering_error_outlined;
        return _message(
          icon: icon,
          title: offline
              ? 'You are offline'
              : error is ApiException && error.type == ApiErrorType.serverError
              ? 'Our servers had a hiccup'
              : 'Could not look up this barcode',
          // Always the user-safe message; raw exception text never reaches UI.
          message: friendlyErrorMessage(error),
          onScanAnother: onScanAnother,
          onRetry: () => ref.invalidate(barcodeLookupProvider(barcode)),
          key: const Key('barcode_results_error'),
        );
      },
      data: (results) {
        if (results.isEmpty) {
          return _message(
            icon: Icons.qr_code_scanner,
            title: 'No shop stocks this',
            message:
                'Barcode $barcode is not listed by any shop delivering to your '
                'area. Check the number and try again.',
            onScanAnother: onScanAnother,
            key: const Key('barcode_results_empty'),
          );
        }
        // Multiple hits can share one barcode (same product stocked by many
        // shops — the NORMAL case) or, rarely, one barcode mapped to several
        // products (inner pack vs outer case sharing a GS1 code). Group by
        // product so the customer picks WHAT first, then WHERE — a flat list
        // of N shops × M products answers neither question.
        final groups = _groupByProduct(results);
        if (groups.length == 1) return _resultsList(context, results);
        return _productGroupsList(context, groups);
      },
    );
  }

  /// A full-height message with the ways forward underneath it.
  ///
  /// `onScanAnother: null` means "scanning again cannot help" — the only such
  /// case is a server without the route — so the scan button disappears while
  /// manual entry stays. Manual entry is itself pointless in that state, which
  /// is why it is dropped too: both would hit the same missing endpoint.
  ///
  /// `onRetry` re-fires the SAME lookup (offline → back online, server hiccup
  /// cleared); `onScanAnother` starts over with a fresh code. Both are offered
  /// on lookup errors because the customer — not the app — knows which fix
  /// applies.
  Widget _message({
    required IconData icon,
    required String title,
    required String message,
    required VoidCallback? onScanAnother,
    VoidCallback? onRetry,
    Key? key,
  }) {
    return Column(
      children: [
        Expanded(
          child: EmptyStateView(
            key: key,
            icon: icon,
            title: title,
            message: message,
            actionLabel: onRetry != null
                ? 'Try again'
                : onScanAnother == null
                ? null
                : 'Scan another barcode',
            actionIcon: onRetry != null ? Icons.refresh : Icons.qr_code_scanner,
            onActionTap: onRetry ?? onScanAnother,
          ),
        ),
        if (onScanAnother != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: onRetry != null
                  ? OutlinedButton.icon(
                      onPressed: onScanAnother,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan another barcode'),
                    )
                  : OutlinedButton.icon(
                      onPressed: onEnterManually,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: const Text('Enter barcode manually'),
                    ),
            ),
          ),
        if (onScanAnother != null && onRetry != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEnterManually,
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: const Text('Enter barcode manually'),
              ),
            ),
          ),
      ],
    );
  }

  /// Groups hits by product so a barcode shared by several products becomes a
  /// pick-WHAT-first list. Keyed on `productId`, falling back to the name when
  /// the backend omits ids — two products never share both.
  Map<String, List<ShopProductResult>> _groupByProduct(
    List<ShopProductResult> results,
  ) {
    final groups = <String, List<ShopProductResult>>{};
    for (final result in results) {
      final key = result.productId.isNotEmpty
          ? result.productId
          : 'name:${result.productName}';
      (groups[key] ??= []).add(result);
    }
    return groups;
  }

  /// A barcode matched several PRODUCTS: one row per product with its cheapest
  /// price and shop count, so the choice is made on facts. Tapping a row opens
  /// that product's shops in a sheet — back returns to the OTHER products, not
  /// to the camera.
  Widget _productGroupsList(
    BuildContext context,
    Map<String, List<ShopProductResult>> groups,
  ) {
    final entries = groups.entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barcode $barcode',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${groups.length} products share this barcode — pick one to '
                'see the shops stocking it',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('barcode_product_groups'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final hits = entries[index].value;
              final first = hits.first;
              final cheapest = hits
                  .map((h) => h.price)
                  .reduce((a, b) => a < b ? a : b);
              final priceText = cheapest.truncateToDouble() == cheapest
                  ? cheapest.toStringAsFixed(0)
                  : cheapest.toStringAsFixed(2);
              return Card(
                key: Key('barcode_product_group_${entries[index].key}'),
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(
                    first.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'From ₹$priceText'
                    ' · ${hits.length} ${hits.length == 1 ? 'shop' : 'shops'}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      _showGroupSheet(context, first.productName, hits),
                ),
              );
            },
          ),
        ),
        const FreshnessDisclaimer(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            key: const Key('barcode_scan_another_groups'),
            onPressed: onScanAnother,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan another barcode'),
          ),
        ),
      ],
    );
  }

  /// The shops stocking ONE product of a multi-product barcode, shown as a
  /// bottom sheet so the group list stays one tap away (sheet back = the
  /// other products, not the camera).
  void _showGroupSheet(
    BuildContext context,
    String productName,
    List<ShopProductResult> hits,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                productName,
                key: const Key('barcode_group_sheet_title'),
                style: Theme.of(sheetContext).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                '${hits.length} ${hits.length == 1 ? 'shop' : 'shops'} '
                'stock this',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: hits.length,
                itemBuilder: (_, index) {
                  final result = hits[index];
                  return ShopProductCard(
                    result: result,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/product/${result.productId}');
                    },
                    onShopTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/shop/${result.shopId}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hits rendered exactly like typed search hits, so a scan and a search for
  /// the same product are indistinguishable apart from how they were entered.
  Widget _resultsList(BuildContext context, List<ShopProductResult> results) {
    final count = results.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barcode $barcode',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '$count ${count == 1 ? 'shop' : 'shops'} near you stock this '
                'product',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('barcode_results_list'),
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            itemCount: count,
            itemBuilder: (context, index) {
              final result = results[index];
              return ShopProductCard(
                result: result,
                onTap: () => context.push('/product/${result.productId}'),
                onShopTap: () => context.push('/shop/${result.shopId}'),
              );
            },
          ),
        ),
        // A scan finds the same shops as a typed search, so it carries the same
        // "this is the shop's last report, not live stock" caveat.
        const FreshnessDisclaimer(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            key: const Key('barcode_scan_another'),
            onPressed: onScanAnother,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan another barcode'),
          ),
        ),
      ],
    );
  }
}
