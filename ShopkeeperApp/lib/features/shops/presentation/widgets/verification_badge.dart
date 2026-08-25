import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Compact colored badge reflecting a shop's verification lifecycle.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.status, this.compact = false});

  final String status;

  /// When true renders a dot+icon only (for dense rows).
  final bool compact;

  (Color, String) get _style {
    switch (status) {
      case 'VERIFIED':
        return (AppTheme.verifiedGreen, 'Verified');
      case 'REJECTED':
        return (AppTheme.rejectedRed, 'Rejected');
      case 'SUBMITTED':
        return (AppTheme.pendingAmber, 'Submitted');
      case 'UNDER_REVIEW':
        return (AppTheme.pendingAmber, 'Under review');
      case 'EXPIRED':
        return (AppTheme.suspendedGrey, 'Expired');
      default:
        return (AppTheme.pendingAmber, 'Verification pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (color, label) = _style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined, size: 14, color: color),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
