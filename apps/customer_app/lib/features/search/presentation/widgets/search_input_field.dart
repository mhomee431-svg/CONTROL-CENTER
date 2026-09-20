import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/search_event_tracker.dart';
import '../controllers/search_controller.dart';

/// Smart search input field.
///
/// Responsibilities (kept in the widget layer, business logic stays in
/// the controller):
/// - Debounced text changes
/// - Clear / cancel behavior
/// - Keyboard handling (escape = clear/cancel, enter = submit)
/// - Optional barcode action (hidden when [onBarcodeTap] is null)
///
/// Note: the [FocusNode] is attached to the [TextField] ONLY. Attaching the
/// same node to a wrapping `Focus` widget as well makes Flutter throw
/// "Tried to make a child into a parent of itself" during reparenting and
/// breaks keyboard focus. Escape handling therefore uses [CallbackShortcuts],
/// which rides on whatever node already has focus.
class SearchInputField extends ConsumerStatefulWidget {
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onBarcodeTap;

  const SearchInputField({
    super.key,
    this.focusNode,
    this.controller,
    this.onSubmitted,
    this.onBarcodeTap,
  });

  @override
  ConsumerState<SearchInputField> createState() => _SearchInputFieldState();
}

class _SearchInputFieldState extends ConsumerState<SearchInputField> {
  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;

  TextEditingController get _controller => widget.controller ?? _internalController;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController();
    _internalFocusNode = FocusNode();
    // Restore query text from the shared query state if available.
    final current = ref.read(searchQueryProvider).query;
    if (current.isNotEmpty) {
      _controller.text = current;
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _internalController.dispose();
    if (widget.focusNode == null) _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    // Immediate echo for UI feedback (clear button, view switch), without
    // touching the debounced value that drives suggestion fetches.
    ref.read(searchQueryProvider.notifier).onTextChanged(value);
    ref.read(debouncerProvider).run(() {
      ref.read(searchQueryProvider.notifier).debouncedTextChanged(value);
    });
  }

  void _handleClear() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).clear();
    ref.read(searchEventTrackerProvider).track(const SearchClearedEvent());
  }

  void _handleCancel() {
    _handleClear();
    _focusNode.unfocus();
  }

  void _handleEscape() {
    _handleCancel();
    if (context.canPop()) context.pop();
  }

  void _handleSubmitted(String value) {
    if (value.trim().isEmpty) return;
    ref.read(searchQueryProvider.notifier).debouncedTextChanged(value.trim());
    ref.read(searchEventTrackerProvider).track(SearchSubmittedEvent(
          query: value.trim(),
          source: 'keyboard',
        ));
    widget.onSubmitted?.call(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final queryState = ref.watch(searchQueryProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        autofocus: true,
        keyboardType: TextInputType.text,
        style: const TextStyle(fontSize: 16),
        onChanged: _handleChanged,
        onSubmitted: _handleSubmitted,
        inputFormatters: [
          // Allow letters/digits/spaces; reject control characters.
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\-_.]')),
        ],
        decoration: InputDecoration(
          hintText: 'Search products, brands...',
          border: InputBorder.none,
          suffixIcon: queryState.query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: _handleClear,
                )
              : (widget.onBarcodeTap == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan barcode',
                      onPressed: widget.onBarcodeTap,
                    )),
        ),
      ),
    );
  }
}
