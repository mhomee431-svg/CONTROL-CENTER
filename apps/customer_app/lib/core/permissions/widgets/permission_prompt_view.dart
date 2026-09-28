import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// One tappable action inside a [PermissionPromptView].
class PermissionPromptAction {
  const PermissionPromptAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.key,
  });

  final String label;

  /// `null` disables the action (e.g. while a request is in flight).
  final VoidCallback? onPressed;
  final IconData? icon;
  final Key? key;
}

/// The single, shared layout for "we need a permission" states.
///
/// WHY SHARED: every permission prompt in the app must explain the same things
/// in the same order — what is needed, why, and EVERY way forward that does NOT
/// need the permission. Rendering them from one widget means an explanation, an
/// "Open settings" escape hatch or a fallback button can never exist on one
/// screen and be missing on another.
class PermissionPromptView extends StatelessWidget {
  const PermissionPromptView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.bullets = const [],
    this.primary,
    this.fallbacks = const [],
    this.busy = false,
  });

  final IconData icon;
  final String title;

  /// Why the permission is needed — one or two sentences, always honest about
  /// what still works without it.
  final String message;

  /// Optional steps (e.g. the exact system-settings path).
  final List<String> bullets;

  /// The main action: allow, enable, or open the system settings.
  final PermissionPromptAction? primary;

  /// The ways forward that do NOT need the permission. Always rendered below
  /// the primary action so the screen can never dead-end.
  final List<PermissionPromptAction> fallbacks;

  /// True while a request is in flight (the OS dialog is up).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            if (bullets.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final bullet in bullets)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6, right: 8),
                              child: Icon(
                                Icons.circle,
                                size: 6,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                bullet,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (primary != null)
              FilledButton.icon(
                key: primary!.key,
                onPressed: busy ? null : primary!.onPressed,
                icon: Icon(primary!.icon ?? Icons.check),
                label: Text(primary!.label),
              ),
            for (final action in fallbacks) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: action.key,
                onPressed: action.onPressed,
                icon: Icon(action.icon ?? Icons.arrow_forward),
                label: Text(action.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
