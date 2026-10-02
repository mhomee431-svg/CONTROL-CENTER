import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_error_handler.dart';
import 'package:hyperlocal_app/core/view/load_state.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/business_profile_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/models/shop_details_models.dart';
import 'package:hyperlocal_app/features/shop_details/domain/shop_details_repository.dart';
import 'package:hyperlocal_app/features/shop_details/presentation/controllers/transport_quote_controller.dart';

/// The transport quote request (Master Spec §87-§88).
///
/// The property under test throughout is HONESTY: a confirmation only after the
/// backend acknowledged, never a price the app made up, and never two requests
/// from two taps.
class _QuoteRepository implements ShopDetailsRepository {
  _QuoteRepository({this.failure, this.gate});

  final Object? failure;

  /// Lets a test hold the request open to observe the in-flight state and fire
  /// a second submit while the first is still running.
  final Completer<void>? gate;

  int quoteCalls = 0;
  TransportQuoteRequest? lastRequest;

  @override
  Future<TransportQuoteReceipt> requestTransportQuote(
    TransportQuoteRequest request,
  ) async {
    quoteCalls++;
    lastRequest = request;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return const TransportQuoteReceipt(quoteId: 'Q-77', status: 'REQUESTED');
  }

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

  // Trips are outside this fake's concern: the quote tests only care that no
  // second request is sent while one is in flight, so an empty list is the
  // honest (and inert) answer.
  @override
  Future<TransportTrips> getMyTransportTrips() async => const TransportTrips();

  @override
  Future<TransportBooking> acceptTransportQuote(String quoteId) async =>
      throw StateError('this fake covers quote requests only');

  @override
  Future<TransportBooking> cancelTransportBooking(
    String bookingId, {
    String? reason,
  }) async => throw StateError('this fake covers quote requests only');
}

ProviderContainer _container(ShopDetailsRepository repository) {
  final container = ProviderContainer(
    overrides: [shopDetailsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<TransportQuoteReceipt?> _submit(
  TransportQuoteViewModel viewModel, {
  String providerId = '9001',
  String pickup = 'A',
  String destination = 'B',
}) {
  return viewModel.submit(
    providerId: providerId,
    tripPurpose: 'AIRPORT',
    pickupAddress: pickup,
    destinationAddress: destination,
    tripDate: DateTime(2026, 3, 7),
  );
}

void main() {
  group('a successful request', () {
    test('confirms with the backend reference and no price', () async {
      final container = _container(_QuoteRepository());

      final receipt = await _submit(
        container.read(transportQuoteViewModelProvider.notifier),
      );

      expect(receipt, isNotNull);
      expect(receipt!.quoteId, 'Q-77');

      final state = container.read(transportQuoteViewModelProvider);
      expect(state.isSubmitted, isTrue);
      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, isNull);
      // Nothing was made up: the receipt is a reference, not an amount.
      expect(state.receipt?.status, 'REQUESTED');
    });

    test('the payload is trimmed and matches the backend contract', () async {
      final repository = _QuoteRepository();
      final container = _container(repository);

      await container
          .read(transportQuoteViewModelProvider.notifier)
          .submit(
            providerId: ' 9001 ',
            tripPurpose: 'LOCAL_TRAVEL',
            pickupAddress: '  Sector 18  ',
            destinationAddress: '  Airport  ',
            tripDate: DateTime(2026, 4, 1),
            tripDays: 2,
            passengerCount: 3,
            notes: '  child seat  ',
          );

      final request = repository.lastRequest!;
      expect(request.providerId, '9001');
      expect(request.pickupAddress, 'Sector 18');
      expect(request.destinationAddress, 'Airport');
      expect(request.notes, 'child seat');
      expect(request.tripDays, 2);
      expect(request.passengerCount, 3);
    });
  });

  group('a failure', () {
    test('reports user-safe copy and never confirms', () async {
      final container = _container(
        _QuoteRepository(
          failure: const ApiException(
            type: ApiErrorType.offline,
            message: 'Could not reach the provider.',
          ),
        ),
      );

      final receipt = await _submit(
        container.read(transportQuoteViewModelProvider.notifier),
      );

      expect(receipt, isNull);
      final state = container.read(transportQuoteViewModelProvider);
      expect(state.isSubmitted, isFalse);
      expect(state.receipt, isNull);
      expect(state.errorMessage, 'Could not reach the provider.');
    });

    test('an unknown failure still leaves the form usable', () async {
      final container = _container(
        _QuoteRepository(failure: Exception('boom')),
      );

      await _submit(container.read(transportQuoteViewModelProvider.notifier));

      final state = container.read(transportQuoteViewModelProvider);
      expect(state.submission, isA<MutationFailed>());
      expect(state.isSubmitting, isFalse);
    });
  });

  group('the duplicate-request guard', () {
    test('a second tap while in flight sends nothing', () async {
      final gate = Completer<void>();
      final repository = _QuoteRepository(gate: gate);
      final container = _container(repository);
      final viewModel = container.read(
        transportQuoteViewModelProvider.notifier,
      );

      final first = _submit(viewModel);
      // The state is in flight before the await resolves, which is exactly the
      // window a double tap lands in.
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(transportQuoteViewModelProvider).isSubmitting,
        isTrue,
      );

      final second = await _submit(viewModel);
      expect(second, isNull);
      expect(repository.quoteCalls, 1, reason: 'one tap, one request');

      gate.complete();
      final receipt = await first;
      expect(receipt, isNotNull);
      expect(
        container.read(transportQuoteViewModelProvider).isSubmitted,
        isTrue,
      );
    });
  });

  group('reset', () {
    test('returns the form to idle after a success', () async {
      final container = _container(_QuoteRepository());
      final viewModel = container.read(
        transportQuoteViewModelProvider.notifier,
      );

      await _submit(viewModel);
      expect(
        container.read(transportQuoteViewModelProvider).isSubmitted,
        isTrue,
      );

      viewModel.reset();
      final state = container.read(transportQuoteViewModelProvider);
      expect(state.submission, isA<MutationIdle>());
      expect(state.receipt, isNull);
      expect(state.isSubmitted, isFalse);
    });
  });
}
