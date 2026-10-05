import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/view/load_state.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../../core/widgets/list_loading_view.dart';
import '../../../../core/widgets/skeletons.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';
import '../../domain/models/business_profile_models.dart';
import '../controllers/transport_quote_controller.dart';

/// The customer's transport trips: quotes they asked for, and bookings they
/// accepted (Master Spec §87-§88).
///
/// This is the OTHER HALF of the request entry point on a provider's profile.
/// Requesting a quote is not a dead end: the provider answers with a price, the
/// customer accepts it here, and a booking appears with a real reference. Every
/// amount on this screen came FROM the provider — nothing is computed locally.
///
/// Deliberately not part of "My Orders": a transport booking is a service booking
/// (Rule 6), not a product order, and merging them would put "In stock" and
/// "Delivered" vocabulary onto a trip that has neither.
class TransportTripsScreen extends ConsumerStatefulWidget {
  const TransportTripsScreen({super.key});

  @override
  ConsumerState<TransportTripsScreen> createState() =>
      _TransportTripsScreenState();
}

class _TransportTripsScreenState extends ConsumerState<TransportTripsScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame rather than in initState: a provider read there
    // happens during build, and a signed-out customer's answer is a sign-in sheet
    // rather than a list.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfAllowed());
  }

  /// Trips belong to a signed-in customer, so the list is behind the same gate
  /// every other account-scoped read uses.
  Future<void> _loadIfAllowed() async {
    if (!mounted) return;
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: 'see your trips',
    );
    if (!allowed || !mounted) return;
    await ref.read(transportTripsViewModelProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transportTripsViewModelProvider);
    final trips = state.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My trips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: state.trips.isLoading
                ? null
                : () =>
                      ref.read(transportTripsViewModelProvider.notifier).load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(transportTripsViewModelProvider.notifier).load(),
        child: _buildBody(context, state, trips),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    TransportTripsState state,
    TransportTrips? trips,
  ) {
    // The load states first: a cold load has nothing to refresh, so it is a
    // placeholder of the list itself rather than pull-to-refresh over an empty
    // scroll view. Cards below, not a bare spinner — the customer can see that
    // quotes and bookings are what is coming, and the layout does not jump when
    // they land.
    if (state.trips is LoadLoading && trips == null) {
      return const ListLoadingView(
        message: 'Loading your trips…',
        // Quote/booking cards: a title with a status chip, then the route and
        // its metadata — the same silhouette [SkeletonRowShape.issue] draws.
        shape: SkeletonRowShape.issue,
      );
    }

    if (state.trips is LoadFailed && trips == null) {
      return _scrollable(
        child: EmptyStateView(
          icon: Icons.cloud_off,
          title: 'Could not load your trips',
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onActionTap: () =>
              ref.read(transportTripsViewModelProvider.notifier).load(),
        ),
      );
    }

    if (trips == null || trips.isEmpty) {
      return _scrollable(
        child: const EmptyStateView(
          icon: Icons.directions_car_outlined,
          title: 'No trips yet',
          message:
              'Quotes you request from a transport or travel provider appear '
              'here, along with the price they quote back.',
        ),
      );
    }

    return _buildList(context, state, trips);
  }

  Widget _buildList(
    BuildContext context,
    TransportTripsState state,
    TransportTrips trips,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (state.actionError != null)
          _ActionError(
            message: state.actionError!,
            onDismiss: () => ref
                .read(transportTripsViewModelProvider.notifier)
                .clearAction(),
          ),
        if (trips.hasActionableQuote)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'A provider has quoted a price for your trip.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        for (final quote in trips.openQuotes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _QuoteCard(
              quote: quote,
              busy: state.isBusyFor(quote.id),
              onAccept: () => _confirmAccept(context, quote),
            ),
          ),
        if (trips.bookings.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
            child: Text(
              'Bookings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        for (final booking in trips.bookings)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _BookingCard(
              booking: booking,
              busy: state.isBusyFor(booking.id),
              onCancel: booking.canCancel
                  ? () => _confirmCancel(context, booking)
                  : null,
            ),
          ),
      ],
    );
  }

  /// A scroll view that still satisfies pull-to-refresh on the empty states.
  Widget _scrollable({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  /// Accepting commits the customer to the provider's price, so it is confirmed
  /// explicitly — and the copy states the amount being accepted, because that is
  /// the one thing being agreed to.
  Future<void> _confirmAccept(
    BuildContext context,
    TransportQuote quote,
  ) async {
    final amount = quote.quotedAmount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept this quote?'),
        content: Text(
          amount == null
              ? 'The provider will confirm your trip.'
              : 'You are accepting ${_money(amount, quote.currency)} for '
                    '${quote.pickupAddress} → ${quote.destinationAddress}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final viewModel = ref.read(transportTripsViewModelProvider.notifier);
    final booking = await viewModel.acceptQuote(quote.id);
    if (!context.mounted) return;

    final state = ref.read(transportTripsViewModelProvider);
    if (booking != null) {
      _toast(context, 'Trip booked. Reference ${booking.bookingRef}');
      return;
    }
    if (state.actionError != null) _toast(context, state.actionError!);
  }

  /// Cancelling a confirmed trip is destructive, so it is confirmed explicitly
  /// and the copy is honest that any charges are the provider's call.
  Future<void> _confirmCancel(
    BuildContext context,
    TransportBooking booking,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: Text(
          'Cancel booking ${booking.bookingRef}. Contact the provider to '
          'discuss any charges.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep trip'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final viewModel = ref.read(transportTripsViewModelProvider.notifier);
    final cancelled = await viewModel.cancelBooking(booking.id);
    if (!context.mounted) return;

    final state = ref.read(transportTripsViewModelProvider);
    _toast(
      context,
      cancelled != null
          ? 'Trip ${cancelled.bookingRef} cancelled'
          : (state.actionError ?? 'Could not cancel this trip.'),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A failed accept/cancel, shown once and dismissible — a row-level failure must
/// not become a whole-screen error.
class _ActionError extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ActionError({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

/// One open quote: where the trip goes, its state, and the provider's price when
/// they have answered.
///
/// The price is the provider's, so a quote still waiting shows "Waiting for a
/// price" rather than a number — and the Accept control exists ONLY on a quoted
/// price, because accepting an unanswered quote is not a thing the backend can do.
class _QuoteCard extends StatelessWidget {
  final TransportQuote quote;
  final bool busy;
  final VoidCallback onAccept;

  const _QuoteCard({
    required this.quote,
    required this.busy,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    quote.providerName.isEmpty
                        ? 'Transport provider'
                        : quote.providerName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusChip(label: _quoteStatusLabel(quote)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${quote.pickupAddress} → ${quote.destinationAddress}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _tripMeta(quote.tripDate, quote.tripDays, quote.passengerCount),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            if (quote.canAccept)
              Row(
                children: [
                  Text(
                    'Quoted ${_money(quote.quotedAmount!, quote.currency)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ],
              )
            else
              const Text(
                'Waiting for a price from the provider',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// One confirmed booking: the reference, the AGREED amount, and its status.
///
/// The amount shown is what the customer accepted, and the status comes from the
/// provider's own transitions — the app never advances a booking's state itself.
class _BookingCard extends StatelessWidget {
  final TransportBooking booking;
  final bool busy;
  final VoidCallback? onCancel;

  const _BookingCard({
    required this.booking,
    required this.busy,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.bookingRef,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusChip(label: _bookingStatusLabel(booking.status)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${booking.pickupAddress} → ${booking.destination}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              _tripMeta(
                booking.tripDate,
                booking.tripDays,
                booking.passengerCount,
              ),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Agreed ${_money(booking.agreedAmount, booking.currency)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (onCancel != null)
                  OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A small coloured state label. Unknown states render as the raw value rather
/// than being hidden, so a new backend status is visible instead of silently
/// blank.
class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

Color _statusColor(String label) {
  switch (label.toUpperCase()) {
    case 'CONFIRMED':
    case 'ACCEPTED':
    case 'COMPLETED':
      return AppColors.secondary;
    case 'CANCELLED':
    case 'REJECTED':
    case 'EXPIRED':
      return AppColors.error;
    default:
      return AppColors.textMuted;
  }
}

String _quoteStatusLabel(TransportQuote quote) {
  if (quote.canAccept) return 'Quoted';
  if (quote.isPending) return 'Waiting';
  return quote.status.isEmpty ? 'Unknown' : quote.status;
}

String _bookingStatusLabel(String status) =>
    status.isEmpty ? 'Unknown' : status;

String _tripMeta(String date, int days, int passengers) {
  final parts = <String>[];
  if (date.isNotEmpty) parts.add(date);
  if (days > 1) parts.add('$days days');
  parts.add('$passengers ${passengers == 1 ? 'seat' : 'seats'}');
  return parts.join('  •  ');
}

/// Money, in the currency the provider quoted. The symbol is fixed to the one the
/// rest of the app uses; a non-INR quote still shows its own currency code rather
/// than being rendered with the wrong sign.
String _money(double amount, String currency) {
  final rounded = amount.round();
  return currency.toUpperCase() == 'INR'
      ? '₹$rounded'
      : '$rounded ${currency.toUpperCase()}';
}
