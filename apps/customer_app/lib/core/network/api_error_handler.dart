import 'package:dio/dio.dart';

enum ApiErrorType {
  offline,
  timeout,

  /// 401 — the token is missing, expired or rejected. The app can usually
  /// recover by refreshing, so it is separated from [accessDenied].
  sessionExpired,

  /// 403 — authenticated, but not allowed. Re-authenticating cannot help.
  accessDenied,

  notFound,

  /// 409 — the request conflicts with current state (usually "already done").
  conflict,

  /// 422 — the payload failed validation.
  validation,

  /// 429 — rate limited.
  rateLimited,

  serverError,
  requestCancelled,

  /// The request reached the server but the response was incomplete, or only
  /// part of a multi-part request succeeded.
  ///
  /// Distinct from [serverError] because the customer's next action differs:
  /// a 500 is worth retrying wholesale, whereas a partial failure often means
  /// some sections are still usable and the rest need a retry. Collapsing both
  /// into "server error" either discards good data or blocks the customer from
  /// content that already arrived.
  partialFailure,

  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  /// Builds a [ApiErrorType.partialFailure] for a caller that knows part of a
  /// response succeeded.
  ///
  /// Repositories use this when a composite fetch is only partly usable — for
  /// example product master loaded but shop inventory did not. The customer
  /// keeps the part that worked and is offered a retry for the rest, which is
  /// strictly better than replacing good content with an error screen.
  const ApiException.partial({required this.message, this.statusCode})
    : type = ApiErrorType.partialFailure;

  /// Whether retrying the same request could plausibly succeed.
  ///
  /// Drives whether the UI offers "Retry" at all. Offering it for a 403, 404 or
  /// 409 would trap the customer on a button that can never work — which the
  /// spec explicitly forbids ("do not trap the customer").
  ///
  /// [rateLimited] and [validation] are also excluded: the first needs the
  /// customer to wait, the second needs them to change something.
  bool get isRetryable =>
      type == ApiErrorType.offline ||
      type == ApiErrorType.timeout ||
      type == ApiErrorType.serverError ||
      type == ApiErrorType.partialFailure;

  /// Whether the customer must sign in again before anything will work.
  bool get requiresSignIn => type == ApiErrorType.sessionExpired;

  /// Whether some content may still be usable despite the failure.
  bool get isPartial => type == ApiErrorType.partialFailure;

  factory ApiException.fromDioError(DioException dioError) {
    if (dioError.type == DioExceptionType.cancel) {
      return const ApiException(
        type: ApiErrorType.requestCancelled,
        message: 'Request was cancelled.',
      );
    }

    if (dioError.type == DioExceptionType.connectionTimeout ||
        dioError.type == DioExceptionType.receiveTimeout ||
        dioError.type == DioExceptionType.sendTimeout) {
      return const ApiException(
        type: ApiErrorType.timeout,
        message: 'Connection timed out. Please check your internet connection and try again.',
      );
    }

    if (dioError.type == DioExceptionType.connectionError) {
      return const ApiException(
        type: ApiErrorType.offline,
        message: 'No internet connection detected. Please connect to Wi-Fi or mobile data.',
      );
    }

    if (dioError.type == DioExceptionType.badCertificate) {
      // A TLS failure means we are connected to *something* that is not our
      // server (captive portal, interception). Calling it "offline" would be
      // wrong; the honest framing is that the connection is not secure.
      return const ApiException(
        type: ApiErrorType.partialFailure,
        message: 'We could not establish a secure connection. Please try again on a trusted network.',
      );
    }

    final response = dioError.response;
    if (response != null) {
      return _fromStatus(response);
    }

    return ApiException(
      type: ApiErrorType.unknown,
      statusCode: response?.statusCode,
      message: dioError.message ?? 'An unexpected network error occurred.',
    );
  }

