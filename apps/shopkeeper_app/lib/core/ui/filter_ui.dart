/// Reusable filter UI — the vocabulary every filterable list in the app
/// speaks (products, inventory scopes, offers).
///
/// Three primitives, ONE state protocol so filter behaviour stays predictable:
///
///  * [FilterChipBar] — a single-select row of quick facets shown OUTSIDE the
///    sheet (stock slices, offer buckets). Tapping is an immediate commit.
///  * [FilterSection] / [FilterDropdown] — the labelled building blocks
///    INSIDE a sheet; a dropdown always offers an explicit "Any" so clearing
///    is one tap, never a hidden gesture.
///  * [FilterSheet] — the bottom-sheet frame that owns the Reset / Apply
///    protocol: **Reset** clears the sheet's draft AND re-applies the empty
///    filter without closing (the list behind updates immediately, so the
///    sheet can never display one thing while the list shows another);
///    **Apply** commits the draft atomically and closes the sheet.
library;

import 'package:flutter/material.dart';

/// One selectable value in a [FilterChipBar].
class FilterChoice<T> {
  const FilterChoice({required this.value, required this.label});

  /// The value reported to [FilterChipBar.onSelected].
  final T value;

  /// The chip's visible label.
  final String label;
}

/// Horizontally scrollable row of single-select filter chips.
///
/// The active chip is exposed to assistive tech via [Semantics.selected] so
/// the selection is never communicated by colour alone, and the chip padding
/// lifts each chip to a 44dp touch target.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
  });

  /// The choices, in display order.
  final List<FilterChoice<T>> options;

  /// The currently committed value.
  final T selected;

  /// Reports a newly chosen value — callers commit immediately (a chip tap
  /// is not a draft).
  final ValueChanged<T> onSelected;

  /// Padding around the scroll view (the caller's layout owns the spacing).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final (index, choice) in options.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            _FilterChipVisual(
              label: choice.label,
              selected: choice.value == selected,
              onTap: () => onSelected(choice.value),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChipVisual extends StatelessWidget {
  const _FilterChipVisual({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled facet inside a filter sheet.
class FilterSection extends StatelessWidget {
  const FilterSection({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Single-choice dropdown with an explicit "Any" (no filter) option, so
/// clearing a selection is one tap instead of a hidden gesture.
class FilterDropdown extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.anyLabel = 'Any',
  });

  /// The selectable values (the "Any" option is added here).
  final List<String> options;

  /// The current value; `null` means "Any".
  final String? value;

  /// Reports the new value, including `null` when "Any" was chosen.
  final ValueChanged<String?> onChanged;

  /// Label of the "no filter" option.
  final String anyLabel;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(anyLabel)),
        for (final option in options)
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// The bottom-sheet frame every filter sheet is built on.
///
/// Owns the chrome (title, keyboard-safe padding, scrollability) and the
/// Reset / Apply protocol — the sheet content only collects a DRAFT:
///
///  * **Reset** ([onReset]) — clears the draft widgets AND re-applies the
///    empty filter. It does NOT close the sheet: the list behind updates and
///    the cleared widgets stay visible, so the two can never disagree.
///  * **Apply** ([onApply]) — commits the whole draft in one step (callers
///    hand back a full query via an explicit "every facet" method, never a
///    `copyWith` that would swallow a `null` clear) and pops the sheet.
class FilterSheet extends StatelessWidget {
  const FilterSheet({
    super.key,
    required this.title,
    required this.onReset,
    required this.onApply,
    required this.children,
  });

  /// The sheet's heading, e.g. `Filter products`.
  final String title;

  /// Clears the draft and applies the empty filter (sheet stays open).
  final VoidCallback onReset;

  /// Commits the draft; implementations are expected to pop the sheet.
  final VoidCallback onApply;

  /// The sheet's facet sections, in display order.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onReset, child: const Text('Reset')),
              const SizedBox(width: 8),
              FilledButton(onPressed: onApply, child: const Text('Apply')),
            ],
          ),
        ],
      ),
    );
  }
}
