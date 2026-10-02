import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/app_text.dart';
import '../controllers/settings_controller.dart';

/// Confirmation step for signing out of the Shopkeeper app.
///
/// Reached from the Account tab and from *Account settings* / *Security*.
/// Logging out runs the full `AuthController.logout()` teardown (Firebase
/// sign-out, backend session revoke, token wipe, cached-state reset) and the
/// router then redirects to Welcome on its own — this screen never navigates by
/// hand, it only asks for confirmation and shows progress while it runs.
class LogoutConfirmationScreen extends ConsumerWidget {
  const LogoutConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggingOut = ref.watch(settingsControllerProvider).loggingOut;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(appText(context).commonLogOut2)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.logout, color: scheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            appText(context).logoutConfirmationScreenLogOutOfPasslyBusiness,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      appText(context).logoutConfirmationScreenYouWillNeedToSign,
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              appText(context).commonWhatHappensNext,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: const [
                  _Consequence(
                    icon: Icons.key_off_outlined,
                    text: 'This device is signed out and its saved session '
                        'is erased.',
                  ),
                  Divider(height: 1),
                  _Consequence(
                    icon: Icons.storefront_outlined,
                    text: 'Your shop, products and offers are untouched.',
                  ),
                  Divider(height: 1),
                  _Consequence(
                    icon: Icons.sync_disabled_outlined,
                    text: 'POS sync and alerts stop until you sign in again.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('logout_confirm_button'),
              onPressed: loggingOut
                  ? null
                  : () =>
                      ref.read(settingsControllerProvider.notifier).logout(),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: loggingOut
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text(appText(context).commonSigningOut),
                      ],
                    )
                  : Text(appText(context).commonLogOut2),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('logout_cancel_button'),
              onPressed: loggingOut ? null : () => context.pop(),
              child: Text(appText(context).commonStaySignedIn),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "what happens next" row.
class _Consequence extends StatelessWidget {
  const _Consequence({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(text, style: const TextStyle(fontSize: 13)),
      dense: true,
    );
  }
}