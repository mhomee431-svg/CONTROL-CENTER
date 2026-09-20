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
        message: _friendlyOfferError(
          e,
          forbidden: 'Only shop owners can create offers.',
        ),
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

  /// Resets after the sheet closes so the next open starts clean.
  void reset() => state = OfferAssignState.idle();
}

/// Technical exceptions → shopkeeper-friendly copy, shared by both controllers.
///
/// [forbidden] overrides the 403 copy because the reason differs per action
/// (creating an offer vs. listing them).
String _friendlyOfferError(ApiException e, {String? forbidden}) {
  if (e.isUnauthorized || e.statusCode == 401) {
    return 'Your session has expired. Please sign in again.';
  }
  if (e.isForbidden || e.statusCode == 403) {
    return forbidden ?? 'You do not have permission for this action.';
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

/// Lifecycle of the offers list.
enum OffersListStatus { loading, ready, error, noShop }

class OffersListState {
  const OffersListState({
    required this.status,
    this.items = const [],
    this.message,
  });

  final OffersListStatus status;
  final List<OfferSummary> items;

  /// Error copy when [status] is [OffersListStatus.error].
  final String? message;

  factory OffersListState.loading() =>
      const OffersListState(status: OffersListStatus.loading);

  /// Offers still running **or** starting in the future — the "Active" tab.
  /// Drafts are included so a just-created offer is never invisible.
  List<OfferSummary> get openOffers =>
      items.where((o) => !o.isExpired && !o.isDisabled).toList(growable: false);

  /// Offers whose window already closed — the "Expired" tab.
  List<OfferSummary> get expiredOffers =>
      items.where((o) => o.isExpired).toList(growable: false);

  /// Disabled offers — hidden from customers until re-enabled.
  List<OfferSummary> get disabledOffers =>
      items.where((o) => o.isDisabled).toList(growable: false);
}

final offersListControllerProvider =
    NotifierProvider<OffersListController, OffersListState>(
        OffersListController.new);

/// Drives the offers tabs.
///
/// ONE fetch serves both tabs — the state slices the result locally, so
/// switching tabs never re-hits the network and the two lists can never
/// disagree with each other or with the backend.
class OffersListController extends Notifier<OffersListState> {
  @override
  OffersListState build() => OffersListState.loading();

  OffersRepository get _repo => ref.read(offersRepositoryProvider);

  int? get _shopId => ref.read(selectedShopProvider)?.id;

  /// Loads every offer for the selected shop (newest window first).
  Future<void> load() async {
    final shopId = _shopId;
    if (shopId == null) {
      state = const OffersListState(
        status: OffersListStatus.noShop,
        message: 'No shop selected',
      );
      return;
    }
    state = OffersListState.loading();
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final page = await _repo.fetchOffers(shopId, token);
      state = OffersListState(
        status: OffersListStatus.ready,
        items: page.items,
      );
    } on ApiException catch (e) {
      state = OffersListState(
        status: OffersListStatus.error,
        message: _friendlyOfferError(
          e,
          forbidden: 'You do not have access to offers for this shop.',
        ),
      );
    } catch (_) {
      state = const OffersListState(
        status: OffersListStatus.error,
        message: 'Could not load offers.',
      );
    }
  }

  /// Activate / pause / disable / cancel one offer, then reload the list so
  /// every tab reflects the server-derived status bucket. Returns true when
  /// the backend accepted the transition.
  Future<bool> setStatus(int offerId, String status) async {
    final shopId = _shopId;
    final currentItems = state.items;
    if (shopId == null) return false;
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      await _repo.updateOfferStatus(shopId, offerId, status, token);
      await load();
      return true;
    } on ApiException catch (e) {
      state = OffersListState(
        status: OffersListStatus.error,
        items: currentItems,
        message: _friendlyOfferError(
          e,
          forbidden: 'Only shop owners can change offer status.',
        ),
      );
      return false;
    } catch (_) {
      state = OffersListState(
        status: OffersListStatus.error,
        items: currentItems,
        message: 'Could not update the offer. Please retry.',
      );
      return false;
    }
  }
}
