import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/support_ticket.dart';

/// The triage state of one support ticket.
///
/// The TEXT is whatever the backend sent as `status_label` — this widget only
/// picks the colour and icon for the status value it recognises. A status this
/// build does not know is rendered with a neutral treatment and the server's
/// own label, so an unknown state can never be dressed up as "Submitted".
class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = ticket.status;
    final accent = switch (status) {
      TicketStatus.open => AppColors.info,
      TicketStatus.inProgress => AppColors.warning,
      TicketStatus.resolved => AppColors.success,
      TicketStatus.closed => scheme.outline,
      TicketStatus.rejected => AppColors.error,
      null => scheme.outline,
    };
    final icon = switch (status) {
      TicketStatus.open => Icons.inbox_outlined,
      TicketStatus.inProgress => Icons.autorenew,
      TicketStatus.resolved => Icons.check_circle_outline,
      TicketStatus.closed => Icons.lock_outline,
      TicketStatus.rejected => Icons.block_outlined,
      null => Icons.help_outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            ticket.statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}
