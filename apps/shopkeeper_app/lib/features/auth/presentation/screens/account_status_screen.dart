import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/auth_controller.dart';

/// Account-status gate (Phase 23) — shown when the backend reports the
/// shopkeeper's account as INACTIVE / SUSPENDED / BANNED during startup.
///
/// The screen is a dead-end by design: nothing from the app is reachable
/// until the account is re-activated by support (or the user signs out).
class AccountStatusScreen extends ConsumerWidget {
  const AccountStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authControllerProvider);
    final message = (auth.errorMessage?.isNotEmpty ?? false)
        ? auth.errorMessage!
        : 'Your account is not active. Please contact support.';
    final lower = message.toLowerCase();
    final suspended = lower.contains('suspend') || lower.contains('bann');
    final title = suspended ? 'Account Suspended' : 'Account Not Active';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    suspended ? Icons.block : Icons.person_off,
                    size: 64,
                    color: scheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(
                    'If you believe this is a mistake, reach out to the '
                    'Hyperlocal support team to reactivate your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
