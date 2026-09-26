import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';

/// Reusable guest auth gate for protected actions.
///
/// Returns `true` immediately when the customer is already signed in. As a
/// guest it opens a bottom sheet offering Google Sign-In; the original action
/// stays on screen underneath, so returning to it needs no route bookkeeping.
///
/// Usage:
/// ```dart
/// final allowed = await requireAuthentication(
///   context,
///   ref,
///   actionLabel: 'call this shop',
/// );
/// if (!allowed || !context.mounted) return;
/// // ... protected action ...
/// ```
Future<bool> requireAuthentication(
  BuildContext context,
  WidgetRef ref, {
  required String actionLabel,
}) async {
  if (ref.read(authControllerProvider).status == AuthStatus.authenticated) {
    return true;
  }

  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AuthGateSheet(actionLabel: actionLabel),
  );
  return signedIn ?? false;
}

class _AuthGateSheet extends ConsumerStatefulWidget {
  const _AuthGateSheet({required this.actionLabel});

  final String actionLabel;

  @override
  ConsumerState<_AuthGateSheet> createState() => _AuthGateSheetState();
}

class _AuthGateSheetState extends ConsumerState<_AuthGateSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    final state = ref.read(authControllerProvider);
    if (state.status == AuthStatus.error) {
      setState(() {
        _loading = false;
        _error =
            state.errorMessage ?? 'Google sign-in failed. Please try again.';
      });
      return;
    }

    // User dismissed the Google sheet — close the gate silently.
    Navigator.of(context).pop(false);
  }

  void _usePhoneOtp() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.push('/login');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, size: 40, color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Sign in to continue',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create an account or sign in to ${widget.actionLabel}. '
              'Your browsing stays exactly where it is.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _loading ? null : _signInWithGoogle,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.g_mobiledata, size: 28),
              label: Text(_loading ? 'Signing in…' : 'Continue with Google'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _loading ? null : _usePhoneOtp,
              child: const Text('Use phone OTP instead'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
