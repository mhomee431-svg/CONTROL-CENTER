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

/// Which slice of the fetched offers the screen shows — the offers screen's
/// filter (spec: Active / Scheduled / Expired, plus Disabled so a paused
/// offer always has a home).
enum OfferFilter {
  active('Active'),
  scheduled('Scheduled'),
  expired('Expired'),
  disabled('Disabled');

  const OfferFilter(this.label);

  /// Chip label — also the word tests and assistive tech see.
  final String label;
}

class OffersListState {
  const OffersListState({
    required this.status,
    this.items = const [],
    this.message,
    this.filter = OfferFilter.active,
  });

  final OffersListStatus status;
  final List<OfferSummary> items;

  /// Error copy when [status] is [OffersListStatus.error].
  final String? message;

  /// Which slice of [items] the screen shows.
  ///
  /// Lives in the STATE (not widget state) so it survives rebuilds, sheet
  /// detours and reloads; changing it never re-hits the network — ONE fetch
  /// serves every filter, so the slices can never disagree with each other
  /// or with the backend.
  final OfferFilter filter;

  factory OffersListState.loading({OfferFilter filter = OfferFilter.active}) =>
      OffersListState(status: OffersListStatus.loading, filter: filter);

  /// Live offers **and** drafts — the "Active" filter. Drafts are included
  /// so a just-created offer is never invisible; scheduled offers are their
  /// own slice ([scheduledOffers]), and an unrecognised display status
  /// (e.g. a newer backend state) lands here rather than vanishing.
  List<OfferSummary> get openOffers => items
      .where((o) => !o.isExpired && !o.isDisabled && !o.isScheduled)
      .toList(growable: false);

  /// Offers whose window has not started yet — the "Scheduled" filter.
  List<OfferSummary> get scheduledOffers =>
      items.where((o) => o.isScheduled).toList(growable: false);

  /// Offers whose window already closed — the "Expired" filter.
  List<OfferSummary> get expiredOffers =>
      items.where((o) => o.isExpired).toList(growable: false);

  /// Disabled offers — hidden from customers until re-enabled.
  List<OfferSummary> get disabledOffers =>
      items.where((o) => o.isDisabled).toList(growable: false);

  /// The slice [filter] selects right now. Every offer lands in exactly one
  /// bucket (the four predicates partition the list), so switching filters
  /// never duplicates or drops a row.
  List<OfferSummary> get visibleOffers => switch (filter) {
        OfferFilter.active => openOffers,
        OfferFilter.scheduled => scheduledOffers,
        OfferFilter.expired => expiredOffers,
        OfferFilter.disabled => disabledOffers,
      };
}

final offersListControllerProvider =
    NotifierProvider<OffersListController, OffersListState>(
        OffersListController.new);

/// Drives the offers list and its filter.
///
/// ONE fetch serves every filter — the state slices the result locally, so
/// switching filters never re-hits the network and the slices can never
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
      state = OffersListState(
        status: OffersListStatus.noShop,
        message: 'No shop selected',
        filter: state.filter,
      );
      return;
    }
    // The filter is the shopkeeper's view preference — it rides through the
    // reload (and through shop switches) instead of snapping back to Active.
    state = OffersListState.loading(filter: state.filter);
    try {
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token == null) throw const ApiException(message: 'Not signed in');
      final page = await _repo.fetchOffers(shopId, token);
      state = OffersListState(
        status: OffersListStatus.ready,
        items: page.items,
        filter: state.filter,
      );
    } on ApiException catch (e) {
      state = OffersListState(
        status: OffersListStatus.error,
        message: _friendlyOfferError(
          e,
          forbidden: 'You do not have access to offers for this shop.',
        ),
        filter: state.filter,
      );
    } catch (_) {
      state = OffersListState(
        status: OffersListStatus.error,
        message: 'Could not load offers.',
        filter: state.filter,
      );
    }
  }

  /// Switches which slice of the fetched rows the screen shows.
  ///
  /// Pure view state: no network round trip, no re-fetch — and because the
  /// filter lives in [OffersListState], it survives reloads, sheet detours
  /// and rebuilds instead of evaporating with the widget that picked it.
  void setFilter(OfferFilter value) {
    if (state.filter == value) return;
    state = OffersListState(
      status: state.status,
      items: state.items,
      message: state.message,
      filter: value,
    );
  }

  /// Activate / pause / disable / cancel one offer, then reload the list so
  /// every filter reflects the server-derived status bucket. Returns true
  /// when the backend accepted the transition.
  Future<bool> setStatus(int offerId, String status) async {
    final shopId = _shopId;
    final currentItems = state.items;
    final currentFilter = state.filter;
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
        filter: currentFilter,
      );
      return false;
    } catch (_) {
      state = OffersListState(
        status: OffersListStatus.error,
        items: currentItems,
        message: 'Could not update the offer. Please retry.',
        filter: currentFilter,
      );
      return false;
    }
  }
}
