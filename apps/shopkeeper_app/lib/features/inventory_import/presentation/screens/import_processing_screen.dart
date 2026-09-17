import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/import_controller.dart';
import '../../domain/import_models.dart';

/// Import Processing — the confirm step: applies the staged job to inventory
/// and renders the outcome (Import Success / Partial Success / Import Failed
/// / queued background processing).
///
/// The screen fires `confirm()` ONCE on entry, watching the shared
/// [importControllerProvider] for the result.
class ImportProcessingScreen extends ConsumerStatefulWidget {
  const ImportProcessingScreen({super.key});

  @override
  ConsumerState<ImportProcessingScreen> createState() =>
      _ImportProcessingScreenState();
}

class _ImportProcessingScreenState
    extends ConsumerState<ImportProcessingScreen> {
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_fired) return;
      final state = ref.read(importControllerProvider);
      if (state.status == ImportStatus.preview &&
          state.preview != null &&
          state.preview!.validCount > 0) {
        _fired = true;
        ref.read(importControllerProvider.notifier).confirm();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Applying import')),
      body: SafeArea(
        child: switch (state.status) {
          ImportStatus.confirming => const _ProcessingView(),
          ImportStatus.done => _ResultView(result: state.result!),
          ImportStatus.error => _FailedRetryView(
              message: state.message ?? 'Could not apply the import.',
              onRetry: () {
                _fired = true;
                ref.read(importControllerProvider.notifier).confirm();
              },
            ),
          // Arrived without a staged preview → nothing to confirm.
          _ => const _NothingToApplyView(),
        },
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text('Applying rows to your inventory…',
              key: const Key('import-processing'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'This usually takes a few seconds.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result});

  final ImportConfirmResult result;

  (IconData, Color, String, String, String) get _view {
    if (result.queued) {
      return (
        Icons.schedule_outlined,
        AppTheme.pendingAmber,
        'Import queued',
        '${result.processed} products queued for background processing. '
            'Check Import history for the outcome.',
        'import-result-queued',
      );
    }
    if (result.processed == 0) {
      return (
        Icons.error_outline,
        AppTheme.rejectedRed,
        'Import failed',
        'No rows could be applied. Check Import history for details.',
        'import-result-failed',
      );
    }
    if (result.failed > 0) {
      return (
        Icons.warning_amber_outlined,
        AppTheme.pendingAmber,
        'Partially imported',
        '${result.processed} products imported, '
            '${result.failed} could not be applied.',
        'import-result-partial',
      );
    }
    return (
      Icons.check_circle_outline,
      AppTheme.verifiedGreen,
      'Import successful',
      '${result.processed} products imported.',
      'import-result-success',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color, title, detail, keyName) = _view;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              key: Key(keyName),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('import-result-done'),
                onPressed: () {
                  ref.read(importControllerProvider.notifier).resetFlow();
                  context.go(Routes.importCenter);
                },
                child: const Text('Done'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('import-result-history'),
                onPressed: () {
                  ref.read(importControllerProvider.notifier).resetFlow();
                  context.go(Routes.importHistory);
                },
                child: const Text('View import history'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedRetryView extends ConsumerWidget {
  const _FailedRetryView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppTheme.rejectedRed),
            const SizedBox(height: 16),
            Text(
              'Import failed',
              key: const Key('import-result-failed'),
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('import-failed-back'),
                    onPressed: () {
                      ref.read(importControllerProvider.notifier).resetFlow();
                      context.go(Routes.importCenter);
                    },
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('import-failed-retry'),
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingToApplyView extends ConsumerWidget {
  const _NothingToApplyView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_off_outlined,
              size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Nothing to apply'),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('import-nothing-back'),
            onPressed: () {
              ref.read(importControllerProvider.notifier).resetFlow();
              context.go(Routes.importCenter);
            },
            child: const Text('Back to Import Center'),
          ),
        ],
      ),
    );
  }
}
