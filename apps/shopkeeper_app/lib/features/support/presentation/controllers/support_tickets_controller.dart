import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../../auth/presentation/controllers/selected_shop.dart';
import '../../data/support_repository.dart';
import '../../data/support_screenshot_picker.dart';
import '../../domain/support_models.dart';
import '../../domain/support_ticket.dart';

/// Load state for the ticket list.
enum SupportTicketsStatus { loading, ready, error }

/// Support-ticket state: the shopkeeper's tracked tickets and the in-flight
/// state of a new report.
///
/// One controller owns both, because the report screen and the ticket list are
/// two views of the same server-side collection — filing a ticket must make it
/// appear in the list without a second source of truth.
class SupportTicketsState {
  const SupportTicketsState({
    this.status = SupportTicketsStatus.loading,
    this.tickets = const [],
    this.total = 0,
    this.loadingMore = false,
    this.message,
    this.submitting = false,
    this.submitError,
    this.lastFiled,
  });

  final SupportTicketsStatus status;

  /// The signed-in shopkeeper's tickets LOADED SO FAR, exactly as the backend
  /// returned them.
  final List<SupportTicket> tickets;

  /// How many tickets the account has in total, per the SERVER's count across
  /// every page — not the number currently held.
  final int total;

  /// True while the next page is in flight (the footer shows progress).
  final bool loadingMore;

  /// Why the list could not be loaded (shown with a Retry).
  final String? message;

  /// True while a report is being filed — the submit button shows progress.
  final bool submitting;

  /// Why the last report could not be filed (backend rejection / offline).
  final String? submitError;

  /// The ticket the last successful submit produced, so the screen can confirm
  /// with the server's own reference and status instead of inventing one.
  final SupportTicket? lastFiled;

  bool get isEmpty => tickets.isEmpty;

  /// True when the server holds tickets this list has not fetched yet.
  bool get hasMore => tickets.length < total;

  /// Tickets still behind the page break — the count the footer offers.
  int get hidden => total - tickets.length;

  SupportTicketsState copyWith({
    SupportTicketsStatus? status,
    List<SupportTicket>? tickets,
    int? total,
    bool? loadingMore,
    String? message,
    bool? submitting,
    String? submitError,
    SupportTicket? lastFiled,
    bool clearMessage = false,
    bool clearSubmitError = false,
    bool clearLastFiled = false,
  }) => SupportTicketsState(
    status: status ?? this.status,
    tickets: tickets ?? this.tickets,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
    message: clearMessage ? null : (message ?? this.message),
    submitting: submitting ?? this.submitting,
    submitError: clearSubmitError ? null : (submitError ?? this.submitError),
    lastFiled: clearLastFiled ? null : (lastFiled ?? this.lastFiled),
  );
}

final supportTicketsProvider =
    NotifierProvider<SupportTicketsController, SupportTicketsState>(
      SupportTicketsController.new,
    );

class SupportTicketsController extends Notifier<SupportTicketsState> {
  @override
  SupportTicketsState build() => const SupportTicketsState();

  SupportRepository get _repo => ref.read(supportRepositoryProvider);

