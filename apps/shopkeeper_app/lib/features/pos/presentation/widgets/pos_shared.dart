import 'package:flutter/material.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/pos_models.dart';
import '../controllers/pos_controller.dart';

/// Shared presentation helpers for the POS module (integration hub, connection
/// setup, sync, progress, result, history, error).
///
/// The server owns every vocabulary value (connector status, sync-job status,
/// sync type, trigger). They are mapped to labels / icons / colors here, in ONE
/// place, so the hub, the sync flow and the history list can never drift — and
/// an unfamiliar server value still renders humanised instead of throwing.

String _humanize(String value) => value
    .trim()
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => '${p[0]}${p.substring(1).toLowerCase()}')
    .join(' ');

// ── Connector status ─────────────────────────────────────────────────────────

/// ACTIVE / PENDING / ERROR / DISCONNECTED → shopkeeper wording.
String posStatusLabel(String status) => switch (status.trim().toUpperCase()) {
  'ACTIVE' => 'Connected',
  'PENDING' => 'Connecting',
  'ERROR' => 'Connection error',
  'INACTIVE' || 'DISCONNECTED' => 'Disconnected',
  '' => 'Unknown',
  final other => _humanize(other),
};

Color posStatusColor(String status, ColorScheme scheme) =>
    switch (status.trim().toUpperCase()) {
      'ACTIVE' => AppTheme.verifiedGreen,
      'PENDING' => AppTheme.pendingAmber,
      'ERROR' => scheme.error,
      _ => scheme.outline,
    };

IconData posStatusIcon(String status) => switch (status.trim().toUpperCase()) {
  'ACTIVE' => Icons.check_circle,
  'PENDING' => Icons.hourglass_top,
  'ERROR' => Icons.error_outline,
  _ => Icons.cloud_off,
};

// ── Sync job status ──────────────────────────────────────────────────────────

/// QUEUED / RUNNING / COMPLETED / COMPLETED_WITH_ERRORS / FAILED → wording.
String posJobStatusLabel(String status) =>
    switch (status.trim().toUpperCase()) {
      'QUEUED' => 'Queued',
      'RUNNING' => 'Running',
      'COMPLETED' => 'Completed',
      'COMPLETED_WITH_ERRORS' => 'Completed with errors',
      'FAILED' => 'Failed',
      'CANCELLED' => 'Cancelled',
      '' => 'Unknown',
      final other => _humanize(other),
    };

Color posJobStatusColor(String status, ColorScheme scheme) =>
    switch (status.trim().toUpperCase()) {
      'COMPLETED' => AppTheme.verifiedGreen,
      'COMPLETED_WITH_ERRORS' => AppTheme.pendingAmber,
      'FAILED' || 'CANCELLED' => scheme.error,
      _ => AppTheme.pendingAmber,
    };

IconData posJobStatusIcon(String status) =>
    switch (status.trim().toUpperCase()) {
      'COMPLETED' => Icons.check_circle,
      'COMPLETED_WITH_ERRORS' => Icons.warning_amber_outlined,
      'FAILED' => Icons.error_outline,
      'CANCELLED' => Icons.block_outlined,
      'RUNNING' => Icons.sync,
      _ => Icons.schedule,
    };

/// `FULL` / `INCREMENTAL` → shopkeeper wording.
String posSyncTypeLabel(String syncType) =>
    syncType.trim().toUpperCase() == 'INCREMENTAL'
    ? 'Incremental'
    : 'Full sync';

/// One-line outcome of a job. Never invents a count the server did not send.
String posJobSummary(PosSyncJob job) {
  if (job.isFailed) return job.errorSummary ?? 'Sync failed';
  if (job.isQueued || job.isRunning) return 'Sync ${job.status.toLowerCase()}…';
  final failed = job.itemsFailed > 0 ? ', ${job.itemsFailed} failed' : '';
  return '${job.itemsSucceeded} products synced$failed';
}

// ── Dates & durations ───────────────────────────────────────────────────────

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Compact `12 Jan 2026, 08:30` (no intl dependency).
String posDateTime(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]} ${dt.year}, '
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';

/// Short `08:30` clock (used inside a single day's job list).
String posClock(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}';

/// Human duration, e.g. `45s` / `2m 5s`. Never invents a time.
String posDurationLabel(Duration? duration) {
  if (duration == null || duration.isNegative) return '—';
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = duration.inMinutes;
  final rest = seconds % 60;
  return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
}

/// How long a job took (started → completed), or null while it is unfinished.
Duration? posJobDuration(PosSyncJob job) {
  final started = job.startedAt;
  final completed = job.completedAt;
  if (started == null || completed == null) return null;
  return completed.difference(started);
}


// ── Shared widgets ──────────────────────────────────────────────────────────

/// Small status pill: icon + label in the status color.
class PosStatusChip extends StatelessWidget {
  const PosStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Centred icon + copy for every non-ready POS state (no shop, error,
/// disconnected, empty list).
///
/// Rendering is the shared [SystemStateView]; this class exists so the POS
/// screens keep one vocabulary (title/body/action) and one retry key. When the
/// caller's copy IS one of the app's canonical state strings (a transport
/// failure now arrives pre-classified from `ApiException`), the shared state's
/// own icon and copy are shown instead — so an offline shopkeeper sees
/// "No internet connection", not a generic cloud.
class PosMessageView extends StatelessWidget {
  const PosMessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.color,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? color;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Optional secondary action (e.g. *Go to connection setup*).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final carried = onRetry == null ? null : SystemStateSpec.fromMessage(title);
    if (carried != null) {
      return SystemStateView(
        spec: SystemStateSpec.of(carried, appText(context)),
        onRetry: onRetry,
        retryLabel: retryLabel,
        retryKey: const Key('pos-retry'),
        secondary: action,
      );
    }
    return SystemStateView(
      spec: SystemStateSpec(
        state: onRetry == null ? SystemState.empty : SystemState.genericRetry,
        title: title,
        message: body,
        icon: icon,
        action: onRetry == null ? SystemAction.none : SystemAction.retry,
      ),
      onRetry: onRetry,
      retryLabel: retryLabel,
      retryKey: const Key('pos-retry'),
      secondary: action,
      iconColor: color,
    );
  }
}

/// Standard async body for POS screens fed by [posControllerProvider]:
/// loading spinner · no-shop copy · error copy with Retry · ready content.
class PosAsyncBody extends StatelessWidget {
  const PosAsyncBody({
    super.key,
    required this.status,
    this.message,
    required this.onRetry,
    required this.builder,
    this.noShopBody = 'Choose a shop to manage its POS integration.',
  });

  final PosStatus status;
  final String? message;
  final VoidCallback onRetry;
  final WidgetBuilder builder;
  final String noShopBody;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      PosStatus.loading => const Center(child: CircularProgressIndicator()),
      PosStatus.noShop => PosMessageView(
        icon: Icons.storefront_outlined,
        title: 'No shop selected',
        body: noShopBody,
      ),
      PosStatus.error => PosMessageView(
        icon: Icons.cloud_off_outlined,
        title: message ?? 'Could not load POS.',
        body: 'Check your connection and try again.',
        onRetry: onRetry,
      ),
      PosStatus.ready => builder(context),
    };
  }
}

/// One navigable row of the POS integration hub.
class PosHubTile {
  const PosHubTile(
    this.tileKey,
    this.icon,
    this.title,
    this.subtitle,
    this.route, {
    this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  /// When set, the tile opens a sheet/flow instead of navigating to [route]
  /// (used by the Terminals and Sync-settings tiles, which are dialogs on the
  /// hub rather than destinations).
  final VoidCallback? onTap;
}