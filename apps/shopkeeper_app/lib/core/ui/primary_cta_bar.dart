import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// ── THE BOTTOM LAYER OF THE PAGE HIERARCHY ────────────────────────────────
///
/// The app's page contract is a fixed three-layer shape:
///
///     TOP     Back / Title / contextual action      → `AppBar` (AppTheme)
///     BODY    sections · cards · forms              → `SafeArea` + scroll
///     BOTTOM  Primary CTA, where necessary          → **this widget**
///
/// **Competing CTAs are structurally impossible here.** The API takes exactly
/// ONE primary (a label + callback) and at most one secondary — there is no
/// list of buttons and no second primary slot, so a screen cannot stack two
/// equally-weighted actions and call it a hierarchy. The secondary is always
/// rendered as an [OutlinedButton], one visual step below the primary, so the
/// eye lands on one action first.
///
/// Use it as `Scaffold.bottomNavigationBar`, which is what keeps the primary
/// action in the SAME place on every screen (thumb-reachable, clear of the
/// scrolling body) instead of drifting with the content length.
///
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('Review import')),
///   body: …,
///   bottomNavigationBar: PrimaryCtaBar(
///     primaryLabel: 'Apply import',
///     onPrimary: _apply,
///     secondaryLabel: 'Discard',
///     onSecondary: _discard,
///   ),
/// )
/// ```
///
/// Screens with NO primary action (a plain settings list, a read-only report)
/// pass no bar at all — "where necessary" is part of the contract.
class PrimaryCtaBar extends StatelessWidget {
  const PrimaryCtaBar({
    super.key,
    required this.primaryLabel,
    this.onPrimary,
    this.primaryIcon,
    this.primaryKey,
    this.loading = false,
    this.loadingLabel,
    this.destructive = false,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryKey,
  }) : assert(
         (secondaryLabel == null) == (onSecondary == null),
         'A secondary action needs BOTH a label and a callback: '
         'one without the other renders a dead button.',
       );

  /// The ONE primary action. Null disables it — never render a second one.
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;

  /// Test/preview handle for the primary button.
  final Key? primaryKey;

  /// True while [onPrimary] is in flight: the primary shows a spinner and BOTH
  /// buttons are disabled, so one tap can never start two operations.
  final bool loading;
  final String? loadingLabel;

  /// Paints the primary with the error palette (sign out, delete, discard a
  /// destructive edit). Still exactly one primary.
  final bool destructive;

  /// The OPTIONAL secondary — always demoted to an [OutlinedButton].
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Key? secondaryKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondaryLabel = this.secondaryLabel;
    final enabled = onPrimary != null && !loading;

    return Material(
      color: scheme.surface,
      // Flat by contract: the bar separates itself with a hairline, not a
      // shadow, so it never reads as a floating card over the body.
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        // `top: false`: the AppBar/body already cleared the status bar, and the
        // bar must own the home-indicator inset itself.
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  key: primaryKey,
                  onPressed: enabled ? onPrimary : null,
                  style: destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        )
                      : null,
                  child: loading
                      ? _BusyLabel(label: loadingLabel ?? primaryLabel)
                      : _CtaLabel(label: primaryLabel, icon: primaryIcon),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    key: secondaryKey,
                    onPressed: loading ? null : onSecondary,
                    child: Text(secondaryLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary label with an optional leading icon, both vertically centred.
class _CtaLabel extends StatelessWidget {
  const _CtaLabel({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// In-flight primary label: spinner + honest progress copy.
class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            // The spinner sits ON the filled primary, so it must read against
            // that fill rather than the scaffold.
            color: AppColors.onPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
