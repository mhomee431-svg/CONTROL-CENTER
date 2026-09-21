import 'package:flutter/material.dart';

/// The page break of a paged catalog list: how many rows are still behind it,
/// and the one control that reveals them.
///
/// One implementation for every catalog-backed list (the products list, the
/// inventory scopes, the price list) so "load more" cannot drift between
/// screens — the same reason `LazyListView` exists. It carries its own key so
/// tests can reach it without knowing its label, and callers pass it only when
/// their page says there is something left to reveal.
class LoadMoreTile extends StatelessWidget {
  const LoadMoreTile({super.key, required this.hidden, required this.onTap});

  /// Matching rows the current page does not show yet.
  final int hidden;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.expand_more, size: 18),
          label: Text('Load more ($hidden remaining)'),
        ),
      ),
    );
  }
}
