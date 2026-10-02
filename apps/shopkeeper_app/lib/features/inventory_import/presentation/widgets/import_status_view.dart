import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/import_models.dart';

/// The visual vocabulary of an import job's state: which icon, in which colour.
///
/// ONE mapping for the whole feature. The confirm/result screen and the history
/// list used to choose their own icon and colour per status, which is how a job
/// ends up green in one place and amber in another. Every surface now reads its
/// icon and colour from here, so the states cannot drift apart.
///
/// The COPY stays with the surface that owns it — a history row wants the short
/// [ImportJobStatusValue.label] ("Partial Success") while the result screen wants
/// the full sentence. Only the visuals are shared.
@immutable
class ImportStatusTone {
  const ImportStatusTone({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

/// Maps a server status to its icon and colour.
///
/// The status vocabulary is [ImportJobStatusValue] — the API is the single
/// source of truth, so this never invents a state. An unrecognised status (one
/// the backend adds after this build) degrades to a neutral "help" icon rather
/// than throwing, exactly as [ImportJobStatusValue.label] degrades to humanised
/// text.
ImportStatusTone importStatusTone(String status) => switch (status) {
      ImportJobStatusValue.validating ||
      ImportJobStatusValue.validated =>
        const ImportStatusTone(
          icon: Icons.hourglass_empty,
          color: AppTheme.pendingAmber,
        ),
      ImportJobStatusValue.awaitingConfirmation => const ImportStatusTone(
          icon: Icons.upload_file_outlined,
          color: AppTheme.brandSeed,
        ),
      // QUEUED and PROCESSING are the same thing to a shopkeeper: "working on
      // it" — so they deliberately share an icon and colour.
      ImportJobStatusValue.queued ||
      ImportJobStatusValue.processing =>
        const ImportStatusTone(
          icon: Icons.schedule_outlined,
          color: AppTheme.pendingAmber,
        ),
      ImportJobStatusValue.completed => const ImportStatusTone(
          icon: Icons.check_circle_outline,
          color: AppTheme.verifiedGreen,
        ),
      ImportJobStatusValue.partial => const ImportStatusTone(
          icon: Icons.warning_amber_outlined,
          color: AppTheme.pendingAmber,
        ),
      ImportJobStatusValue.failed => const ImportStatusTone(
          icon: Icons.error_outline,
          color: AppTheme.rejectedRed,
        ),
      _ => const ImportStatusTone(
          icon: Icons.help_outline,
          color: AppTheme.pendingAmber,
        ),
    };

/// The status block every import outcome renders through.
///
/// One component covers the whole lifecycle — Processing, Success, Partial and
/// Failed — instead of each screen hand-rolling an icon/title/message stack.
/// The caller supplies the words (they differ per surface) and the tone decides
/// how it looks.
class ImportStatusView extends StatelessWidget {
  const ImportStatusView({
    required this.tone,
    required this.title,
    required this.message,
    this.iconSize = 56,
    this.titleKey,
    super.key,
  });

  /// Icon + colour for this outcome, normally from [importStatusTone].
  final ImportStatusTone tone;

  /// Short headline, e.g. "Import successful".
  final String title;

  /// One sentence of detail, e.g. "12 rows processed — all successful.".
  final String message;

  final double iconSize;

  /// Key on the title, so tests can assert WHICH outcome rendered without
  /// depending on the copy.
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(tone.icon, size: iconSize, color: tone.color),
        const SizedBox(height: 16),
        Text(
          title,
          key: titleKey,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }
}