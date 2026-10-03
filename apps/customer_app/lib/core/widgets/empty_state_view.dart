import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable empty-state widget used across discovery sections.
/// Shows an icon, title, optional message, and one optional action button —
/// or a row of labelled secondary actions via [actions].
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;

  /// Icon for the optional action button. Defaults to a refresh glyph,
  /// which is the overwhelmingly common action (retry/reload).
  final IconData actionIcon;
  final VoidCallback? onActionTap;

  /// Extra labelled buttons rendered as a wrapping row beneath the primary
  /// action. Each runs only when its own callback is non-null, so a state like
  /// "no nearby shops" can offer *change location* AND *search by pin* without
  /// inventing a combined button — the customer picks the recovery that fits.
  final List<EmptyStateAction> actions;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon = Icons.refresh,
    this.onActionTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
            if (actionLabel != null && onActionTap != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onActionTap,
                icon: Icon(actionIcon),
                label: Text(actionLabel!),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final action in actions)
                    if (action.onTap != null)
                      OutlinedButton.icon(
                        key: action.key,
                        onPressed: action.onTap,
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.label),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One recovery button inside an [EmptyStateView]'s secondary [actions] row.
///
/// A deliberately separate type rather than three loose parameters: a recovery
/// offer is a (label, destination, availability) bundle, and a button whose
/// destination does not exist yet is exactly the dead control the
/// error-handling rules forbid — so the presence of [onTap] IS what renders
/// the button. Callers pass a slot only when the recovery behind it is real.
class EmptyStateAction {
  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const EmptyStateAction({
    this.key,
    required this.icon,
    required this.label,
    this.onTap,
  });
}
