import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_error_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../domain/barcode_validation.dart';
import '../controllers/search_controller.dart';
import 'freshness_disclaimer.dart';
import 'shop_product_card.dart';

/// Prompts for a barcode and shows the shops selling that product.
///
/// Manual entry is used deliberately: a live camera scanner would require a
/// new native dependency (and camera permission), so the screen stays
/// functional and testable without one. The lookup itself is the real
/// `GET /search/v2/barcodes/{barcode}` endpoint.
class BarcodeLookupSheet extends ConsumerStatefulWidget {
  const BarcodeLookupSheet({super.key});

  @override
  ConsumerState<BarcodeLookupSheet> createState() => _BarcodeLookupSheetState();
}

class _BarcodeLookupSheetState extends ConsumerState<BarcodeLookupSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _submitted;
  String? _fieldError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates BEFORE submitting: a malformed code shows an inline field error
  /// instead of firing a request that can only fail. Returns true when a
  /// lookup was actually started.
  bool _submit() {
    final value = normalizeBarcode(_controller.text);
    final reason = validateBarcode(value.isEmpty ? null : value);
    if (reason != null) {
      setState(() {
        _fieldError = invalidBarcodeMessage(reason);
        _submitted = null;
      });
      return false;
    }
    setState(() {
      _fieldError = null;
      _submitted = value;
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Scan barcode',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('barcodeInput'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.search,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'Enter barcode',
              border: const OutlineInputBorder(),
              // Inline validation error — the request never fires for a
              // malformed code, so the message appears here, not as a lookup
              // failure below.
              errorText: _fieldError,
              suffixIcon: IconButton(
                key: const Key('barcodeSubmit'),
                icon: const Icon(Icons.search),
                tooltip: 'Look up',
                onPressed: _submit,
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_submitted == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Enter the barcode printed on the product.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            _BarcodeResults(barcode: _submitted!),
        ],
      ),
    );
  }
}

class _BarcodeResults extends ConsumerWidget {
  final String barcode;

  const _BarcodeResults({required this.barcode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(barcodeLookupProvider(barcode));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
      error: (err, _) {
        // Offline/timeout vs server/auth failures read differently: the first
        // is the phone's connection (fixable by the customer right now), the
        // second is ours. The message always comes from `friendlyErrorMessage`
        // — raw exception text never reaches the sheet.
        final isOffline = err is ApiException &&
            (err.type == ApiErrorType.offline || err.type == ApiErrorType.timeout);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isOffline
                    ? 'You appear to be offline. Reconnect and try again, or fix '
                        'a possible typo below.'
                    : friendlyErrorMessage(err),
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                key: const Key('barcodeSheetRetry'),
                onPressed: () => ref.invalidate(barcodeLookupProvider(barcode)),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        );
      },
      data: (results) {
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: EmptyStateView(
              icon: Icons.qr_code_scanner,
              title: 'No match found',
              message: 'This barcode is not stocked by any nearby shop.',
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return ShopProductCard(
                    result: result,
                    onTap: () => Navigator.of(context).pop(),
                  );
                },
              ),
            ),
            // A scan finds the same shops as a typed search, so it carries the
            // same "this is the shop's last report" caveat.
            const SizedBox(height: AppSpacing.sm),
            const FreshnessDisclaimer(),
          ],
        );
      },
    );
  }
}
