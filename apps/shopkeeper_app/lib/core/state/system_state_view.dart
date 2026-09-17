import 'package:flutter/material.dart';

import 'system_state.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// The ONE reusable renderer for the nine system states.
///
/// This is deliberately a *component*, not a screen per state: features keep
/// their own `*Status` enums and swap only the body under their `Scaffold`, so
/// the same copy, icon and way-out appear everywhere and can never drift.
///
/// ```dart
/// // Full-screen error (the common case):
/// SystemStateView(
///   spec: SystemStateSpec.resolve(state: SystemState.permissionDenied),
///   onSwitchShop: () => context.push(Routes.shops),
/// )
///
/// // Inline / inside a scroll view or card:
/// SystemStateView(state: spec, compact: true, onRetry: reload)
///
/// // Empty state (title/message owned by the feature):
/// SystemStateView.empty(
///   title: 'No products yet',
///   message: 'Tap "Add" to create your first listing.',
/// )
/// ```
///
/// Every existing screen keeps its wording: pass [SystemStateSpec.resolve] with
/// the feature's own `title`/`message` and the strings come through untouched.
/// ─────────────────────────────────────────────────────────────────────────────
class SystemStateView extends StatelessWidget {
  const SystemStateView({
    super.key,
    required this.spec,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.retryKey,
    this.onSignIn,
    this.onSwitchShop,
    this.secondary,
    this.iconColor,
    this.compact = false,
  });

  /// Empty state — the calling feature owns the wording and the call to action.
  ///
  /// An empty result is NOT a failure: the copy says what is missing and the
  /// optional [action] is the one thing that fixes it (add the first product,
  /// clear a filter, go back).
  factory SystemStateView.empty({
    Key? key,
    required String title,
    String message = '',
    IconData icon = Icons.inbox_outlined,
    Color? iconColor,
    Widget? action,
    bool compact = false,
  }) {
    return SystemStateView(
      key: key,
      spec: SystemStateSpec(
        state: SystemState.empty,
        title: title,
        message: message,
        icon: icon,
        action: SystemAction.none,
      ),
      secondary: action,
      iconColor: iconColor,
      compact: compact,
    );
  }

  /// Copy + icon + default action (see [SystemStateSpec]).
  final SystemStateSpec spec;

  /// Re-issues the failed request — the way out for offline / network / server
  /// / maintenance / generic failures. Rendered only when a callback is
  /// supplied; a state that cannot be retried (`permissionDenied`,
  /// `sessionExpired`) never shows a lying Retry unless the caller decides its
  /// own context makes one useful.
  final VoidCallback? onRetry;

  final String retryLabel;

  /// Stable key for tests (e.g. `Key('pos-retry')`).
  final Key? retryKey;

  /// Sends the shopkeeper back through sign-in.
  final VoidCallback? onSignIn;

  /// Sends the shopkeeper to a shop they do have access to.
  final VoidCallback? onSwitchShop;

  /// Optional extra action widget (feature-specific way out).
  final Widget? secondary;

  /// Optional icon tint (a feature that encodes "waiting"/"warning" in colour,
  /// e.g. the POS flow). Defaults to the theme's outline/error per state.
  final Color? iconColor;

