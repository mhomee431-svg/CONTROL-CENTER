import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/view/load_state.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/presentation/controllers/transport_quote_controller.dart';

/// The trips list: the half of the flow that turns a requested quote into a
/// booking (Master Spec §87-§88).
///
/// What matters here is honesty about state — a quoted price is the provider's,
/// an unanswered quote has none, an accept is never sent twice, and a failure
/// never leaves the button spinning forever.
class _TripsRepository implements ShopDetailsRepository {
  _TripsRepository({this.trips, this.acceptGate, this.acceptFailure});

  TransportTrips? trips;

  /// Mutable so a test can fail the SECOND load only, which is what proves a
  /// failed refresh keeps the list the customer was already reading.
  Object? failure;
  final Completer<void>? acceptGate;
  final Object? acceptFailure;

  int acceptCalls = 0;
  int cancelCalls = 0;
  int tripLoads = 0;

  @override
  Future<TransportTrips> getMyTransportTrips() async {
    tripLoads++;
    if (failure != null) throw failure!;
    return trips ?? const TransportTrips();
  }

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async {
    acceptCalls++;
    if (acceptGate != null) await acceptGate!.future;
    if (acceptFailure != null) throw acceptFailure!;
    return TransportBooking(
      id: 'B-$quoteId',
      quoteId: quoteId,
      bookingRef: 'TRP-1',
      status: 'PENDING',
      agreedAmount: 650,
    );
  }

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async {
    cancelCalls++;
    return TransportBooking(
      id: bookingId,
      bookingRef: 'TRP-1',
      status: 'CANCELLED',
      agreedAmount: 650,
    );
  }

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async => const TransportQuoteReceipt(quoteId: 'Q-1');

  @override
  Future<ShopProfile> getShopProfile(String shopId) async =>
      throw UnimplementedError();

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {}

  @override
  Future<RestaurantProfile?> getRestaurantProfile(String shopId) async => null;

  @override
  Future<TransportServiceProfile?> getTransportServiceProfile(
    String shopId,
  ) async => null;
}

