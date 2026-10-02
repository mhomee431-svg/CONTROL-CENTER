import 'package:flutter/material.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/ui/filter_ui.dart';
import '../../../products/domain/product_query.dart';

/// Bottom sheet to filter one inventory scope's list — the Inventory module's
/// half of the spec's filter set (Stock lives in the quick chips outside;
/// Category and Freshness are here).
///
/// Built on the shared [FilterSheet] frame, so it follows the same state
/// protocol as the products sheet: the widget state is a DRAFT of [initial];
/// *Reset* clears the draft AND applies the empty filter without closing;
/// *Apply* commits every facet atomically and closes. Search text, the stock
/// chips and the scope's own slice ride along in [initial] untouched —
/// `withFilters` replaces only the facets this sheet owns.
class InventoryFilterSheet extends StatefulWidget {
  const InventoryFilterSheet({
    super.key,
    required this.initial,
    required this.onApply,
    this.categories = const [],
  });

  /// The list's current USER query (search + facets). The sheet edits only
  /// the facets it shows and hands the whole query back.
  final ProductQuery initial;

  final ValueChanged<ProductQuery> onApply;

  /// Category values present in the loaded catalog — an empty list hides
  /// the picker entirely (never offer a filter that cannot match a row).
  final List<String> categories;

  @override
  State<InventoryFilterSheet> createState() => _InventoryFilterSheetState();
}

class _InventoryFilterSheetState extends State<InventoryFilterSheet> {
  String? _category;
  String? _freshness;

  @override
  void initState() {
    super.initState();
    _category = widget.initial.category;
    _freshness = widget.initial.freshness;
  }

  /// Clears every picker AND applies the empty filter in one step, so the
  /// sheet can never display one thing while the list behind it shows
  /// another (Apply would otherwise re-send the stale local selections).
  void _reset() {
    setState(() {
      _category = null;
      _freshness = null;
    });
    widget.onApply(widget.initial.clearFilters());
  }

  void _apply() {
    widget.onApply(widget.initial.withFilters(
      availability: widget.initial.availability,
      category: _category,
      brand: widget.initial.brand,
      minPrice: widget.initial.minPrice,
      maxPrice: widget.initial.maxPrice,
      recentlyUpdated: widget.initial.recentlyUpdated,
      freshness: _freshness,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return FilterSheet(
      title: 'Filter inventory',
      onReset: _reset,
      onApply: _apply,
      children: [
        if (widget.categories.isNotEmpty)
          FilterSection(
            label: appText(context).commonCategory,
            child: FilterDropdown(
              options: widget.categories,
              value: _category,
              onChanged: (value) => setState(() => _category = value),
            ),
          ),
        FilterSection(
          label: appText(context).commonFreshness,
          // Empty selection = Any — the facet is opt-in, exactly like the
          // products sheet's Availability segment.
          child: SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ProductQuery.freshnessFresh,
                label: Text(appText(context).commonFresh),
              ),
              ButtonSegment(
                value: ProductQuery.freshnessStale,
                label: Text(appText(context).commonNeedsUpdate),
              ),
            ],
            selected: _freshness == null
                ? const <String>{}
                : <String>{_freshness!},
            onSelectionChanged: (selection) => setState(
              () => _freshness = selection.isEmpty ? null : selection.first,
            ),
          ),
        ),
      ],
    );
  }
}
