import 'package:dio/dio.dart';

import '../errors/app_message_code.dart';
import '../l10n/app_text.dart';
import '../state/system_state.dart';

/// Normalized API failure carrying HTTP status and backend error code.
class ApiException implements Exception {
  final int? statusCode;
  final String? errorCode;
  final String message;

  /// Set when the wording for this failure lives in `app_en.arb` instead of at
  /// the throw site. [message] mirrors the English catalog so callers that
  /// cannot reach a `BuildContext` keep working; UI with a context should read
  /// [apiFailureText] to get the active locale.
  final AppMessageCode? messageCode;

  /// Transport classification: WHY the request failed before (or without) an
  /// HTTP answer. Populated by [ApiException.fromDioError]; defaults to
  /// [ApiFailureKind.unknown] for hand-built failures (tests, fakes).
  final ApiFailureKind kind;

  /// Raw `data` payload from the error envelope (if any). The barcode-lookup
  /// endpoint embeds the catalog matches inside a 300 / 404 error envelope,
  /// so callers can reconstruct the [BarcodeResolution] from this field.
  final dynamic data;

  const ApiException({
    this.statusCode,
    this.errorCode,
    required this.message,
    this.data,
    this.kind = ApiFailureKind.unknown,
    this.messageCode,
  });

  /// A failure the shopkeeper sees in their own language: the copy is looked
  /// up by [code] in the localization catalog, so the throw site carries a
  /// meaning and not an English sentence.
  ///
  /// Not `const` because the English mirror of [message] is read from the
  /// generated catalog.
  ApiException.localized(
    AppMessageCode code, {
    this.statusCode,
    this.errorCode,
    this.data,
    this.kind = ApiFailureKind.unknown,
  }) : messageCode = code,
       message = appMessageEnglish(code);

  /// True when the backend refused shop access (association/permission).
  bool get isForbidden => statusCode == 403;

  /// True when the session is no longer valid (401 unrecoverable).
  bool get isUnauthorized => statusCode == 401;

  /// 403 error codes the backend raises for PLAN/FEATURE refusals rather than
  /// shop-association denials — `EntitlementDenied` and `enforce_limit` in
  /// `backend/app/services/subscription/entitlements.py`
  /// (`ENTITLEMENT_DENIED`, `SUBSCRIPTION_EXPIRED`, `PLAN_LIMIT_REACHED`).
  static const Set<String> entitlementErrorCodes = {
    'ENTITLEMENT_DENIED',
    'SUBSCRIPTION_EXPIRED',
    'PLAN_LIMIT_REACHED',
  };

  /// True when a 403 is a subscription/entitlement refusal. The server's own
  /// message for these ("Your current plan does not include 'x'. Upgrade to
  /// unlock this feature.") is the actionable copy — screens must show it
  /// instead of a generic permission-denied fallback.
  bool get isEntitlementDenied =>
      isForbidden &&
      errorCode != null &&
      entitlementErrorCodes.contains(errorCode);

  /// Which of the nine system states this failure is.
  ///
  /// Screens use it to pick the copy, the icon and — most importantly — the ONE
  /// way out that can actually help (Retry vs Switch shop vs Sign in). See
  /// `core/state/system_state.dart`.
  SystemState get systemState => SystemStateSpec.classify(
    statusCode: statusCode,
    errorCode: errorCode,
    failureKind: kind,
    message: message,
  );

  factory ApiException.fromDioError(DioException e) {
    final response = e.response;
    final body = response?.data;
    final kind = _kindOf(e);
    final statusCode = response?.statusCode;
    String message = e.message ?? 'Network error';
    String? errorCode;
    dynamic errorData;
    var serverExplained = false;
    if (body is Map) {
      final bodyMessage = body['message'];
      if (bodyMessage is String && bodyMessage.isNotEmpty) {
        message = bodyMessage;
        serverExplained = true;
      }
      final code = body['error_code'];
      if (code is String) errorCode = code;
      errorData = body['data'];
    }
    // Infrastructure failures are NOT explained by the server:
    //   * a transport failure leaves us with Dio's `message`
    //     ("The connection errored: ..."), which is implementation-speak;
    //   * a 503 means the backend deliberately is not serving (fail-closed
    //     storage / OTP / queue outage), and its technical wording
    //     ("Object storage is unavailable") is not something a shopkeeper can
    //     act on.
    // Both get the app's own state copy instead, so EVERY screen — migrated or
    // not — shows the right thing (see SystemStateSpec.ownsCopy).
    if (statusCode == 503) {
      message = SystemStateSpec.of(
        SystemState.maintenance,
        appTextStatic(),
      ).message;
    } else if (!serverExplained) {
      message = switch (kind) {
        ApiFailureKind.offline => SystemStateSpec.of(
          SystemState.offline,
          appTextStatic(),
        ).message,
        ApiFailureKind.cancelled => 'Request was cancelled.',
        ApiFailureKind.timeout => SystemStateSpec.of(
          SystemState.timeout,
          appTextStatic(),
        ).message,
        ApiFailureKind.badResponse || ApiFailureKind.unknown =>
          SystemStateSpec.of(
            SystemState.networkError,
            appTextStatic(),
          ).message,
      };
    }
    return ApiException(
      statusCode: statusCode,
      errorCode: errorCode,
      message: message,
      data: errorData,
      kind: kind,
    );
  }

