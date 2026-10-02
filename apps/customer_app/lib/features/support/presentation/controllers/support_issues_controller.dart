import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/support_repository.dart';

export '../../domain/models/support_issue.dart';

/// The tickets the signed-in customer has filed, newest first.
///
/// `autoDispose` on purpose: the screen that files a report and the screen that
/// lists reports are different routes under `/support/*`, so a freshly filed
/// ticket must be visible the next time the list is opened rather than being
/// served from a read taken before it existed.
///
/// A failure PROPAGATES rather than being flattened into an empty list, so the
/// view can tell "you have not reported anything" from "we could not load your
/// reports" — two situations that need different copy and different actions.
final supportIssuesProvider = FutureProvider.autoDispose<List<SupportIssue>>((
  ref,
) async {
  return ref.watch(supportRepositoryProvider).listMyIssues();
});
