import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_text.dart';
import '../../../../core/state/system_state.dart';
import '../../../../core/state/system_state_view.dart';
import '../../domain/device_session.dart';
import '../controllers/sessions_controller.dart';
import '../widgets/settings_widgets.dart';

/// Device / session information straight from the backend.
///
/// The shopkeeper backend records one row per sign-in in `auth_sessions`, so
/// this screen shows real server truth — device label, platform, app version,
/// IP and last activity — instead of a client-side guess. Each row can revoke
/// that device; the list is reloaded afterwards so a revoked device can never
/// linger on screen.
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(sessionsControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonSessionsDevices2)),
      body: SafeArea(
        child: switch (state.status) {
          SessionsStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          SessionsStatus.error => SystemStateView(
              spec: SystemStateSpec.resolve(
                text: appText(context),
                state: SystemState.genericRetry,
                title: state.message ?? 'Could not load your active devices.',
                message: appText(context).sessionsScreenCheckYourConnectionAndTry,
              ),
              onRetry: () =>
                  ref.read(sessionsControllerProvider.notifier).load(),
            ),
          SessionsStatus.ready => _readyBody(state),
        },
      ),
    );
  }

  Widget _readyBody(SessionsState state) {
    if (state.isEmpty) {
      // No server-side session rows. That is a legitimate outcome for a
      // Google/Firebase sign-in (Firebase owns that token, so there is nothing
      // for Passly to store or revoke) — the copy says so instead of implying
      // that the account is broken.
      return SystemStateView.empty(
        title: appText(context).sessionsScreenNoDeviceSessionsRecorded,
        message: appText(context).sessionsScreenThisAccountSignsInWith,
        icon: Icons.devices_other_outlined,
      );
    }

    final current = state.currentSession;
    final others = state.sessions
        .where((session) => !state.isCurrent(session))
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionsControllerProvider.notifier).load(),
      // Always scrollable: pull-to-refresh must fire even with a single
      // session (each device is one row).
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsIntro(
            icon: Icons.devices_outlined,
            title: appText(context).commonWhereYouAreSignedIn,
            subtitle: appText(context).sessionsScreenDevicesWithAnActivePassly,
          ),
          if (current != null)
            SettingsSection(
              title: appText(context).commonThisDevice,
              children: [
                _SessionRow(
                    session: current, isCurrent: true, isRevoking: false),
              ],
            ),
          SettingsSection(
            title: appText(context).commonOtherDevices,
            children: others.isEmpty
                ? [
                    SettingsTile(
                      icon: Icons.verified_user_outlined,
                      title: appText(context).commonNoOtherDevices,
                      subtitle: appText(context).sessionsScreenOnlyThisDeviceIsSigned,
                    ),
                  ]
                : [
                    for (final session in others)
                      _SessionRow(
                        session: session,
                        isCurrent: false,
                        isRevoking: state.isRevoking(session),
                        onRevoke: () => _confirmRevoke(session),
                      ),
                  ],
          ),
          const SizedBox(height: 8),
          SettingsNotice(
            icon: Icons.info_outline,
            title: appText(context).sessionsScreenSigningADeviceOutTakes,
            message: appText(context).sessionsScreenTheDeviceIsReturnedTo,
          ),
        ],
      ),
    );
  }

  /// Revoking is destructive for the device on the other end, so it is always
  /// confirmed first — the same courtesy the logout flow gives.
  Future<void> _confirmRevoke(DeviceSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context).commonSignOutThisDevice),
        content: Text(
          appText(context).sessionsScreenLabelWillNeedToSign(session.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(appText(context).commonCancel),
          ),
          FilledButton(
            key: const Key('confirm_revoke_session'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(appText(context).commonSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final failure = await ref
        .read(sessionsControllerProvider.notifier)
        .revoke(session.sessionId);
    if (!mounted || failure == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(failure), behavior: SnackBarBehavior.floating),
      );
  }
}

/// One device row.
///
/// The current device is marked and carries NO revoke button: ending this
/// session belongs to *Log out*, which also clears the local tokens. Offering
/// it here would sign the shopkeeper out with no warning.
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.isCurrent,
    required this.isRevoking,
    this.onRevoke,
  });

  final DeviceSession session;
  final bool isCurrent;
  final bool isRevoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ip = session.ipAddress;

    return ListTile(
      key: Key('device_session_${session.sessionId}'),
      isThreeLine: true,
      leading: Icon(
        isCurrent ? Icons.smartphone : Icons.devices_outlined,
        color: isCurrent ? scheme.primary : null,
      ),
      title: Text(session.label, style: const TextStyle(fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(session.detail, style: const TextStyle(fontSize: 12)),
          Text(
            activityLabel(session),
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          if (ip != null)
            Text(
              appText(context).sessionsScreenIPIp(ip),
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
        ],
      ),
      trailing: isCurrent
          ? Text(
              appText(context).commonThisDevice,
              key: const Key('session_this_device'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            )
          : isRevoking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  key: Key('revoke_session_${session.sessionId}'),
                  onPressed: onRevoke,
                  child: Text(appText(context).commonSignOut),
                ),
    );
  }
}

/// Absolute "last used" stamp — a security screen reads better with an exact
/// time than with "3h ago" — falling back to the sign-in time when the backend
/// never recorded activity.
///
/// Public so the sessions test can assert the copy without a widget tree.
String activityLabel(DeviceSession session) {
  final last = session.lastActivityAt;
  if (last != null) return 'Last used ${formatSessionStamp(last)}';
  final created = session.createdAt;
  if (created != null) return 'Signed in ${formatSessionStamp(created)}';
  return 'Activity time unknown';
}

/// Local-time timestamp used by the session rows.
String formatSessionStamp(DateTime value) =>
    DateFormat('d MMM yyyy, HH:mm').format(value.toLocal());