  /// Compact: no centring/scrolling, smaller icon — for use inside an existing
  /// scroll view, card, or list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = _buildContent(context, theme, scheme);
    if (compact) return content;
    return Center(child: SingleChildScrollView(child: content));
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final iconSize = compact ? 40.0 : 56.0;
    final padding = compact ? 16.0 : 32.0;
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            spec.icon,
            size: iconSize,
            color:
                iconColor ??
                (spec.state == SystemState.permissionDenied ||
                        spec.state == SystemState.sessionExpired ||
                        spec.state == SystemState.unauthorized
                    ? scheme.error
                    : scheme.outline),
          ),
          const SizedBox(height: 12),
          Text(
            spec.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          if (spec.message.trim().isNotEmpty)
            Text(
              spec.message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.outline),
            ),
          ..._buildActions(context, scheme),
        ],
      ),
    );
  }

  /// Buttons, in intent order.
  ///
  /// The state names the action that genuinely helps (`Retry` for a network
  /// blip, `Switch shop` for a 403, `Sign in` for an expired session). The
  /// caller supplies the callbacks — and a caller that passes a callback for a
  /// state whose "natural" action is different (e.g. reloading the shop
  /// selection on a 403) still gets its button: this layer adds a way out, it
  /// never removes one.
  List<Widget> _buildActions(BuildContext context, ColorScheme scheme) {
    final primary = switch (spec.action) {
      SystemAction.retry => onRetry == null ? null : _retryButton(),
      SystemAction.signIn => onSignIn == null ? null : _signInButton(),
      SystemAction.switchShop =>
        onSwitchShop == null ? null : _switchShopButton(),
      SystemAction.none => null,
    };

    final buttons = <Widget>[
      if (primary != null)
        primary
      else if (onRetry != null)
        _retryButton()
      else if (onSignIn != null)
        _signInButton()
      else if (onSwitchShop != null)
        _switchShopButton(),
      ?secondary,
    ];

    if (buttons.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        buttons[i],
      ],
    ];
  }

  Widget _retryButton() => OutlinedButton.icon(
    key: retryKey,
    onPressed: onRetry,
    icon: const Icon(Icons.refresh),
    label: Text(retryLabel),
  );

  Widget _signInButton() => FilledButton.icon(
    key: retryKey,
    onPressed: onSignIn,
    icon: const Icon(Icons.login),
    label: const Text('Sign in'),
  );

  Widget _switchShopButton() => FilledButton.tonalIcon(
    key: retryKey,
    onPressed: onSwitchShop,
    icon: const Icon(Icons.swap_horiz),
    label: const Text('Switch shop'),
  );
}

/// The standard async body for a screen fed by ONE controller:
/// **loading → failure → empty → content**.
///
/// Screens keep their own `*Status` enum (single source of truth per feature)
/// and translate it here, so the four-way contract and its widgets exist once.
/// A feature only writes the two lines that are genuinely its own: which state
/// the failure is, and what "empty" means for it.
///
/// ```dart
/// SystemStateBody(
///   isLoading: state.status == ProductsStatus.loading,
///   failure: state.status == ProductsStatus.error
///       ? SystemStateSpec.resolve(message: state.message)
///       : state.status == ProductsStatus.accessDenied
///           ? SystemStateSpec.of(SystemState.permissionDenied)
///           : null,
///   isEmpty: state.items.isEmpty,
///   emptyTitle: 'No products yet',
///   onRetry: () => ref.read(productsControllerProvider.notifier).load(),
///   builder: (context) => _ReadyBody(...),
/// )
/// ```
class SystemStateBody extends StatelessWidget {
  const SystemStateBody({
    super.key,
    required this.isLoading,
    required this.failure,
    this.isEmpty = false,
    required this.onRetry,
    required this.builder,
    this.retryLabel = 'Retry',
    this.retryKey,
    this.onSignIn,
    this.onSwitchShop,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = '',
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
  });

  final bool isLoading;

  /// The failure to render, or `null` when the request succeeded.
  final SystemStateSpec? failure;

  final bool isEmpty;

  final VoidCallback? onRetry;

  final String retryLabel;

  final Key? retryKey;

  final VoidCallback? onSignIn;

  final VoidCallback? onSwitchShop;

  final String emptyTitle;

  final String emptyMessage;

  final IconData emptyIcon;

  /// The one thing that fixes emptiness (add, clear a filter, go back).
  final Widget? emptyAction;

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (failure != null) {
      return SystemStateView(
        spec: failure!,
        onRetry: onRetry,
        retryLabel: retryLabel,
        retryKey: retryKey,
        onSignIn: onSignIn,
        onSwitchShop: onSwitchShop,
      );
    }
    if (isEmpty) {
      return SystemStateView.empty(
        title: emptyTitle,
        message: emptyMessage,
        icon: emptyIcon,
        action: emptyAction,
      );
    }
    return builder(context);
  }
}