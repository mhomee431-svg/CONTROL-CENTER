import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../share/share_content.dart';
import '../share/share_service.dart';

/// The one place a share is composed and dispatched.
///
/// Replaces three independent ad-hoc implementations (a helper in
/// `core/widgets`, an inline call in the product screen, another in the shop
/// screen) that each invented their own wording and none of which could attach
/// a link. Having one owner is what makes "no id in the prose, no credential
/// anywhere" a property of the codebase rather than a habit of each call site.
final shareServiceProvider = Provider<ShareService>(
  (ref) => const PlatformShareService(),
);

/// Shares a product, optionally with a safe deep link.
///
/// [productId] enables the link; omitting it shares the text alone, which is
/// what the search-result card does when it has no shareable id.
Future<ShareOutcome> shareProductContent(
  WidgetRef ref,
  ShareContent content,
) async {
  final outcome = await ref.read(shareServiceProvider).share(content);
  if (outcome == ShareOutcome.unavailable) {
    _notify(ref, 'Could not open sharing right now.');
  }
  return outcome;
}

/// Shows a short confirmation that a share is on its way.
///
/// Only ever shown on success. Telling someone "shared!" after they dismissed
/// the sheet trains them to ignore the message, and showing one on failure
/// trains them to ignore that too.
void _notify(WidgetRef ref, String message) {
  final context = ref.context;
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textMuted,
      ),
    );
}