  Future<String> _token() async {
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null || token.isEmpty) {
      throw const ApiException(message: 'Not signed in');
    }
    return token;
  }

  /// Loads the FIRST page of the shopkeeper's tickets from the backend.
  ///
  /// Always restarts at offset 0 and REPLACES the rows: a reload must never
  /// stack a previous session's page 2 under the current page 1.
  Future<void> load() async {
    state = state.copyWith(
      status: SupportTicketsStatus.loading,
      clearMessage: true,
    );
    try {
      final page = await _repo.fetchTickets(await _token());
      state = state.copyWith(
        status: SupportTicketsStatus.ready,
        tickets: page.tickets,
        total: page.total,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        status: SupportTicketsStatus.error,
        message: e.isUnauthorized
            ? 'Your session expired. Sign in again to see your tickets.'
            : e.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: SupportTicketsStatus.error,
        message: 'Could not load your tickets. Please retry.',
      );
    }
  }

  /// Fetches the NEXT page of tickets and appends it.
  ///
  /// Paginated by the BACKEND: the offset is the number of tickets already
  /// held, so each page is one bounded round trip and no ticket is downloaded
  /// twice. It is a no-op when nothing is left, so a footer tap at the end of
  /// the list cannot loop, and a failed page keeps the rows already loaded
  /// (with the reason in [SupportTicketsState.message]).
  Future<void> loadMore() async {
    if (state.status != SupportTicketsStatus.ready) return;
    if (!state.hasMore || state.loadingMore) return;

    state = state.copyWith(loadingMore: true, clearMessage: true);
    try {
      final page = await _repo.fetchTickets(
        await _token(),
        offset: state.tickets.length,
      );
      // De-duplicate by id: a ticket filed while paging shifts the offset
      // window, and the same row could otherwise appear twice.
      final seen = state.tickets.map((t) => t.id).toSet();
      state = state.copyWith(
        tickets: [
          ...state.tickets,
          ...page.tickets.where((t) => !seen.contains(t.id)),
        ],
        total: page.total,
        loadingMore: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        loadingMore: false,
        message: e.isUnauthorized
            ? 'Your session expired. Sign in again to see your tickets.'
            : e.message,
      );
    } catch (_) {
      state = state.copyWith(
        loadingMore: false,
        message: 'Could not load more tickets. Please retry.',
      );
    }
  }

  /// Files a report and returns the created ticket, or null when it failed
  /// (the reason then lives in [SupportTicketsState.submitError]).
  ///
  /// The returned ticket is the SERVER's row, so the confirmation shows the
  /// backend's reference and status. It is also prepended to the cached list,
  /// which is server data — not a locally fabricated placeholder.
  Future<SupportTicket?> submit({
    required IssueCategory category,
    required IssueSeverity severity,
    required String description,
    String? steps,
    String? appVersion,
    PickedScreenshot? screenshot,
  }) async {
    if (state.submitting) return null;
    final shop = ref.read(selectedShopProvider);
    state = state.copyWith(
      submitting: true,
      clearSubmitError: true,
      clearLastFiled: true,
    );
    String? attachmentKey;
    try {
      final token = await _token();
      if (screenshot != null) {
        // Push the screenshot through the same signed-upload pipeline product
        // and shop images use (grant -> upload -> confirm) — AWS credentials
        // never reach the device, and only a CONFIRMED object can be attached,
        // so a dropped upload can never leave a broken ticket.
        attachmentKey = await _repo.uploadAttachment(
          token: token,
          filename: screenshot.filename,
          contentType: screenshot.contentType,
          bytes: screenshot.bytes,
        );
      }
      final ticket = await _repo.createTicket(
        token: token,
        category: category,
        severity: severity,
        description: description,
        steps: steps,
        appVersion: appVersion,
        // Attached so support can look up the right shop first time; the
        // backend re-authorizes the id before accepting it.
        shopId: shop?.id,
        attachmentKey: attachmentKey,
      );
      final alreadyListed = state.tickets.any((t) => t.id == ticket.id);
      state = state.copyWith(
        submitting: false,
        lastFiled: ticket,
        tickets: [ticket, ...state.tickets.where((t) => t.id != ticket.id)],
        // The new row is now in the list, so the server's count has grown by
        // one too — otherwise "x more" would be off by the ticket just filed.
        total: alreadyListed ? state.total : state.total + 1,
      );
      return ticket;
    } on ApiException catch (e) {
      state = state.copyWith(
        submitting: false,
        submitError: e.isUnauthorized
            ? 'Your session expired. Sign in again to send this report.'
            : e.message,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        submitError: 'Could not send your report. Please retry.',
      );
      return null;
    }
  }

  /// Re-reads one ticket (used when a resolution notice opens it).
  Future<SupportTicket?> reloadTicket(int ticketId) async {
    try {
      final ticket = await _repo.fetchTicket(ticketId, await _token());
      state = state.copyWith(
        tickets: [ticket, ...state.tickets.where((t) => t.id != ticket.id)],
      );
      return ticket;
    } catch (_) {
      return null;
    }
  }

  /// Drops the confirmation banner after the shopkeeper has seen it.
  void acknowledgeFiled() => state = state.copyWith(clearLastFiled: true);

  /// Drops every ticket on sign-out.
  ///
  /// Required by the hard-logout flow: tickets are scoped to one account, so
  /// leaving them cached would show the previous shopkeeper's support history
  /// to whoever signs in next on this device.
  void reset() => state = const SupportTicketsState();
}

