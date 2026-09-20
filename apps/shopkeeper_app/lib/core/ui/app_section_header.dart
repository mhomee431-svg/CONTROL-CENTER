/// One section title for every screen.
///
/// This is the app's single "clear section title" implementation: same type
/// scale, same ink, same hierarchy everywhere. Screens that need different
/// *spacing* pass [padding]; screens that need a trailing control pass
/// [action]. They must not restyle the text.
library;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.padding,
  });

  final String title;

  /// Optional trailing control (e.g. a "See all" text button).
  final Widget? action;

  /// Defaults to a standard [AppSpacing.sm] gap below the title. Pass
  /// `EdgeInsets.zero` when the caller already provides the surrounding gap.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.headingSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
              ),
            ),
          ),
          // ignore: use_null_aware_elements
          if (action case final widget?) widget,
        ],
      ),
    );
  }
}