import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/token_store.dart';
import '../../data/sessions_repository.dart';
import '../../domain/device_session.dart';

enum SessionsStatus { loading, ready, error }

class SessionsState {
  const SessionsState({
    required this.status,
    this.sessions = const [],
    this.currentSessionId,
    this.message,
    this.revoking = const <String>{},
  });

  final SessionsStatus status;
  final List<DeviceSession> sessions;

  /// Session id THIS device signed in with (`TokenStore.readSessionId`).
  ///
  /// The "This device" marker comes from the stored id rather than "the first
  /// row" — the backend orders by activity, so guessing from position would
  /// label the wrong device.
  final String? currentSessionId;

  /// Failure copy when [status] is [SessionsStatus.error].
  final String? message;

  /// Session ids with a revoke in flight — the row shows progress and its
  /// button is disabled, so a double tap cannot fire two revokes.
  final Set<String> revoking;

  bool get isEmpty => sessions.isEmpty;

  /// The backend row for this device, or null when the server has no session
  /// for it (a Google/Firebase sign-in carries no server-side session).
  DeviceSession? get currentSession {
    final id = currentSessionId;
    if (id == null) return null;
    for (final session in sessions) {
      if (session.sessionId == id) return session;
    }
    return null;
  }

  bool isCurrent(DeviceSession session) =>
      currentSessionId != null && session.sessionId == currentSessionId;

  bool isRevoking(DeviceSession session) => revoking.contains(session.sessionId);

  factory SessionsState.loading() =>
      const SessionsState(status: SessionsStatus.loading);

  SessionsState copyWith({
    SessionsStatus? status,
    List<DeviceSession>? sessions,
    String? currentSessionId,
    String? message,
    Set<String>? revoking,
  }) =>
      SessionsState(
        status: status ?? this.status,
        sessions: sessions ?? this.sessions,
        currentSessionId: currentSessionId ?? this.currentSessionId,
        message: message,
        revoking: revoking ?? this.revoking,
      );
}

final sessionsControllerProvider =
    NotifierProvider<SessionsController, SessionsState>(SessionsController.new);

/// Loads the shopkeeper's active devices and revokes individual sessions.
///
/// The list is always re-read from the backend after a revoke, so what the
/// shopkeeper sees is server truth — never an optimistic guess that could hide
/// a device that is still signed in.
class SessionsController extends Notifier<SessionsState> {
  @override
  SessionsState build() => SessionsState.loading();

  SessionsRepository get _repo => ref.read(sessionsRepositoryProvider);

  Future<void> load() async {
    state = SessionsState.loading();
    final tokenStore = ref.read(tokenStoreProvider);
    final token = await tokenStore.readAccessToken();
    final currentSessionId = await tokenStore.readSessionId();

    if (token == null) {
      state = SessionsState(
        status: SessionsStatus.error,
        currentSessionId: currentSessionId,
        message: 'Sign in again to see your active devices.',
      );
      return;
    }
    try {
      final sessions = await _repo.fetchSessions(token);
      state = SessionsState(
        status: SessionsStatus.ready,
        sessions: sessions,
        currentSessionId: currentSessionId,
      );
    } on ApiException catch (e) {
      state = SessionsState(
        status: SessionsStatus.error,
        currentSessionId: currentSessionId,
        message: e.message,
      );
    } catch (_) {
      state = SessionsState(
        status: SessionsStatus.error,
        currentSessionId: currentSessionId,
        message: 'Could not load your active devices.',
      );
    }
  }

  /// Revokes one device, then reloads.
  ///
  /// Returns `null` on success, otherwise the failure copy for the caller to
  /// surface (a SnackBar). The list itself is refreshed either way: a "failed"
  /// revoke can still mean the device is gone (revoked from elsewhere), and the
  /// only honest answer is what the server reports next.
  Future<String?> revoke(String sessionId) async {
    if (state.revoking.contains(sessionId)) return null;
    final token = await ref.read(tokenStoreProvider).readAccessToken();
    if (token == null) return 'Sign in again to manage your devices.';

    state = state.copyWith(revoking: {...state.revoking, sessionId});

    String? failure;
    try {
      await _repo.revokeSession(sessionId, token);
    } on ApiException catch (e) {
      failure = e.message;
    } catch (_) {
      failure = 'Could not sign that device out.';
    }

    await load();
    return failure;
  }

  /// Clears cached devices on logout so the next account starts empty.
  void reset() => state = SessionsState.loading();
}