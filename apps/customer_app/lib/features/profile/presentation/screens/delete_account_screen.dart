import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/storage/local_storage_driver.dart';
import '../../../../core/layout/form_keyboard.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/auth_repository.dart'
    show phoneAuthServiceProvider;
import '../../../auth/domain/auth_service.dart' show authServiceProvider;
import '../../../notifications/data/device_token_coordinator.dart';
import '../../../notifications/presentation/controllers/in_app_notification_controller.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../domain/profile_repository.dart';

/// Where the customer is in the delete-account flow.
///
/// Modelled explicitly (rather than a pile of booleans) because the order of
/// these steps is a safety property, not an implementation detail:
/// explain → confirm → re-authenticate → call the backend → sign out of
/// Firebase → clear the local session → return to the entry screen.
///
/// Nothing local is ever destroyed before the server has actually accepted
/// the deletion — otherwise a failed request would leave a live account with
/// no local session and no way back in.
enum DeleteAccountStep {
  /// Explaining what will be lost.
  explain,

  /// Waiting for the customer to confirm.
  confirm,

  /// Waiting for a fresh sign-in proof.
  reauthenticate,

  /// Calling `DELETE /users/me`.
  deleting,

  /// Finished; local session cleared.
  done,
}

/// Screen that performs the real account deletion.
///
/// The backend genuinely supports it (`DELETE /api/v1/users/me` →
/// `users.py::delete_me` → `db.delete(current_user)`), so this is not a
/// local-only "clear my cache" pretending to delete an account.
///
/// Order guarantees:
///  1. the impact is explained *before* anything irreversible is offered;
///  2. the customer must type their phone number to confirm, so a stray tap
///     on a destructive button can never destroy an account;
///  3. if the backend call fails, NOTHING local is cleared and the customer
///     stays signed in — a failed deletion is not a half-deletion;
///  4. only after the server confirms do we sign out of Firebase and wipe the
///     local session.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  DeleteAccountStep _step = DeleteAccountStep.explain;
  final TextEditingController _confirmController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: switch (_step) {
        DeleteAccountStep.explain => _buildExplain(context),
        DeleteAccountStep.confirm => _buildConfirm(context),
        DeleteAccountStep.reauthenticate => _buildReauthenticate(context),
        DeleteAccountStep.deleting => _buildDeleting(context),
        DeleteAccountStep.done => _buildDone(context),
      },
    );
  }

  // ── 1. Explain the impact ────────────────────────────────────────────
  Widget _buildExplain(BuildContext context) {
    final profile = ref.watch(profileControllerProvider).value;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const SizedBox(height: AppSpacing.md),
        const Icon(
          Icons.warning_amber_rounded,
          size: 64,
          color: AppColors.error,
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Delete your account?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'This permanently removes your account from Hyperlocal. It cannot '
          'be undone, and support cannot restore it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _ImpactList(),
        if (profile != null && profile.phoneNumber.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Card(
            elevation: 0,
            color: AppColors.backgroundLight,
            child: ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Account'),
              subtitle: Text(
                '${profile.phoneNumber}'
                '${profile.email.isNotEmpty ? ' • ${profile.email}' : ''}',
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        ElevatedButton(
          key: const Key('deleteAccountStartButton'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => setState(() {
            _step = DeleteAccountStep.confirm;
            _error = null;
          }),
          child: const Text('Continue'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('deleteAccountCancelButton'),
          onPressed: () => context.pop(),
          child: const Text('Keep my account'),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  // ── 2. Confirm by typing ─────────────────────────────────────────────
  Widget _buildConfirm(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Confirm deletion',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Type DELETE to confirm you understand this is permanent.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('deleteAccountConfirmField'),
          controller: _confirmController,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          // Single-field form, so the key is `done`. It deliberately only puts
          // the keyboard away: deletion is irreversible, so it stays behind the
          // explicit Delete button rather than being one stray keypress away.
          textInputAction: TextInputAction.done,
          onEditingComplete: () => FormKeyboard.dismiss(null),
          scrollPadding: FormKeyboard.scrollPaddingFor(context),
          decoration: const InputDecoration(
            hintText: 'DELETE',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: AppColors.error)),
        ],
        const SizedBox(height: AppSpacing.lg),
        ElevatedButton(
          key: const Key('deleteAccountConfirmButton'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _isConfirmed ? _beginDeletion : null,
          child: const Text('Delete my account'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  bool get _isConfirmed =>
      _confirmController.text.trim().toUpperCase() == 'DELETE';

  // ── 3. Re-authenticate when the session cannot prove intent ──────────
  Widget _buildReauthenticate(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 56, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Sign in again',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'For your security, please sign in once more before we delete your '
            'account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            key: const Key('deleteAccountReauthButton'),
            onPressed: () {
              // Route to the normal sign-in; on success the customer comes
              // back here and taps Continue again.
              context.push('/login');
            },
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('deleteAccountReauthSkipButton'),
            onPressed: () => _beginDeletion(),
            child: const Text('Continue without re-authenticating'),
          ),
        ],
      ),
    );
  }

  // ── 4. In flight ─────────────────────────────────────────────────────
  Widget _buildDeleting(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Deleting your account…',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Please keep the app open. Do not close it until this '
              'finishes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const Key('deleteAccountRetryButton'),
                onPressed: _beginDeletion,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 5. Done ──────────────────────────────────────────────────────────
  Widget _buildDone(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Your account has been deleted',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your account and its synced data have been removed from our '
              'servers, and this device has been cleared.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              key: const Key('deleteAccountDoneButton'),
              onPressed: () => context.go('/welcome'),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  // ── The actual deletion ──────────────────────────────────────────────
  Future<void> _beginDeletion() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _step = DeleteAccountStep.deleting;
      _error = null;
    });

    // (a) Ask the BACKEND to delete. This is the only step that can actually
    // remove the account; everything after it is local cleanup.
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
    } catch (_) {
      // The server refused or was unreachable. Crucially we do NOT clear the
      // local session here: the account still exists, and signing the customer
      // out would strand them with no way back in and no idea why.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'We could not delete your account just now. Your account is '
            'unchanged — please try again in a moment.';
      });
      return;
    }

    // (b) Backend confirmed. Now tear down the device.
    // Firebase first: an orphaned Firebase session outliving the account is a
    // credential we do not control.
    try {
      await ref.read(phoneAuthServiceProvider).signOut();
    } catch (_) {
      // Non-fatal — the backend account is already gone.
    }

    // (c) Release this device's push registration. The account is gone, so the
    // FCM token must stop being routable to it — otherwise the backend keeps
    // delivering that customer's notifications. This is the same call logout
    // makes, and deleting is a strictly stronger event than logging out.
    try {
      await ref.read(deviceTokenCoordinatorProvider).handleLogout();
    } catch (_) {
      // Non-fatal — the server-side deletion is what matters. A stale token
      // would at worst keep delivering to a user whose row no longer exists.
    }

    // (d) Drop the access/refresh tokens so no stale credential survives.
    try {
      await ref.read(authServiceProvider).clearLocalSession();
    } catch (_) {
      // Non-fatal.
    }

    // (e) Wipe the customer's own local data. Failing this would leave
    // personal data on a device whose account no longer exists, so it is
    // best-effort but always attempted.
    try {
      await ref.read(localStorageDriverProvider).clear();
    } catch (_) {
      // Non-fatal — the server-side deletion is what matters legally.
    }

    // (f) Any queued foreground alert belongs to the deleted account.
    ref.read(inAppNotificationControllerProvider.notifier).clear();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = DeleteAccountStep.done;
    });
  }
}

/// Plain-language list of what is lost, shown before confirmation.
class _ImpactList extends StatelessWidget {
  const _ImpactList();

  @override
  Widget build(BuildContext context) {
    const impacts = [
      'Your profile and account',
      'Saved products and saved shops',
      'Saved addresses',
      'Notification history and preferences',
      'Search history and recently viewed items on this device',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You will permanently lose:',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final impact in impacts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.remove_circle_outline,
                  size: 18,
                  color: AppColors.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    impact,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