ProviderContainer _container(ShopDetailsRepository repository) {
  final container = ProviderContainer(
    overrides: [shopDetailsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

const TransportQuote _quoted = TransportQuote(
  id: 'Q-1',
  providerId: '9001',
  providerName: 'Raftaar',
  status: 'QUOTED',
  pickupAddress: 'A',
  destinationAddress: 'B',
  quotedAmount: 650,
);

const TransportQuote _pending = TransportQuote(
  id: 'Q-2',
  providerId: '9001',
  providerName: 'Raftaar',
  status: 'REQUESTED',
  pickupAddress: 'C',
  destinationAddress: 'D',
);

void main() {
  group('the model rules the screen relies on', () {
    test('only a QUOTED quote can be accepted', () {
      expect(_quoted.canAccept, isTrue);
      expect(_pending.canAccept, isFalse);
      expect(_pending.isPending, isTrue);
    });

    test('an unanswered quote carries no price at all', () {
      // Never ₹0: the column default would read as a free trip.
      expect(_pending.quotedAmount, isNull);
    });

    test('a completed or cancelled booking cannot be cancelled', () {
      const completed = TransportBooking(
        id: 'b',
        bookingRef: 'TRP-1',
        status: 'COMPLETED',
      );
      const cancelled = TransportBooking(
        id: 'b',
        bookingRef: 'TRP-1',
        status: 'CANCELLED',
      );
      const confirmed = TransportBooking(
        id: 'b',
        bookingRef: 'TRP-1',
        status: 'CONFIRMED',
      );

      expect(completed.canCancel, isFalse);
      expect(cancelled.canCancel, isFalse);
      expect(confirmed.canCancel, isTrue);
    });

    test('a quote with a price is the actionable one', () {
      expect(
        const TransportTrips(quotes: [_pending]).hasActionableQuote,
        isFalse,
      );
      expect(
        const TransportTrips(quotes: [_pending, _quoted]).hasActionableQuote,
        isTrue,
      );
    });

    test('accepted and closed quotes leave the open list', () {
      const trips = TransportTrips(
        quotes: [
          TransportQuote(id: 'Q3', providerId: '9001', status: 'ACCEPTED'),
          TransportQuote(id: 'Q4', providerId: '9001', status: 'REJECTED'),
          TransportQuote(id: 'Q5', providerId: '9001', status: 'REQUESTED'),
        ],
      );
      expect(trips.openQuotes.map((q) => q.id), ['Q5']);
    });
  });

  group('loading', () {
    test('a loaded list is ready', () async {
      final container = _container(
        _TripsRepository(trips: const TransportTrips(quotes: [_quoted])),
      );
      await container.read(transportTripsViewModelProvider.notifier).load();

      final state = container.read(transportTripsViewModelProvider);
      expect(state.trips, isA<LoadReady<TransportTrips>>());
      expect(state.value?.quotes, hasLength(1));
    });

    test('no trips at all is an empty state, not a failure', () async {
      final container = _container(
        _TripsRepository(trips: const TransportTrips()),
      );
      await container.read(transportTripsViewModelProvider.notifier).load();

      final state = container.read(transportTripsViewModelProvider);
      // "You have no trips" needs different copy than "it broke" — so the two
      // states must not collapse.
      expect(state.trips, isA<LoadEmpty<TransportTrips>>());
      expect(state.trips.isFailed, isFalse);
    });

    test('a failed reload keeps the previous list', () async {
      final repository = _TripsRepository(
        trips: const TransportTrips(quotes: [_quoted]),
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();

      repository.failure = const ApiException(
        type: ApiErrorType.offline,
        message: 'No connection',
      );
      await viewModel.load();

      final state = container.read(transportTripsViewModelProvider);
      expect(state.trips.isFailed, isTrue);
      // The customer keeps reading what they had.
      expect(state.value?.quotes, hasLength(1));
    });
  });

  group('accepting a quote', () {
    test('creates the booking the backend returned, then reloads', () async {
      final repository = _TripsRepository(
        trips: const TransportTrips(quotes: [_quoted]),
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();

      final booking = await viewModel.acceptQuote('Q-1');

      expect(booking, isNotNull);
      expect(booking!.bookingRef, 'TRP-1');
      // The list reflects what the SERVER created, not a predicted row.
      expect(repository.tripLoads, 2);
      final state = container.read(transportTripsViewModelProvider);
      expect(state.action, isA<MutationSucceeded>());
    });

    test('a second tap while accepting sends nothing', () async {
      final gate = Completer<void>();
      final repository = _TripsRepository(
        trips: const TransportTrips(quotes: [_quoted]),
        acceptGate: gate,
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();

      final first = viewModel.acceptQuote('Q-1');
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(transportTripsViewModelProvider).isBusyFor('Q-1'),
        isTrue,
      );

      // Two accepts would create two bookings.
      expect(await viewModel.acceptQuote('Q-1'), isNull);
      expect(repository.acceptCalls, 1);

      gate.complete();
      expect(await first, isNotNull);
    });

    test('a rejected accept reports the reason and stays retryable', () async {
      final repository = _TripsRepository(
        trips: const TransportTrips(quotes: [_quoted]),
        acceptFailure: const ApiException(
          type: ApiErrorType.conflict,
          message: 'This quote was already accepted.',
        ),
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();

      expect(await viewModel.acceptQuote('Q-1'), isNull);

      final state = container.read(transportTripsViewModelProvider);
      expect(state.action, isA<MutationFailed>());
      expect(state.actionError, 'This quote was already accepted.');
      // Not stuck spinning, and the list is intact.
      expect(state.action.isRunning, isFalse);
      expect(state.value?.quotes, hasLength(1));
    });
  });

  group('cancelling a booking', () {
    test('cancels and reloads', () async {
      final repository = _TripsRepository(
        trips: const TransportTrips(
          bookings: [
            TransportBooking(
              id: 'B-1',
              bookingRef: 'TRP-1',
              status: 'CONFIRMED',
            ),
          ],
        ),
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();

      final booking = await viewModel.cancelBooking('B-1');

      expect(booking?.status, 'CANCELLED');
      expect(repository.cancelCalls, 1);
    });

    test('clearAction drops a stale failure message', () async {
      final repository = _TripsRepository(
        trips: const TransportTrips(quotes: [_quoted]),
        acceptFailure: const ApiException(
          type: ApiErrorType.conflict,
          message: 'Already accepted.',
        ),
      );
      final container = _container(repository);
      final viewModel = container.read(
        transportTripsViewModelProvider.notifier,
      );
      await viewModel.load();
      await viewModel.acceptQuote('Q-1');
      expect(
        container.read(transportTripsViewModelProvider).actionError,
        isNotNull,
      );

      viewModel.clearAction();
      final state = container.read(transportTripsViewModelProvider);
      expect(state.actionError, isNull);
      expect(state.action, isA<MutationIdle>());
    });
  });
}
