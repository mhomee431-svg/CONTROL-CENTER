import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../l10n/app_text.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// SYSTEM STATES — the nine conditions any async surface in the app can be in.
///
/// WHY ONE FILE OWNS THIS
///
/// Every feature screen used to render its own `_ErrorView` / `_MessageView`
/// with a hardcoded icon, a hardcoded "Retry" and whatever string the
/// controller happened to keep. That produced two defects:
///
///  1. No screen could tell an *offline* failure from a *server* failure, so a
///     shopkeeper with no network was told "Something went wrong" (or, worse,
///     shown Dio's raw text).
///  2. The way out was always "Retry" — even when retrying cannot possibly
///     help (a 403, an expired session, a 503 outage).
///
/// The nine states below are the app's whole error/empty vocabulary. A state
/// owns its copy, icon and the ONE action that actually helps:
///
/// | State            | Real trigger (backend evidence)                    | Action      |
/// |------------------|----------------------------------------------------|-------------|
/// | offline          | `DioExceptionType.connectionError` / socket error   | Retry       |
/// | networkError     | DNS/TLS failures, no response at all                | Retry       |
/// | timeout          | connect/send/receive timeout                        | Retry       |
/// | serverError      | 5xx (`INTERNAL_ERROR` and its typed 500s)           | Retry       |
/// | permissionDenied | 403 `FORBIDDEN` / `PERMISSION_DENIED`               | Switch shop |
/// | sessionExpired   | 401 "Invalid or expired token" / "…has been revoked"| Sign in     |
/// | unauthorized     | 401 "Not authenticated" / "Invalid token type"      | Sign in     |
/// | maintenance      | 503 `SERVICE_UNAVAILABLE` / `STORAGE_UNAVAILABLE`   | Retry       |
/// | notFound         | 404                                                 | (feature)   |
/// | conflict         | 409                                                 | Retry       |
/// | validation       | 422                                                 | (feature)   |
/// | genericRetry     | other 4xx the server explained (429/unknown)        | Retry       |
/// | empty            | a successful load that legitimately has nothing     | (feature)   |
///
/// Rendering lives in `system_state_view.dart`; this file stays pure Dart
/// vocabulary + classification so it is testable without a widget tree.
/// ─────────────────────────────────────────────────────────────────────────────

/// The app-wide states. Every screen is in exactly one of them (or is
/// loading / showing content).
enum SystemState {
  /// The device itself has no usable network.
  offline,

  /// The network exists but the request never completed (DNS, TLS).
  networkError,

  /// The request was sent but the server never answered in time.
  timeout,

  /// The backend answered 5xx.
  serverError,

  /// The account is not allowed to touch this shop/resource (403).
  permissionDenied,

  /// The stored session is gone — signing in again is the ONLY fix.
  sessionExpired,

  /// The request carried no usable authentication (app-level auth state).
  unauthorized,

  /// The backend is up but deliberately not serving (503).
  maintenance,

  /// The referenced resource does not exist (404).
  notFound,

  /// The change collides with the server's current state (409).
  conflict,

  /// The payload failed server-side validation (422).
  validation,

  /// Anything else the server explained (429/unknown).
  genericRetry,

  /// A successful, genuinely empty result.
  empty,
}

/// Why a request failed *before* an HTTP status existed.
///
/// Classified once, in `ApiException.fromDioError`, so the whole app shares the
/// same reading of a transport failure.
enum ApiFailureKind {
  /// No usable network on the device (`DioExceptionType.connectionError`,
  /// socket errors).
  offline,

  /// The request was sent but never answered in time (connect/send/receive
  /// timeout) or the transport failed mid-flight.
  timeout,

  /// The caller cancelled the request — not a user-facing failure.
  cancelled,

  /// An HTTP response arrived (possibly an error envelope).
  badResponse,

  /// Unclassified transport failure — treated as [timeout] semantics (the
  /// request could not be completed) unless a response proves otherwise.
  unknown,
}

/// The single action that actually improves a state.
enum SystemAction {
  /// Re-issue the request.
  retry,

  /// Send the shopkeeper back through sign-in.
  signIn,

  /// Pick a different shop they do have access to.
  switchShop,

  /// Nothing to offer — the feature owns the call to action (empty states).
  none,
}

/// Copy + icon + action for one [SystemState].
@immutable
class SystemStateSpec {
  const SystemStateSpec({
    required this.state,
    required this.title,
    required this.message,
    required this.icon,
    required this.action,
  });

  final SystemState state;

  /// Short headline (never a raw exception string).
  final String title;

  /// One actionable sentence.
  final String message;

  final IconData icon;

  final SystemAction action;

  /// True when the state's whole copy belongs to the app because the server
  /// has nothing useful to say: a Dio message ("The connection errored: …") or
  /// an infrastructure 503 is implementation-speak, never shopkeeper copy.
  bool get ownsCopy => switch (state) {
    SystemState.offline ||
    SystemState.networkError ||
    SystemState.timeout ||
    SystemState.sessionExpired ||
    SystemState.unauthorized ||
    SystemState.maintenance ||
    SystemState.empty => true,
    _ => false,
  };

