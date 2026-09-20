/// One node of the product taxonomy (`GET /api/v1/categories`).
///
/// The backend stores BOTH levels in one table: a subcategory is simply a row
/// whose `parent_id` points at a top-level category. The list is therefore
/// flat, and the cascade is derived locally — no second request when the
/// shopkeeper picks a category.
class CategoryOption {
  const CategoryOption({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final int id;
  final String name;

  /// Non-null only for a subcategory. `null` means "top level".
  final int? parentId;

  /// Backend display order — the list keeps the server's ordering.
  final int sortOrder;

  /// Inactive rows are hidden from the picker; they cannot be filed under.
  final bool isActive;

  bool get isSubcategory => parentId != null;

  factory CategoryOption.fromJson(Map<String, dynamic> json) =>
      CategoryOption(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        parentId: (json['parent_id'] as num?)?.toInt(),
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );

  static List<CategoryOption> listFrom(dynamic raw) => raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .map(CategoryOption.fromJson)
          .toList(growable: false)
      : const <CategoryOption>[];
}

/// A one-shot index over the flat taxonomy, built once per fetch.
///
/// This is what keeps the form fast: picking a category resolves its
/// subcategories with a map lookup in O(1), so the second dropdown updates on
/// the same frame instead of waiting on a network round trip. Rebuilt only
/// when the server payload actually changes.
class CategoryTaxonomy {
  CategoryTaxonomy(List<CategoryOption> rows) : _rows = _ordered(rows) {
    for (final row in _rows) {
      final parent = row.parentId;
      if (parent == null) {
        _topLevel.add(row);
      } else {
        (_children[parent] ??= []).add(row);
      }
    }
  }

  /// Active rows only, server order preserved (sort_order, then id for a
  /// stable tiebreak).
  static List<CategoryOption> _ordered(List<CategoryOption> rows) {
    final usable =
        rows.where((r) => r.isActive && r.id > 0 && r.name.isNotEmpty).toList()
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
          });
    return List.unmodifiable(usable);
  }

  final List<CategoryOption> _rows;
  final List<CategoryOption> _topLevel = [];
  final Map<int, List<CategoryOption>> _children = {};

  /// Top-level categories, in server order.
  List<CategoryOption> get topLevel => _topLevel;

  /// All rows (top level + children), for lookups and tests.
  List<CategoryOption> get rows => _rows;

  /// Subcategories of [categoryId] — an empty list when it has none, which is
  /// exactly the signal to hide the second dropdown.
  List<CategoryOption> childrenOf(int categoryId) =>
      _children[categoryId] ?? const [];

  /// A row by id, or null. Used to re-resolve a selection after a reload.
  CategoryOption? byId(int? id) =>
      id == null ? null : _rows.where((r) => r.id == id).firstOrNull;
}
