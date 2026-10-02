import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_text.dart';

/// A search text field that filters while typing AND debounces the parent's
/// filter call.
///
/// The products / inventory / price-list search boxes all filter a local
/// catalog on every keystroke. The `ProductSearch` predicate and its
/// `ProductQueryCache` make each filter cheap, but "cheap" on a 2,000-row
/// shop is still enough to make the keyboard lag if the full query (and its
/// provider rebuild) runs once per glyph.
///
/// Ownership: the field owns its [TextEditingController] (seeded from
/// [initialValue]) so a rebuild cannot steal the cursor; the PARENT still
/// owns the search text (the query state) and [onChanged] is the only
/// writer — the same `setSearch` each list already calls.
///
/// The filter call itself is debounced: each keystroke restarts a [delay]
/// timer, and the parent's [onChanged] fires only for values the timer
/// elapses on — **plus the still-pending text, immediately, when the field
/// loses focus or is submitted**. That flush keeps the visible rows
/// identical to the pre-debounce behaviour: a shopkeeper (or a test) who
/// types and immediately looks / taps / submits sees the matching rows,
/// while the provider/notification rebuild still happens at most once per
/// pause. The consumed value is tracked so the timer can never
/// double-deliver.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.onFocusLost,
    this.hintText = 'Search…',
    this.initialValue = '',
    this.delay = _kDefaultDelay,
    this.inputFormatters,
    this.recentSearches = const [],
    this.onRecentSelected,
    this.onRecentRemoved,
  });

  /// Called after [delay] has elapsed since the last keystroke (or
  /// immediately for the still-pending text on focus loss / submit / clear).
  final ValueChanged<String> onChanged;

  /// Called when the keyboard's search action fires.
  final ValueChanged<String>? onSubmitted;

  /// Called when the clear button is tapped.
  final VoidCallback? onCleared;

  /// Called when the field loses focus (tap outside). The still-pending
  /// text is flushed through [onChanged] first — receivers that record
  /// submitted searches (recent-searches history) hook here instead of
  /// duplicating the flush logic.
  final ValueChanged<String>? onFocusLost;

  final String hintText;

  /// The text the field starts with (the list's persisted query).
  final String initialValue;

  /// How long to wait after the last keystroke before firing [onChanged].
  final Duration delay;

  /// Optional input formatters (e.g. for SKU search that should be numeric).
  final List<TextInputFormatter>? inputFormatters;

  /// Recent submitted terms shown as a suggestion dropdown while the field
  /// is focused and EMPTY. Empty (the default) disables the dropdown.
  final List<String> recentSearches;

  /// Called when the shopkeeper taps a recent term — the field adopts the
  /// text and applies it immediately (no debounce: the value is settled).
  final ValueChanged<String>? onRecentSelected;

  /// Called when the shopkeeper dismisses one recent term.
  final ValueChanged<String>? onRecentRemoved;

  static const Duration _kDefaultDelay = Duration(milliseconds: 300);

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  /// The latest text the parent has NOT seen yet. Non-null only while the
  /// debounce timer is pending; [Timer] firing or [_flush] consume it.
  String? _lastValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    // Place the cursor at the end so a re-mounted field doesn't select all.
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    // Driven by the suffix icon's clear visibility; rebuilt in _onChanged /
    // _clear only (cheap — one bool, not the whole list page).
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
    // When the user taps a row / a button / anywhere outside, the field
    // loses focus: apply the still-pending text first, so the rows the
    // shopkeeper sees already match what they typed.
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  bool _hasText = false;

  void _onTextChanged() {
    final has = _controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      // The dropdown lives only while focused: refresh it on entry.
      setState(() {});
      return;
    }
    final hadPending = _lastValue != null;
    _flush();
    if (hadPending) widget.onFocusLost?.call(_controller.text);
    // Leaving the field dismisses the dropdown.
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // The typed text is visible through the field's own controller on every
    // keystroke; only the EXPENSIVE part — the parent's filter derivation
    // and provider rebuild — waits for the pause below.
    _lastValue = value;
    _debounce?.cancel();
    _debounce = Timer(widget.delay, () {
      _debounce = null;
      _lastValue = null;
      widget.onChanged(value);
    });
  }

  /// Applies [_lastValue] NOW when the timer has not fired for it yet.
  ///
  /// Called from the focus listener and from [_onSubmitted]: the value the
  /// timer has not fired for yet is applied synchronously, and the pending
  /// timer is dropped so the same value cannot arrive twice. A value the
  /// timer ALREADY delivered ([_lastValue] consumed) is a no-op — so a
  /// focus change / submit after the pause can never double-deliver.
  void _flush() {
    final pending = _debounce;
    _debounce = null;
    pending?.cancel();
    final value = _lastValue;
    if (value != null) {
      _lastValue = null;
      widget.onChanged(value);
    }
  }

  void _onSubmitted(String value) {
    // The pending debounce is flushed through _flush so the filter sees the
    // submitted text exactly once, then the action runs.
    final hadPending = _lastValue != null;
    _flush();
    if (hadPending) widget.onFocusLost?.call(value);
    widget.onSubmitted?.call(value);
  }

  void _clear() {
    _debounce?.cancel();
    _lastValue = null;
    _controller.clear();
    // The listener flips [_hasText] and rebuilds the suffix icon.
    widget.onCleared?.call();
    widget.onChanged('');
  }

  void _selectRecent(String term) {
    // A settled value: apply immediately (no debounce), move the cursor to
    // the end, and keep focus so the shopkeeper can refine it.
    _debounce?.cancel();
    _lastValue = null;
    _controller.text = term;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: term.length),
    );
    widget.onChanged(term);
    widget.onRecentSelected?.call(term);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Recent terms show only while focused AND the field is empty: once the
    // shopkeeper types, the rows themselves are the answer — not history.
    final showRecents = _focusNode.hasFocus &&
        _controller.text.isEmpty &&
        widget.recentSearches.isNotEmpty &&
        widget.onRecentSelected != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('search_field'),
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _hasText
                ? IconButton(
                    tooltip: appText(context).commonClearSearch,
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clear,
                  )
                : null,
          ),
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.onSubmitted != null
              ? TextInputAction.search
              : TextInputAction.done,
        ),
        if (showRecents) ...[
          const SizedBox(height: 4),
          _RecentSearchesDropdown(
            terms: widget.recentSearches,
            onSelect: _selectRecent,
            onRemove: widget.onRecentRemoved == null
                ? null
                : (term) {
                    widget.onRecentRemoved!(term);
                    // The removal updates the parent's list — rebuild so the
                    // dropdown shrinks immediately.
                    setState(() {});
                  },
          ),
        ],
      ],
    );
  }
}

/// The recent-searches dropdown: most-recent-first rows under the field.
///
/// Tapping a row re-runs that search; the trailing dismiss drops one term.
/// Kept private to the field so the "focused + empty + history" visibility
/// rule lives in exactly one place — callers only pass terms + callbacks.
class _RecentSearchesDropdown extends StatelessWidget {
  const _RecentSearchesDropdown({
    required this.terms,
    required this.onSelect,
    this.onRemove,
  });

  final List<String> terms;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Recent searches',
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerLow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                appText(context).commonRecentSearches,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            for (final term in terms)
              InkWell(
                key: Key('recent_search_$term'),
                onTap: () => onSelect(term),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.history, size: 16),
                      ),
                      Expanded(
                        child: Text(
                          term,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (onRemove != null)
                        IconButton(
                          key: Key('remove_recent_$term'),
                          tooltip: appText(context).debouncedSearchFieldRemoveTerm(term),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => onRemove!(term),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