  /// Default copy for [state] — the ONE place these strings exist.
  static SystemStateSpec of(SystemState state, AppLocalizations text) => switch (state) {
    SystemState.offline => SystemStateSpec(
      state: SystemState.offline,
      title: text.commonNoInternetConnection,
      message:
          text.systemStateCheckYourMobileDataOr,
      icon: Icons.wifi_off_rounded,
      action: SystemAction.retry,
    ),
    SystemState.networkError => SystemStateSpec(
      state: SystemState.networkError,
      title: text.commonNetworkProblem,
      message:
          text.systemStateWeCouldNotReachThe,
      icon: Icons.cloud_off_outlined,
      action: SystemAction.retry,
    ),
    SystemState.timeout => SystemStateSpec(
      state: SystemState.timeout,
      title: text.commonTheServerTookTooLong,
      message:
          text.systemStateTheRequestTimedOutBefore,
      icon: Icons.hourglass_top_rounded,
      action: SystemAction.retry,
    ),
    SystemState.serverError => SystemStateSpec(
      state: SystemState.serverError,
      title: text.commonServerError,
      message: text.systemStateSomethingWentWrongOnOur,
      icon: Icons.dns_outlined,
      action: SystemAction.retry,
    ),
    SystemState.permissionDenied => SystemStateSpec(
      state: SystemState.permissionDenied,
      title: text.commonNoAccessToThisShop,
      message:
          text.systemStateYourAccountIsNotAllowed,
      icon: Icons.lock_outline,
      action: SystemAction.switchShop,
    ),
    SystemState.sessionExpired => SystemStateSpec(
      state: SystemState.sessionExpired,
      title: text.commonSessionExpired,
      message:
          text.systemStateForYourSecurityYouWere,
      icon: Icons.lock_clock_outlined,
      action: SystemAction.signIn,
    ),
    SystemState.unauthorized => SystemStateSpec(
      state: SystemState.unauthorized,
      title: text.commonSignInRequired,
      message: text.systemStateYouAreNotSignedIn,
      icon: Icons.no_accounts_outlined,
      action: SystemAction.signIn,
    ),
    SystemState.maintenance => SystemStateSpec(
      state: SystemState.maintenance,
      title: text.commonUnderMaintenance,
      message:
          text.systemStateWeAreDoingAShort,
      icon: Icons.engineering_outlined,
      action: SystemAction.retry,
    ),
    SystemState.notFound => SystemStateSpec(
      state: SystemState.notFound,
      title: text.commonNotFound,
      message: text.systemStateWeCouldNotFindThat,
      icon: Icons.search_off_rounded,
      // Retrying an identical 404 cannot succeed — the caller decides whether
      // its own context makes a Retry meaningful (the view still renders a
      // caller-supplied onRetry as a fallback).
      action: SystemAction.none,
    ),
    SystemState.conflict => SystemStateSpec(
      state: SystemState.conflict,
      title: text.commonThatChangeConflicts,
      message:
          text.systemStateSomethingWasAlreadyUpdatedRefresh,
      icon: Icons.rule_rounded,
      action: SystemAction.retry,
    ),
    SystemState.validation => SystemStateSpec(
      state: SystemState.validation,
      title: text.commonCheckTheDetails,
      message:
          text.systemStateSomeOfTheInformationIs,
      icon: Icons.fact_check_outlined,
      // Resending identical input can never pass validation — the shopkeeper
      // has to change something first.
      action: SystemAction.none,
    ),
    SystemState.genericRetry => SystemStateSpec(
      state: SystemState.genericRetry,
      title: text.commonSomethingWentWrong3,
      message: text.systemStateTheActionCouldNotBe,
      icon: Icons.error_outline,
      action: SystemAction.retry,
    ),
    SystemState.empty => SystemStateSpec(
      state: SystemState.empty,
      title: text.commonNothingHereYet,
      message: text.systemStateThereIsNothingToShow,
      icon: Icons.inbox_outlined,
      action: SystemAction.none,
    ),
  };