  /// Maps an HTTP response to an [ApiException].
  ///
  /// Extracted from [fromDioError] so the status-code table can be tested
  /// directly against synthetic responses — the point of the mapping is that
  /// every code produces a specific, readable message, and that is impossible
  /// to verify while it is buried in a catch block.
  ///
  /// Two rules govern every branch:
  ///
  ///  * **Never surface a raw body.** Backend `detail`/`message` fields are used
  ///    only when they pass [_safeBackendMessage]; a stack trace, HTML error
  ///    page or internal exception string must never reach a customer.
  ///  * **Never surface a raw status code to the UI.** "HTTP 409" tells a
  ///    shopper nothing; "This is already in your saved list" does. Codes are
  ///    still recorded on [ApiException.statusCode] for logs and tests.
  static ApiException _fromStatus(Response<dynamic> response) {
    final code = response.statusCode;
    final backend = _safeBackendMessage(response.data);

    switch (code) {
      // ── Session / authentication ──────────────────────────────────────
      // Distinct from 403 on purpose: a 401 means "we don't know who you are"
      // and the app can (and does) transparently refresh the token, whereas a
      // 403 means "we know exactly who you are and the answer is no". Telling
      // a customer to "log in again" for a 403 would send them round a loop
      // that cannot succeed.
      case 401:
        return ApiException(
          type: ApiErrorType.sessionExpired,
          statusCode: code,
          message: 'Your session has expired. Please sign in again.',
        );

      // ── Access denied ─────────────────────────────────────────────────
      case 403:
        return ApiException(
          type: ApiErrorType.accessDenied,
          statusCode: code,
          message:
              backend ??
              'You do not have access to this. If you think this is wrong, '
                  'please contact support.',
        );

      // ── Not found ─────────────────────────────────────────────────────
      case 404:
        return ApiException(
          type: ApiErrorType.notFound,
          statusCode: code,
          message: backend ?? 'This is no longer available.',
        );

      // ── Conflict ──────────────────────────────────────────────────────
      // Almost always "you already did this". Retrying is pointless, so
      // isRetryable stays false and the UI offers a way forward instead.
      case 409:
        return ApiException(
          type: ApiErrorType.conflict,
          statusCode: code,
          message:
              backend ?? 'This has already been done. Nothing else to change.',
        );

      // ── Validation ────────────────────────────────────────────────────
      // The backend's field-level detail is genuinely useful here ("Enter a
      // 10-digit mobile number"), so it is preferred over generic copy.
      case 422:
        return ApiException(
          type: ApiErrorType.validation,
          statusCode: code,
          message: backend ?? 'Some of the details you entered are not valid.',
        );

      // ── Rate limited ──────────────────────────────────────────────────
      case 429:
        return ApiException(
          type: ApiErrorType.rateLimited,
          statusCode: code,
          message:
              backend ??
              'Too many attempts. Please wait a moment before trying again.',
        );

      default:
        if (code != null && code >= 500) {
          return ApiException(
            type: ApiErrorType.serverError,
            statusCode: code,
            // Deliberately omits the code. "Our team has been notified" is what
            // the customer can act on; a 502-vs-503 distinction is noise that
            // invites "so is it broken?".
            message:
                'Something went wrong on our side. Please try again in a '
                'moment.',
          );
        }
        if (code != null && code >= 400) {
          // Any other 4xx we do not model explicitly (e.g. 405, 418).
          return ApiException(
            type: ApiErrorType.unknown,
            statusCode: code,
            message: backend ?? 'That request could not be completed.',
          );
        }
        return ApiException(
          type: ApiErrorType.unknown,
          statusCode: code,
          message: 'Something went wrong. Please try again.',
        );
    }
  }

  /// Extracts a customer-safe message from a backend error body.
  ///
  /// Returns null — forcing the caller to fall back to its own copy — unless
  /// the text is short, single-line, and free of anything that smells like a
  /// stack trace or a framework exception. A FastAPI 500 body routinely
  /// contains `"Traceback (most recent call last): ..."`, and a default
  /// handler would render that string straight into a dialog.
  static String? _safeBackendMessage(dynamic body) {
    if (body is! Map) return null;

    // FastAPI puts field errors in `detail`; this backend's envelope uses
    // `message`. Both are considered.
    final raw = body['message'] ?? body['detail'];

    // Validation errors arrive as a list of per-field objects, not prose, so
    // there is nothing safe to lift out of them here.
    if (raw is! String) return null;

    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 160) return null;

    // Anything machine-generated is not customer-facing copy.
    final lowered = trimmed.toLowerCase();
    const forbidden = [
      'traceback',
      '  file "',
      'exception',
      'stack trace',
      'error: ',
      'nullreference',
      '.dart:',
      'sqlstate',
      'psycopg',
      'pydantic',
      'assertionerror',
      'typeerror',
      'valueerror',
      'keyerror',
    ];
    if (forbidden.any(lowered.contains)) return null;

    // A newline would break single-line surfaces such as a SnackBar.
    if (trimmed.contains('\n') || trimmed.contains('\r')) return null;

    return trimmed;
  }

  @override
  String toString() =>
      'ApiException [$type]: $message (Status Code: $statusCode)';
}

/// Maps any thrown error into a user-safe message suitable for display.
///
/// Raw exception text (`Exception: ...`, stack fragments, internal URLs)
/// must never reach the UI — it leaks implementation details and reads
/// badly. Known [ApiException]s already carry human-friendly copy; anything
/// else collapses to a generic, actionable message.
String friendlyErrorMessage(Object? error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please check your connection and try again.';
}

/// Whether [error] is a connectivity problem rather than a logical one.
///
/// Used to decide whether a failure should mark the device offline. A 404 or a
/// 422 proves the network works, so treating those as an outage would put a
/// false "You're offline" banner in front of a customer whose real problem is
/// a missing record.
bool isConnectivityError(Object? error) {
  if (error is! ApiException) return false;
  return error.type == ApiErrorType.offline ||
      error.type == ApiErrorType.timeout ||
      error.type == ApiErrorType.partialFailure;
}
