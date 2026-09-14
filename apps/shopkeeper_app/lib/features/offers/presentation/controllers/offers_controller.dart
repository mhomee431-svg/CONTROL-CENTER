import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/offers_repository.dart';
import '../../domain/offer_models.dart';

/// Lifecycle of one offer-assignment attempt.
enum OfferAssignStatus { idle, saving, done, error }

class OfferAssignState {
  const OfferAssignState({required this.status, this.result, this.message});

  final OfferAssignStatus status;
  final OfferAssignResult? result;

  /// Error copy when [status] is [OfferAssignStatus.error].
  final String? message;

  factory OfferAssignState.idle() =>
      const OfferAssignState(status: OfferAssignStatus.idle);
}

final offersControllerProvider =
    NotifierProvider<OffersController, OfferAssignState>(OffersController.new);

/// Drives offer creation. UI renders [OfferAssignState] and forwards the
/// validated [OfferAssignRequest] — no business logic in widgets.
class OffersController extends Notifier<OfferAssignState> {
  @override
  OfferAssignState build() => OfferAssignState.idle();

  OffersRepository get _repo => ref.read(offersRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Creates + links the offer. Returns true on success (state becomes
  /// [OfferAssignState.done] with the [OfferAssignResult]).
  Future<bool> assign(OfferAssignRequest request) async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const OfferAssignState(
        status: OfferAssignStatus.error,
        message: 'No shop selected',
      );
      return false;
    }
    state = const OfferAssignState(status: OfferAssignStatus.saving);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final result = await _repo.assignOffer(shopId, request, token);
      state = OfferAssignState(status: OfferAssignStatus.done, result: result);
      return true;
    } on ApiException catch (e) {
      state = OfferAssignState(
        status: OfferAssignStatus.error,
        message: _friendly(e),
      );
      return false;
    } catch (_) {
      state = const OfferAssignState(
        status: OfferAssignStatus.error,
        message: 'Could not create the offer. Please retry.',
      );
      return false;
    }
  }

  /// Technical exceptions → shopkeeper-friendly copy.
  String _friendly(ApiException e) {
    if (e.isUnauthorized || e.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (e.isForbidden || e.statusCode == 403) {
      return 'Only shop owners can create offers.';
    }
    if (e.statusCode == 402 || e.errorCode == 'PLAN_LIMIT_REACHED') {
      return e.message.isNotEmpty
          ? e.message
          : 'Your plan does not allow more active offers.';
    }
    if (e.statusCode == null) {
      return 'No internet connection. Check your network and retry.';
    }
    return e.message;
  }

  /// Resets after the sheet closes so the next open starts clean.
  void reset() => state = OfferAssignState.idle();
}
