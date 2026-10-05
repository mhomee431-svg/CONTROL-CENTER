import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_error_handler.dart'
    show friendlyErrorMessage;
import '../../../../core/view/load_state.dart';
import '../../../../core/view/view_model.dart';
import '../../domain/models/business_profile_models.dart';
import '../../domain/shop_details_repository.dart';

/// Everything the transport quote form needs to render itself.
///
/// The TEXT stays in the widget — controllers are widget state, and putting
/// them here would mean a ViewModel importing Flutter widgets. What moves out
/// is the part that was genuinely request logic living in a view: the
/// mutation state machine and the contract-conformant payload.
class TransportQuoteState {
  /// The mutation lifecycle. One case at a time — never two booleans.
  final MutationState submission;

  /// The receipt once the backend has acknowledged the request. Non-null only
  /// after [MutationSucceeded], so a quote id can never be shown for a request
  /// that never landed.
  final TransportQuoteReceipt? receipt;

  const TransportQuoteState({
    this.submission = const MutationIdle(),
    this.receipt,
  });

  bool get isSubmitting => submission.isRunning;

  /// True once the server has actually acknowledged the request.
  ///
  /// Derived from [MutationSucceeded] rather than from a flag set alongside it,
  /// so a "requested" confirmation cannot be shown optimistically.
  bool get isSubmitted => submission is MutationSucceeded;

  /// User-safe failure text, or null when there is no failure to show.
  String? get errorMessage => switch (submission) {
    MutationFailed(:final error) => friendlyErrorMessage(error),
    _ => null,
  };

