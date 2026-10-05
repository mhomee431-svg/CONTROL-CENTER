import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/search_event_tracker.dart';
import '../../domain/search_text_sanitizer.dart';
import '../controllers/search_controller.dart';
import '../search_input_capabilities.dart';
import '../../../../core/theme/app_theme.dart';

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

  TextEditingController get _controller =>
      widget.controller ?? _internalController;
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
    ref
        .read(searchEventTrackerProvider)
        .track(SearchSubmittedEvent(query: value.trim(), source: 'keyboard'));
    widget.onSubmitted?.call(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final queryState = ref.watch(searchQueryProvider);
    // Loading is read from the suggestions provider rather than inferred from
    // the query text: during the 500ms debounce there is genuinely nothing in
    // flight, and showing a spinner for that window would make the bar look
    // busy while the customer is still typing the word.
    final isLoading = ref.watch(
      suggestionsProvider.select((async) => async.isLoading),
    );

    final capabilities = ref.watch(searchInputCapabilitiesProvider);
    final extension = ref.watch(searchInputExtensionProvider);
    // Both conditions must hold: the build must be flagged for it AND an
    // implementation must be installed. The flag alone would render a button
    // with nothing behind it.
    final voiceAction = capabilities.has(SearchInputCapability.voice)
        ? extension.buildAction(_handleExtensionResult)
        : null;

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
        inputFormatters: [SearchTextSanitizer.formatter],
        decoration: InputDecoration(
          hintText: 'Search products, brands...',
          border: InputBorder.none,
          // A row rather than a single icon. Clear, scan and voice are
          // independent actions, and making them mutually exclusive means
          // typing one character hides the scanner -- so a customer who
          // starts typing and then decides to scan has to delete their query
          // first. All of them stay reachable at once.
          suffixIcon: _SuffixActions(
            isLoading: isLoading,
            hasText: queryState.query.isNotEmpty,
            onClear: _handleClear,
            onBarcode: widget.onBarcodeTap,
            extensionAction: voiceAction,
          ),
        ),
      ),
    );
  }

  /// Routes a recognised phrase through the exact same path as typed input.
  ///
  /// Funnelling it here rather than into the controller directly is what means
  /// a voice search cannot skip history, debouncing or analytics: there is only
  /// one way text enters the search flow, whoever produced it.
  void _handleExtensionResult(String transcript) {
    final value = transcript.trim();
    if (value.isEmpty) return;
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    _handleChanged(value);
  }
}

/// The trailing affordances: progress, clear, scan, and the optional
/// extension's action.
class _SuffixActions extends StatelessWidget {
  final bool isLoading;
  final bool hasText;
  final VoidCallback onClear;
  final VoidCallback? onBarcode;
  final Widget? extensionAction;

  const _SuffixActions({
    required this.isLoading,
    required this.hasText,
    required this.onClear,
    this.onBarcode,
    this.extensionAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.xs),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ?extensionAction,
        if (onBarcode != null)
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: onBarcode,
          ),
        if (hasText)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: onClear,
          ),
      ],
    );
  }
}