  /// Map a failure onto one of the system states.
  ///
  /// Order is deliberate: with an HTTP status, the status decides (503 is the
  /// backend's fail-closed outage signal; 401 splits by the evidence in the
  /// message — `dependencies.py` returns `UNAUTHORIZED` for both "Not
  /// authenticated" and "Invalid or expired token" / "Token has been revoked";
  /// 403 is a scope problem; any other 5xx is a server fault; 404/409/422 each
  /// name their own state because the fix differs — a different target, a
  /// refresh first, corrected input — and only the remaining 4xx (429 and
  /// friends) are genuinely worth a plain retry).
  ///
  /// Without a status the request never got an answer, but the evidence may
  /// still say what happened: a code or a message from the transport layer,
  /// and only then the [ApiFailureKind].
  static SystemState classify({
    int? statusCode,
    String? errorCode,
    ApiFailureKind? failureKind,
    String? message,
  }) {
    final code = (errorCode ?? '').trim().toUpperCase();
    final text = (message ?? '').toLowerCase();

    if (statusCode != null) {
      if (statusCode == 503) return SystemState.maintenance;
      if (statusCode == 401) {
        final expired =
            code == 'TOKEN_EXPIRED' ||
            code == 'SESSION_EXPIRED' ||
            code == 'INVALID_TOKEN' ||
            text.contains('expired') ||
            text.contains('revoked');
        return expired ? SystemState.sessionExpired : SystemState.unauthorized;
      }
      if (statusCode == 403) return SystemState.permissionDenied;
      if (statusCode >= 500) return SystemState.serverError;
      // The request itself was the problem, and each class has a different
      // fix: a 404 needs a different target, a 409 needs a refresh first, a
      // 422 needs corrected input — only 429/unknown benefit from a plain
      // retry, so they stay genericRetry.
      if (statusCode == 404) return SystemState.notFound;
      if (statusCode == 409) return SystemState.conflict;
      if (statusCode == 422) return SystemState.validation;
      return SystemState.genericRetry;
    }

    // No HTTP status — fall back to whatever evidence exists.
    final fromCode = _stateFromCode(code);
    if (fromCode != null) return fromCode;
    final fromText = _stateFromText(text);
    if (fromText != null) return fromText;

    return switch (failureKind) {
      ApiFailureKind.offline => SystemState.offline,
      ApiFailureKind.cancelled => SystemState.genericRetry,
      ApiFailureKind.badResponse => SystemState.genericRetry,
      ApiFailureKind.timeout => SystemState.timeout,
      _ => SystemState.networkError,
    };
  }

  /// Server/transport error code → state. Null when the code says nothing.
  static SystemState? _stateFromCode(String code) => switch (code) {
    'SERVICE_UNAVAILABLE' ||
    'STORAGE_UNAVAILABLE' ||
    'MAINTENANCE' => SystemState.maintenance,
    'TOKEN_EXPIRED' || 'SESSION_EXPIRED' || 'INVALID_TOKEN' =>
      SystemState.sessionExpired,
    'FORBIDDEN' || 'PERMISSION_DENIED' => SystemState.permissionDenied,
    'UNAUTHORIZED' || 'NOT_AUTHENTICATED' || 'MISSING_TOKEN' =>
      SystemState.unauthorized,
    'INTERNAL_ERROR' || 'SERVER_ERROR' => SystemState.serverError,
    _ => null,
  };

  /// Free-text evidence → state. Null when the text says nothing.
  static SystemState? _stateFromText(String text) {
    if (text.contains('maintenance')) return SystemState.maintenance;
    if (text.contains('expired') || text.contains('revoked')) {
      return SystemState.sessionExpired;
    }
    return null;
  }

  /// Recognise the app's OWN canonical copy.
  ///
  /// Controllers very often keep only the message string (their `error` status
  /// has no room for a status code). Because the transport copy is written HERE,
  /// matching it back to its state is exact — never a guess — which lets the
  /// shared view pick the right icon and action even on screens that were not
  /// handed a status code.
  static SystemState? fromMessage(String? message) {
    final text = (message ?? '').trim();
    if (text.isEmpty) return null;
    for (final state in SystemState.values) {
      if (of(state, appTextStatic()).message == text) return state;
    }
    return null;
  }

  /// THE entry point for screens.
  ///
  /// [state] wins when the feature already knows (e.g. a `*Status.accessDenied`
  /// branch); otherwise the state is classified from whatever evidence the
  /// caller has, falling back to recognising the app's own copy and finally to
  /// [SystemState.genericRetry].
  ///
  /// [title] and [message] are optional overrides so an existing screen keeps
  /// its hand-written wording verbatim — this layer adds states, it never
  /// rewrites a feature's copy.
  static SystemStateSpec resolve({
    SystemState? state,
    int? statusCode,
    String? errorCode,
    ApiFailureKind? failureKind,
    String? title,
    String? message,
    String? fallbackMessage,
    required AppLocalizations text,
  }) {
    final evidence = (message ?? '').trim().isNotEmpty
        ? message!.trim()
        : ((fallbackMessage ?? '').trim().isNotEmpty
              ? fallbackMessage!.trim()
              : null);

    final resolved =
        state ??
        (statusCode != null || failureKind != null
            ? classify(
                statusCode: statusCode,
                errorCode: errorCode,
                failureKind: failureKind,
                message: evidence,
              )
            : fromMessage(evidence) ?? SystemState.genericRetry);
    final base = of(resolved, text);
    return SystemStateSpec(
      state: base.state,
      title: (title ?? '').trim().isEmpty ? base.title : title!.trim(),
      message: base.ownsCopy || evidence == null ? base.message : evidence,
      icon: base.icon,
      action: base.action,
    );
  }
}