import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small uppercase caption that introduces a group of rows inside a screen.
///
/// FIVE screens used to carry a private `_SectionLabel`: the type styling
/// (12 / w700 / 1.1 tracking / muted) was byte-identical in every copy and only
/// the surrounding padding differed. That is the worst shape of duplication —
/// one design change meant five edits, and a missed one silently drifted. There
/// is now ONE definition, and a screen that wants different spacing passes
/// [padding] instead of re-declaring the styling to move its label.
///
/// Distinct from [SectionHeader], which is the large 18pt title with an optional
/// trailing action used above a content list.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.padding, super.key});

  final String text;

  /// Spacing around the label. Defaults to the settings-screen rhythm.
  final EdgeInsetsGeometry? padding;

  static const EdgeInsets _defaultPadding = EdgeInsets.fromLTRB(
    AppSpacing.md,
    AppSpacing.lg,
    AppSpacing.md,
    AppSpacing.xs,
  );

  /// For a label that follows a list inside an already-padded screen, where the
  /// default's `lg` top gap would double the space above the first row.
  static const EdgeInsets tight = EdgeInsets.only(
    top: AppSpacing.md,
    bottom: AppSpacing.xs,
  );

  /// The densest variant, for stacks that already provide their own rhythm.
  static const EdgeInsets dense = EdgeInsets.only(
    top: AppSpacing.sm,
    bottom: AppSpacing.xs,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? _defaultPadding,
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (actionLabel != null && onActionTap != null)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