  TransportQuoteState copyWith({
    MutationState? submission,
    TransportQuoteReceipt? receipt,
  }) {
    return TransportQuoteState(
      submission: submission ?? this.submission,
      receipt: receipt ?? this.receipt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportQuoteState &&
          submission == other.submission &&
          receipt == other.receipt;

  @override
  int get hashCode => Object.hash(submission, receipt);
}

/// Owns the transport quote request.
///
/// This is the ViewModel the View rule asks for: the screen must not call
/// `requestTransportQuote` itself and track `_isSubmitting` / `_error` as two
/// independent fields, which could show "submitting" and "failed" at once and —
/// worse here than in support — could fire the SAME request twice with two taps
/// and charge the customer two quote threads. [MutationState] plus the
/// double-submit guard makes both unrepresentable.
class TransportQuoteViewModel extends ViewModel<TransportQuoteState> {
  @override
  TransportQuoteState buildOnce() => const TransportQuoteState();

  /// Asks the provider for a trip price.
  ///
  /// Fields are passed in rather than read from controllers held here, which is
  /// what keeps this class free of Flutter widgets. Returns the receipt on
  /// success, null when nothing was sent (already submitting) or when the
  /// request failed.
  Future<TransportQuoteReceipt?> submit({
    required String providerId,
    required String tripPurpose,
    required String pickupAddress,
    required String destinationAddress,
    required DateTime tripDate,
    int tripDays = 1,
    int passengerCount = 1,
    String? vehicleId,
    String notes = '',
  }) async {
    // The duplicate-request guard. Two taps must not create two quote requests.
    if (state.isSubmitting) return null;

    final request = TransportQuoteRequest(
      providerId: providerId.trim(),
      tripPurpose: tripPurpose,
      pickupAddress: pickupAddress.trim(),
      destinationAddress: destinationAddress.trim(),
      tripDate: tripDate,
      tripDays: tripDays,
      passengerCount: passengerCount,
      vehicleId: vehicleId,
      notes: notes.trim(),
    );

    state = state.copyWith(submission: const MutationRunning());
    final repository = ref.read(shopDetailsRepositoryProvider);

    try {
      final receipt = await repository.requestTransportQuote(request);
      state = state.copyWith(
        submission: const MutationSucceeded(),
        receipt: receipt,
      );
      return receipt;
    } catch (error) {
      // The repository contract says backend errors surface, and it never
      // invents a receipt. An uncaught throw here would leave the button
      // spinning forever — the one outcome the customer cannot escape — so the
      // catch is deliberate, not defensive noise.
      state = state.copyWith(submission: MutationFailed(error, ''));
      return null;
    }
  }

  /// Returns the form to its initial state, e.g. when the sheet closes after a
  /// success so the next request starts clean.
  void reset() {
    state = buildOnce();
  }
}

/// The quote ViewModel. Hot by default (see [ViewModel]), so navigating to the
/// sheet and back — or a rebuild mid-request — never discards the outcome.
final transportQuoteViewModelProvider =
    NotifierProvider<TransportQuoteViewModel, TransportQuoteState>(
      TransportQuoteViewModel.new,
    );

/// Everything the trips list needs to render itself.
///
/// The LIST is a [LoadState] and the per-row ACTIONS are a [MutationState],
/// because they are genuinely different lifecycles: a failed load leaves the
/// whole screen retryable, while a failed accept must leave the rest of the list
/// intact and retryable on that one row. Collapsing them into one state would
/// either blank the screen on a single failed tap or make a load failure look
/// like a row-level problem.
class TransportTripsState {
  final LoadState<TransportTrips> trips;

  /// The accept/cancel currently in flight, and how it ended.
  final MutationState action;

  /// The booking the last successful action produced, for the confirmation copy.
  final TransportBooking? lastBooking;

  /// Which quote/booking the in-flight action belongs to, so a row can show its
  /// own spinner instead of the whole list dimming.
  final String? busyTarget;

  const TransportTripsState({
    this.trips = const LoadIdle<TransportTrips>(),
    this.action = const MutationIdle(),
    this.lastBooking,
    this.busyTarget,
  });

  /// The trips, or the last good list during a refresh or a failed reload.
  TransportTrips? get value => trips.dataOrNull;

  bool get isRefreshing => trips.isLoading && value != null;

  /// True while a specific row's action is running.
  bool isBusyFor(String id) => busyTarget == id && action.isRunning;

  /// User-safe failure text for the action, or null.
  String? get actionError => switch (action) {
    MutationFailed(:final error) => friendlyErrorMessage(error),
    _ => null,
  };

  TransportTripsState copyWith({
    LoadState<TransportTrips>? trips,
    MutationState? action,
    TransportBooking? lastBooking,
    String? busyTarget,
    bool clearBooking = false,
    bool clearTarget = false,
  }) {
    return TransportTripsState(
      trips: trips ?? this.trips,
      action: action ?? this.action,
      lastBooking: clearBooking ? null : (lastBooking ?? this.lastBooking),
      busyTarget: clearTarget ? null : (busyTarget ?? this.busyTarget),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransportTripsState &&
          trips == other.trips &&
          action == other.action &&
          lastBooking == other.lastBooking &&
          busyTarget == other.busyTarget;

  @override
  int get hashCode => Object.hash(trips, action, lastBooking, busyTarget);
}

/// Owns the customer's transport trips: the list, plus accept and cancel.
///
/// This is the ViewModel the View rule asks for. The screen must not call the
/// repository or hold `_isLoading` / `_isAccepting` / `_error` as separate
/// fields, which could show a whole-list error because one row's tap failed, and
/// — worse — let a double tap send two accept requests and create two bookings.
class TransportTripsViewModel extends ViewModel<TransportTripsState> {
  @override
  TransportTripsState buildOnce() => const TransportTripsState();

  /// Loads quotes + bookings.
  ///
  /// Written out rather than delegating to [runLoad] for one reason: a REFRESH
  /// must keep the previous list on screen, and `runLoad` publishes a plain
  /// [LoadLoading] that discards it — so a failed reload would blank trips the
  /// customer was reading. [LoadState.refreshingOrLoading] is the sanctioned way
  /// to keep them. A successful-but-empty answer is [LoadEmpty], not an empty
  /// success: "you have no trips" needs different copy and a different route out
  /// than a failure does.
  Future<void> load() async {
    if (state.trips.isLoading) return;
    state = state.copyWith(trips: state.trips.refreshingOrLoading());
    try {
      final trips = await ref
          .read(shopDetailsRepositoryProvider)
          .getMyTransportTrips();
      state = state.copyWith(
        trips: trips.isEmpty
            ? const LoadEmpty<TransportTrips>()
            : LoadReady<TransportTrips>(trips),
      );
    } catch (error) {
      // The previous list is carried across, so a failed refresh is "old content
      // plus a retry", never a blank screen.
      state = state.copyWith(
        trips: LoadFailed<TransportTrips>(error, state.value),
      );
    }
  }

  /// Accepts a quoted price, creating the booking.
  ///
  /// Reloads afterwards so the list shows the booking the backend actually
  /// created, rather than a locally predicted row — the booking reference and
  /// status are the server's to decide.
  Future<TransportBooking?> acceptQuote(String quoteId) async {
    if (state.action.isRunning) return null;
    state = state.copyWith(
      action: const MutationRunning(),
      busyTarget: quoteId,
      clearBooking: true,
    );
    try {
      final booking = await ref
          .read(shopDetailsRepositoryProvider)
          .acceptTransportQuote(quoteId);
      state = state.copyWith(
        action: const MutationSucceeded(),
        lastBooking: booking,
      );
      await load();
      return booking;
    } catch (error) {
      state = state.copyWith(action: MutationFailed(error, ''));
      return null;
    }
  }

  /// Cancels a booking the customer can no longer use.
  Future<TransportBooking?> cancelBooking(
    String bookingId, {
    String? reason,
  }) async {
    if (state.action.isRunning) return null;
    state = state.copyWith(
      action: const MutationRunning(),
      busyTarget: bookingId,
      clearBooking: true,
    );
    try {
      final booking = await ref
          .read(shopDetailsRepositoryProvider)
          .cancelTransportBooking(bookingId, reason: reason);
      state = state.copyWith(
        action: const MutationSucceeded(),
        lastBooking: booking,
      );
      await load();
      return booking;
    } catch (error) {
      state = state.copyWith(action: MutationFailed(error, ''));
      return null;
    }
  }

  /// Clears a finished action so a later failure message cannot linger next to a
  /// newly loaded list.
  void clearAction() {
    if (state.action is MutationIdle) return;
    state = state.copyWith(
      action: const MutationIdle(),
      clearBooking: true,
      clearTarget: true,
    );
  }
}

/// The trips ViewModel. Hot (see [ViewModel]): returning to the screen should not
/// refetch a list the customer just read, and an accept must not lose its
/// outcome to a rebuild.
final transportTripsViewModelProvider =
    NotifierProvider<TransportTripsViewModel, TransportTripsState>(
      TransportTripsViewModel.new,
    );
