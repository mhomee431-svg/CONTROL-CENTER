/// Typed view over the platform-wide API response envelope.
///
/// Every endpoint in the Hyperlocal backend wraps its payload with
/// `success_response()` / `error_response()` (see
/// `backend/app/core/responses.py`):
///
/// ```json
/// // success
/// {"success": true,  "message": "Success", "data": {...}}
///
/// // error
/// {"success": false, "message": "Shop not found",
///  "error_code": "SHOP_NOT_FOUND", "data": null}
/// ```
///
/// This class is the single shared Dart representation of that contract;
/// keeping it in one place prevents the customer / shopkeeper / admin apps
/// from drifting apart when the envelope evolves.
class ApiEnvelope {
  const ApiEnvelope({
    required this.success,
    required this.message,
    this.errorCode,
    this.data,
  });

  /// Parses a decoded JSON body (e.g. Dio `response.data`).
  factory ApiEnvelope.fromJson(dynamic json) {
    final map = (json is Map<String, dynamic>)
        ? json
        : throw ArgumentError.value(
            json, 'json', 'expected a decoded JSON object for ApiEnvelope');
    return ApiEnvelope(
      success: map['success'] == true,
      message: map['message'] as String? ?? '',
      errorCode: map['error_code'] as String?,
      data: map['data'],
    );
  }

  /// Whether the request succeeded (`success_response` envelope).
  final bool success;

  /// Human-readable message from the backend.
  final String message;

  /// Stable machine-readable error code (errors only, e.g. `SHOP_NOT_FOUND`).
  final String? errorCode;

  /// Raw decoded payload — cast via [dataAs] with the app's own model.
  final dynamic data;

  /// True when this is an error envelope.
  bool get isError => !success;

  /// Casts [data] to `T` (the app applies its own `fromJson`).
  T? dataAs<T>() => data is T ? data as T : null;

  Map<String, dynamic> toJson() => {
        'success': success,
        'message': message,
        if (errorCode != null) 'error_code': errorCode,
        'data': data,
      };

  @override
  String toString() =>
      'ApiEnvelope(success: $success, message: $message, '
      'errorCode: $errorCode, hasData: ${data != null})';
}
