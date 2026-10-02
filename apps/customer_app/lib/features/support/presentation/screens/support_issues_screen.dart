import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state_view.dart';
import '../../../auth/presentation/widgets/auth_gate_sheet.dart';
import '../controllers/support_issues_controller.dart';

/// The reports the customer has filed with support, and their real status.
///
/// WHY THIS SCREEN EXISTS
/// ----------------------
/// The app could file a report but never read one back. The intake route
/// (`POST /support/issues`) was wired and the history route
/// (`GET /support/issues`) — serving the same resource on the same backend
/// router — was called by nothing. So "we have your report" was the last thing
/// the app ever said: a customer who wanted to know whether anything had
/// happened could only file the report again, which is exactly the behaviour a
/// support queue does not need.
///
/// This is the read half. Every state it renders comes from the backend
/// (`status_label`, `category_label`, `resolution_notes`), so the screen never
/// invents a progression of its own — a ticket an admin resolved directly shows
/// as resolved, not as "in progress".
class SupportIssuesScreen extends ConsumerStatefulWidget {
  const SupportIssuesScreen({super.key});

  @override
  ConsumerState<SupportIssuesScreen> createState() =>
      _SupportIssuesScreenState();
}

class _SupportIssuesScreenState extends ConsumerState<SupportIssuesScreen> {
  /// Whether the auth gate has finished. Until it has, the screen shows a
  /// spinner rather than an empty state, because "you have no reports" would be
  /// an assertion the app has not yet earned the right to make.
  bool _gateChecked = false;

  /// Whether the customer may read this list. Reports are account data, so the
  /// gate is the same one every other account-scoped read uses.
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    // After the first frame, not in initState: a provider read there happens
    // during build, and a signed-out customer's answer is a sign-in sheet
    // rather than a list.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkGate());
  }

  Future<void> _checkGate() async {
    if (!mounted) return;
    final allowed = await requireAuthentication(
      context,
      ref,
      actionLabel: 'see your reports',
    );
    if (!mounted) return;
    setState(() {
      _gateChecked = true;
      _allowed = allowed;
    });
    if (!allowed) return;
    // Read AFTER the gate opens. Anything cached from before sign-in would be
    // another customer's absence of reports — or this customer's, stale.
    ref.invalidate(supportIssuesProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(supportIssuesProvider);
    try {
      await ref.read(supportIssuesProvider.future);
    } catch (_) {
      // A failed refresh must not throw out of the RefreshIndicator: the error
      // is already rendered by the `error` branch below, and an exception here
      // would only add an unrelated crash on top of it.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My reports'),
        actions: [
          if (_allowed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(supportIssuesProvider),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_gateChecked) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (!_allowed) {
      return EmptyStateView(
        icon: Icons.lock_outline,
        title: 'Sign in to see your reports',
        message:
            'Reports are attached to your account so you can follow their '
            'progress. Sign in and they will be right here.',
        actionLabel: 'Sign in',
        actionIcon: Icons.login,
        onActionTap: () => context.push('/login'),
      );
    }

    final issues = ref.watch(supportIssuesProvider);
    return issues.when(
      // The cold-load spinner. `RefreshIndicator` is deliberately NOT wrapped
      // around this: there is nothing yet to pull.
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      // A failed read is a RETRY, never an empty state — telling a customer
      // "you have no reports" when the request failed would be a lie they act
      // on by filing the same report twice.
      error: (_, _) => EmptyStateView(
        icon: Icons.cloud_off,
        title: 'Couldn\u2019t load your reports',
        message:
            'We could not reach our servers. Nothing you reported has been '
            'lost \u2014 please try again.',
        actionLabel: 'Retry',
        onActionTap: () => ref.invalidate(supportIssuesProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyStateView(
            icon: Icons.report_outlined,
            title: 'No reports yet',
            message:
                'If something looks wrong in the app, tell us and you will be '
                'able to follow it here.',
            actionLabel: 'Report an issue',
            actionIcon: Icons.edit_outlined,
            onActionTap: () => context.push('/help'),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _IssueCard(issue: items[index]),
          ),
        );
      },
    );
  }
}

/// One reported issue: reference, backend status, what was reported, and
/// support's answer once there is one.
class _IssueCard extends StatelessWidget {
  final SupportIssue issue;

  const _IssueCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    return Card(
      // Keyed by the reference the customer can quote to support, so a test (or
      // a future "open ticket" deep link) can address a row by the same value
      // the customer sees.
      key: Key('supportIssue_${issue.reference}'),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    issue.reference,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(
                  label: issue.displayStatus,
                  color: _statusColor(issue.status),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              issue.displayCategory,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            if (issue.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                issue.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ],
            if (issue.createdAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Reported ${_formatDate(issue.createdAt!)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (issue.hasResolution) ...[
              const SizedBox(height: 10),
              if (issue.resolvedAt != null)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Resolved ${_formatDate(issue.resolvedAt!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              // Only shown when support actually wrote something. A labelled
              // empty box would imply an answer that does not exist.
              if (issue.resolutionNotes?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    issue.resolutionNotes!.trim(),
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The state label. Coloured by the RAW backend status, because the display
/// wording is presentation and may be reworded or translated while the meaning
/// stays with the code.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// A colour for each state the backend can report. An unrecognised (or absent)
/// status falls back to the neutral colour rather than to a verdict.
Color _statusColor(String status) {
  switch (status.trim().toUpperCase()) {
    case 'RESOLVED':
      return AppColors.secondary;
    case 'IN_PROGRESS':
      return AppColors.primary;
    case 'REJECTED':
      return AppColors.error;
    case 'CLOSED':
      return AppColors.textMuted;
    default:
      return AppColors.primary;
  }
}

/// `12 Mar 2026` — deliberately hand-rolled rather than pulling in a date
/// formatter for one label, and deliberately not the ambiguous `12/03/2026`
/// form, which is two different dates in India and the US.
String _formatDate(DateTime value) {
  const months = [
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
  final month = months[(value.month - 1).clamp(0, 11)];
  return '${value.day} $month ${value.year}';
}
