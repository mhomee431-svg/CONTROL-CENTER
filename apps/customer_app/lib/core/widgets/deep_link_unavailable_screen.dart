import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import 'empty_state_view.dart';

/// Shown when a deep link resolves to a route that exists but whose content is
/// not available -- an expired offer, a promotion the backend no longer serves.
///
/// WHY A REGISTERED ROUTE FOR UNAVAILABLE CONTENT
/// ----------------------------------------------
/// The alternative is letting the link resolve to nothing, which lands the
/// customer on a 404 screen with no way back. Registering the path and
/// degrading *inside* the app keeps three promises: the router table is the
/// single source of truth for what a link may target, a link can never produce
/// a dead end, and shipping the real offer screen later is a one-line change
/// here rather than a migration of every link already in the wild.
///
/// The guard normally intercepts these links before this screen is reached
/// (an offer is account-scoped, and its probe reports it unavailable), so this
/// is the last line of defence, not the first.
class DeepLinkUnavailableScreen extends StatelessWidget {
  /// What the link was trying to reach, in customer language ("this offer").
  /// Deliberately not the raw entity name.
  final String subject;

  final IconData icon;

  const DeepLinkUnavailableScreen({
    super.key,
    required this.subject,
    this.icon = Icons.campaign_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Not available'),
      ),
      body: SafeArea(
        child: EmptyStateView(
          icon: icon,
          title: "This $subject isn't available",
          message:
              'It may have ended, or it may not be served in your area yet. '
              'Browse what is available near you instead.',
          actionLabel: 'Browse nearby',
          actionIcon: Icons.storefront_outlined,
          onActionTap: () {
            // `go`, not `push`: this screen is a dead end by design, so
            // "back" should leave the app rather than return the customer to a
            // page that cannot help them.
            context.go('/');
          },
        ),
      ),
    );
  }
}

/// Route body for `/offer/:id`.
///
/// The id is parsed but not rendered: there is no offer screen in this build,
/// and showing an offer id to a customer would be leaking an internal key
/// while telling them nothing useful.
class OfferLinkScreen extends StatelessWidget {
  const OfferLinkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DeepLinkUnavailableScreen(subject: 'offer');
  }
}

/// Small helper so the "browse nearby" copy stays on-brand wherever a deep
/// link degrades, instead of every call site inventing its own wording.
const String kDeepLinkBrowseNearbyLabel = 'Browse nearby';

/// Exposed for tests: the colour the fallback uses for its icon, so a test can
/// assert the screen is the themed one rather than a default Material blue.
const Color kDeepLinkUnavailableIconColor = AppColors.textMuted;
