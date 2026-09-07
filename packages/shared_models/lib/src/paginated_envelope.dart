import 'api_envelope.dart';

/// Pagination metadata returned inside a [PaginatedEnvelope].
///
/// Mirrors the `pagination` object built by `paginated_response()` in
/// `backend/app/core/api_responses.py`.
class PaginationMeta {
  const PaginationMeta({
    required this.total,
    required this.page,
    required this.limit,
    required this.pages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory PaginationMeta.fromJson(dynamic json) {
    final map = (json is Map<String, dynamic>)
        ? json
        : throw ArgumentError.value(
            json, 'json', 'expected a decoded JSON object for PaginationMeta');
    return PaginationMeta(
      total: (map['total'] as num?)?.toInt() ?? 0,
      page: (map['page'] as num?)?.toInt() ?? 1,
      limit: (map['limit'] as num?)?.toInt() ?? 0,
      pages: (map['pages'] as num?)?.toInt() ?? 0,
      hasNext: map['has_next'] == true,
      hasPrev: map['has_prev'] == true,
    );
  }

  final int total;
  final int page;
  final int limit;
  final int pages;
  final bool hasNext;
  final bool hasPrev;

  Map<String, dynamic> toJson() => {
        'total': total,
        'page': page,
        'limit': limit,
        'pages': pages,
        'has_next': hasNext,
        'has_prev': hasPrev,
      };
}

/// Typed view over `paginated_response()` bodies:
///
/// ```json
/// {"success": true, "message": "Success",
///  "data": {"items": [...],
///           "pagination": {"total": 100, "page": 1, "limit": 20,
///                          "pages": 5, "has_next": true, "has_prev": false}}}
/// ```
class PaginatedEnvelope extends ApiEnvelope {
  const PaginatedEnvelope({
    required super.success,
    required super.message,
    super.errorCode,
    required this.items,
    required this.pagination,
  });

  factory PaginatedEnvelope.fromJson(dynamic json) {
    final base = ApiEnvelope.fromJson(json);
    final data = (base.data is Map<String, dynamic>)
        ? base.data as Map<String, dynamic>
        : throw ArgumentError.value(
            json, 'json', 'expected a paginated envelope with a data object');
    return PaginatedEnvelope(
      success: base.success,
      message: base.message,
      errorCode: base.errorCode,
      items: (data['items'] as List?) ?? const [],
      pagination: data['pagination'] == null
          ? null
          : PaginationMeta.fromJson(data['pagination']),
    );
  }

  /// Raw decoded item list — each app maps elements to its own model.
  final List<dynamic> items;

  final PaginationMeta? pagination;
}
