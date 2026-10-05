import 'dart:async';

import 'package:dio/dio.dart';

import '../security/safe_logger.dart';

/// Interceptor that automatically retries failed requests with exponential
/// backoff — but only when doing so is provably safe.
///
/// Safe means the request is a read ([_idempotentMethods]), or the backend has
/// been confirmed to collapse replays of it ([_serverConfirmedIdempotentPaths]).
///
/// ## The current state, stated plainly
/// ------------------------------------
/// Only reads are retried. Mutations are not, because this backend has no
/// header-based idempotency to lean on — its key handling lives in request
/// bodies on three merchant endpoints the customer app never calls. Attaching an
/// `Idempotency-Key` header therefore buys nothing today, and treating its
/// presence as a safety signal would be actively dangerous: the client would
/// retry a mutation the server would happily perform twice.
class ExponentialRetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration initialDelay;

  ExponentialRetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.initialDelay = const Duration(milliseconds: 800),
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final requestOptions = err.requestOptions;
    final retries = requestOptions.extra['retry_count'] ?? 0;

    if (shouldRetry(err) && retries < maxRetries) {
      requestOptions.extra['retry_count'] = retries + 1;
      final delay =
          initialDelay *
          (1 << retries); // Exponential backoff: 800ms, 1600ms, 3200ms

      SafeLogger.warning(
        'Retrying request [${requestOptions.path}] (Attempt ${retries + 1}/$maxRetries) in ${delay.inMilliseconds}ms...',
      );

      await Future.delayed(delay);

      try {
        final response = await dio.fetch(requestOptions);
        return handler.resolve(response);
      } on DioException catch (retryErr) {
        return super.onError(retryErr, handler);
      }
    }

    return super.onError(err, handler);
  }

  /// Whether a failed request may be retried automatically.
  ///
  /// ## The rule
  ///
  /// * **GET / HEAD** — always retryable. Re-running a read changes nothing.
  ///
  /// * **POST / PUT / PATCH / DELETE** — retryable ONLY when the request
  ///   carries an `Idempotency-Key`.
  ///
  /// ## Why a mutation without a key must never retry
  ///
  /// The dangerous case is not "the request failed" but "the request SUCCEEDED
  /// and the response was lost" — a dropped connection on the way back, a
  /// timeout while the server was already writing. A blind retry then performs
  /// the side effect twice: two OTP SMS sent, a payment captured twice, an
  /// order created twice. The customer sees one action and gets two outcomes.
  /// No client-side timeout policy can distinguish this case from a genuine
  /// pre-flight failure, which is precisely why the decision has to come from
  /// the request itself.
  ///
  /// ## Why an idempotency key makes it safe
  ///
  /// The backend contract is: send `Idempotency-Key: <uuid>`, and a replay of
  /// that key returns the FIRST result instead of performing the work again.
  /// The app honours that contract for the endpoints that implement it (POS,
  /// subscriptions, merchant onboarding). With the key attached, a retry is
  /// safe by the server's own guarantee — so refusing to retry would be leaving
  /// reliability on the table for no reason.
  ///
  /// The key must be generated ONCE per logical operation and REUSED across
  /// attempts. A fresh key per attempt would defeat the entire mechanism, so
  /// this reads it from the request rather than minting one here.
  bool shouldRetry(DioException err) {
    final options = err.requestOptions;
    final method = options.method.toUpperCase();

    // Never retry a cancelled request. Cancellation is the USER saying stop —
    // the request was probably deliberate, and a background retry would race
    // whatever they just navigated to.
    if (err.type == DioExceptionType.cancel) return false;

    final isIdempotentMethod = _idempotentMethods.contains(method);
    // A mutation is retryable only when the SERVER has promised to collapse the
    // replay — not merely because a key is attached. See
    // [_serverConfirmedIdempotentPaths] for why that distinction is the whole
    // safety argument.
    final serverGuarantees = _serverGuaranteesCollapse(options);

    // A read is safe; a mutation is safe only by server contract.
    if (!isIdempotentMethod && !serverGuarantees) return false;

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode;
    return status != null && (status >= 500 || status == 429);
  }

  /// HTTP methods that are safe to re-run unconditionally.
  ///
  /// A read has no side effects, so replaying it cannot duplicate anything.
  static const Set<String> _idempotentMethods = {'GET', 'HEAD'};

  /// Endpoints whose BACKEND actually collapses a replayed `Idempotency-Key`.
  ///
  /// ## This set is empty, and that is deliberate
  /// -------------------------------------------
  /// Attaching an `Idempotency-Key` header is a *promise*, not a guarantee. It
  /// only means anything if the receiving server reads the header, records the
  /// key, and returns the first response instead of redoing the work.
  ///
  /// Auditing this backend found no `Idempotency-Key` header handling anywhere.
  /// Its idempotency is all in the request BODY (`payload.idempotency_key` on POS
  /// sync, merchant onboarding and inventory import jobs) — a different mechanism,
  /// on three endpoints the customer app does not call.
  ///
  /// So a header-only check would be false safety: the client would consider a
  /// mutation safely replayable, retry it, and the server would happily perform
  /// the side effect a second time. The customer sees one tap and gets two
  /// charges. That is strictly worse than not retrying at all, because it also
  /// *looks* handled in review.
  ///
  /// Adding a path here is the ONLY way to enable a mutation retry, and it should
  /// be done in the same commit that adds server-side key handling and a test
  /// proving the replay collapses. Until then every mutation fails closed.
  static const Set<String> _serverConfirmedIdempotentPaths = <String>{};

  /// Whether the server has promised to collapse a replay of this request.
  ///
  /// Requires BOTH a key and a path the server is known to honour. The key alone
  /// proves nothing — see [_serverConfirmedIdempotentPaths].
  static bool _serverGuaranteesCollapse(RequestOptions options) {
    if (_idempotencyKeyOf(options) == null) return false;
    return _serverConfirmedIdempotentPaths.contains(options.path);
  }

  /// The idempotency key attached to [options], or null.
  ///
  /// Read from the header so it is present on every attempt including retries —
  /// Dio replays the same [RequestOptions], so a header set once survives.
  static String? _idempotencyKeyOf(RequestOptions options) {
    for (final entry in options.headers.entries) {
      if (entry.key.toLowerCase() == _idempotencyHeader) {
        final value = entry.value;
        return (value is String && value.isNotEmpty) ? value : null;
      }
    }
    return null;
  }

  /// Canonical header name, compared case-insensitively above.
  static const String _idempotencyHeader = 'idempotency-key';

  /// Marks [options] with an idempotency key.
  ///
  /// **Attaching a key does NOT by itself make the request retryable.** It only
  /// does so for paths in [_serverConfirmedIdempotentPaths], which is currently
  /// empty because this backend does not read the header. This method is kept so
  /// the key travels with the request and is visible in logs/contracts, but
  /// callers must not read it as "this mutation is now safe to replay".
  ///
  /// To actually enable a retry, add the path to
  /// [_serverConfirmedIdempotentPaths] in the same change that implements
  /// server-side key handling.
  ///
  /// The key must be generated ONCE per logical operation and reused across every
  /// attempt. A fresh key per attempt would defeat the mechanism entirely, so it
  /// is minted by the caller and attached here rather than generated below.
  static void markIdempotent(RequestOptions options, String key) {
    options.headers[_idempotencyHeader] = key;
  }
}
