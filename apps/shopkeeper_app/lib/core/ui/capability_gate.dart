import 'package:flutter/material.dart';

import '../state/system_state_view.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// The ONE capability gate for backend-driven feature flags (spec §103).
///
/// The four `canX` flags come from the centralized
/// `capabilitiesControllerProvider` (backed by the backend's
/// `derive_shop_capabilities`); a screen passes its own flag + copy here and
/// renders either the real content or the locked state. No screen ever
/// derives plan rules itself.
///
/// UI hiding is NOT authorization — the backend stays authoritative and a
/// stale "allowed" still meets its 403 (`ApiException.isEntitlementDenied`),
/// which the feature's error path renders with the server's upgrade copy.
///
/// ```dart
/// CapabilityGate(
///   allowed: caps.canUsePos,
///   title: 'POS not in your plan',
///   message: 'Upgrade to connect a point of sale.',
///   child: const PosScreenBody(),
/// )
/// ```
/// ─────────────────────────────────────────────────────────────────────────────
class CapabilityGate extends StatelessWidget {
  const CapabilityGate({
    super.key,
    required this.allowed,
    required this.title,
    required this.message,
    required this.child,
  });

  /// The backend flag for this feature (never computed here).
  final bool allowed;

  /// Locked-state copy — the feature owns its wording; the layer only gates.
  final String title;
  final String message;

  /// The real screen body, rendered only when [allowed].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (allowed) return child;
    return SystemStateView.empty(
      key: const Key('capability-locked'),
      title: title,
      message: message,
      icon: Icons.lock_outline,
      iconColor: Theme.of(context).colorScheme.outline,
    );
  }
}
