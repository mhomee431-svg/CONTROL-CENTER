import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import 'share_content.dart';

/// Outcome of offering a share to the platform.
enum ShareOutcome {
  /// The sheet was handled. This includes the customer dismissing it, which
  /// `share_plus` 13.3.0 does not distinguish from a dispatched share
  /// ([ShareResult] exposes only an `unavailable` status). The distinction is
  /// not needed: no confirmation is shown on success, so treating a dismissal
  /// as "handled" produces exactly the right, silent behaviour.
  shared,

  /// The platform refused: no share target, plugin unavailable, or a host with
  /// no share UI. Never throws at the call site.
  unavailable,
}

/// Hands composed [ShareContent] to the OS share sheet.
///
/// Abstracted behind a provider so the calling screens stay testable and so
/// every failure path is reachable in a test. `share_plus` is deliberately not
/// called directly from a widget: a thrown [PlatformException] from a missing
/// plugin would otherwise take down a customer's product page because they
/// tapped the share icon.
abstract class ShareService {
  Future<ShareOutcome> share(ShareContent content);
}

/// The real implementation, backed by `share_plus`.
class PlatformShareService implements ShareService {
  const PlatformShareService();

  @override
  Future<ShareOutcome> share(ShareContent content) async {
    // Re-check here rather than trusting the composer. This is the last point
    // before the string leaves the process, and the composer is not the only
    // thing that can build a ShareContent in future.
    assertShareIsSafe(content);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: content.fullText, subject: content.subject),
      );
      // `share_plus` 13.3.0 exposes exactly one distinguishable status on
      // `ShareResult`: `unavailable`. Everything else means the platform
      // handled the request. Compared by identity so a future version adding a
      // status cannot silently turn a failure into a success.
      if (identical(result, ShareResult.unavailable)) {
        return ShareOutcome.unavailable;
      }
      return ShareOutcome.shared;
    } catch (error, stack) {
      // Deliberately swallowed and reported as a value. A share sheet failing
      // to open is a cosmetic problem; crashing the screen behind it is not.
      debugPrint('Share sheet failed: $error\n$stack');
      return ShareOutcome.unavailable;
    }
  }
}