  /// Dio reports a transport failure as a *type*; the rest of the app needs a
  /// stable vocabulary. No response at all == the device could not reach the
  /// network (offline); a timeout == the network exists but the server did not
  /// answer in time.
  static ApiFailureKind _kindOf(DioException e) => switch (e.type) {
    DioExceptionType.cancel => ApiFailureKind.cancelled,
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => ApiFailureKind.timeout,
    DioExceptionType.connectionError => ApiFailureKind.offline,
    DioExceptionType.badResponse => ApiFailureKind.badResponse,
    DioExceptionType.badCertificate => ApiFailureKind.unknown,
    DioExceptionType.unknown =>
      e.response == null ? ApiFailureKind.offline : ApiFailureKind.unknown,
  };

  @override
  String toString() =>
      'ApiException($statusCode, $errorCode, $kind): $message';
}

/// Thin Dio wrapper for the Shopkeeper backend:
///   - unwraps the `{success, message, data}` envelope
///   - maps failures to [ApiException]
///   - exposes [onUnauthorized] so the app can force sign-out on 401
///
/// Auth headers are attached by repositories (they hold the token store),
/// keeping this class free of storage dependencies.
class ApiClient {
  ApiClient({required this.dio, this.onUnauthorized});

  final Dio dio;

  /// Invoked when a request fails with 401 (session revoked/expired).
  final void Function(ApiException error)? onUnauthorized;

  Options _options(String? token, {bool json = true}) => Options(
        headers: {
          'Accept': 'application/json',
          if (json) 'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    String? token,
  }) =>
      _send(() =>
          dio.get(path, queryParameters: query, options: _options(token)));

  Future<dynamic> post(String path, {Object? body, String? token}) =>
      _send(() => dio.post(path, data: body, options: _options(token)));

  Future<dynamic> put(String path, {Object? body, String? token}) =>
      _send(() => dio.put(path, data: body, options: _options(token)));

  Future<dynamic> patch(String path, {Object? body, String? token}) =>
      _send(() => dio.patch(path, data: body, options: _options(token)));

  Future<dynamic> delete(String path, {String? token}) =>
      _send(() => dio.delete(path, options: _options(token)));

  /// Multipart POST against this API (the backend-streamed upload path).
  ///
  /// `Content-Type` is deliberately NOT set: Dio writes
  /// `multipart/form-data; boundary=…` itself, and forcing the JSON type here
  /// would strip the boundary the server needs to parse the parts.
  Future<dynamic> postMultipart(
    String path, {
    required FormData form,
    String? token,
  }) =>
      _send(() => dio.post(path, data: form, options: _options(token, json: false)));

  /// POST a multipart form to an ABSOLUTE third-party URL (the signed S3
  /// upload endpoint).
  ///
  /// No `Authorization` header and no JSON content type are attached: the
  /// signature in the form already authorizes the write, and S3 rejects a
  /// request carrying credentials it did not sign for.
  Future<void> postFormToExternal(String url, {required FormData form}) async {
    try {
      await dio.post(
        url,
        data: form,
        options: Options(
          headers: const {'Accept': '*/*'},
          // S3 answers 204 on success; Dio must not treat it as an empty body.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() fn) async {
    try {
      final response = await fn();
      return _unwrap(response);
    } on DioException catch (e) {
      final mapped = ApiException.fromDioError(e);
      if (mapped.isUnauthorized) onUnauthorized?.call(mapped);
      throw mapped;
    }
  }

  dynamic _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
            if (body['success'] == true) return body['data'];
      throw ApiException(
        statusCode: response.statusCode,
        errorCode: body['error_code'] as String?,
        message: (body['message'] as String?) ?? 'Request failed',
        data: body['data'],
        kind: ApiFailureKind.badResponse,
      );
    }
    return body;
  }
}
