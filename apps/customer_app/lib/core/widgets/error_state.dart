import 'package:flutter/material.dart';

import '../network/api_error_handler.dart';
import '../theme/app_theme.dart';

/// The app's ONE error surface: what failed, in plain language, and the one
/// action that can move the customer forward.
///
/// WHY ONE WIDGET
/// --------------
/// Error handling was hand-rolled on ~40 call sites and had drifted into three
/// incompatible families, none of them trustworthy:
///
/// 1. `Text('Error: $error')` — rendered the RAW EXCEPTION to the customer.
///    A `DioException` or an `ApiException.toString()` puts the HTTP status, the
///    request path and sometimes a stack fragment on screen. That is both ugly
///    and a small information leak, and it is the opposite of a message.
/// 2. `message: '$err'` on an `EmptyStateView` — same leak, one layer buried.
/// 3. A hand-built `Column` of icon + text + button, repeated with three
///    different titles and two different button labels for the same failure.
///
/// This widget makes "what failed" and "what to do" impossible to get wrong,
/// because a caller supplies only those two things.
///
/// THE ONE RULE IT ENFORCES: NO DEAD RETRY
/// --------------------------------------
/// [onRetry] is only rendered when the caller has something real to re-read, and
/// [ErrorState.fromApi] additionally inspects [ApiException.isRetryable] — a
/// 403, 404, 409 or 422 must NOT offer "Retry", because retrying can never work
/// and a button that can never succeed is exactly the dead control the app's own
/// error rules forbid. So does [ErrorState.from].
class ErrorState extends StatelessWidget {
  /// Screen-specific headline, e.g. "Unable to load nearby shops."
  ///
  /// States WHAT did not load, in the customer's terms. Not "Error", not
  /// "Something went wrong" — those talk about the app instead of about the
  /// customer's task.
  final String title;

  /// Supporting line. Defaults to the message [error] carries, which is already
  /// customer-safe (see [friendlyErrorMessage]). Pass explicit copy only when
  /// the screen can say something the generic message cannot.
  final String? message;

  /// Re-runs the failed request. Null hides the button entirely rather than
  /// rendering one that does nothing.
  final VoidCallback? onRetry;

  /// Overrides the action label. Defaults to "Retry".
  final String retryLabel;

  /// Overrides the icon. Defaults to [iconForApiError] via [ErrorState.fromApi].
  final IconData? icon;

  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon,
    this.retryButtonKey,
  });

  /// Key applied to the [RetryButton], so a screen that had its retry control
  /// addressable by a test (or by a semantics label) keeps that handle after
  /// being moved onto this shared widget.
  final Key? retryButtonKey;

  /// Builds the state for an arbitrary thrown error.
  ///
  /// The headline is the caller's own; the body falls back to
  /// [friendlyErrorMessage], which is the ONLY safe way to turn an exception
  /// into text. Passing the error OBJECT around instead of the string it
  /// resolves to is how the raw-exception leak got in.
  factory ErrorState.from(
    Object? error, {
    required String title,
    VoidCallback? onRetry,
    String retryLabel = 'Retry',
    IconData? icon,
    Key? retryButtonKey,
  }) {
    return ErrorState(
      title: title,
      message: friendlyErrorMessage(error),
      onRetry: onRetry,
      retryLabel: retryLabel,
      icon: icon,
      retryButtonKey: retryButtonKey,
    );
  }

  /// Builds the state for an [ApiException], choosing the icon AND deciding
  /// whether a retry is even possible.
  ///
  /// [onRetry] is forced to null when the failure is not retryable, so a 403 /
  /// 404 / 409 / 422 cannot render a dead button even if a caller passed one out
  /// of habit. Callers do not have to remember the rule; this is where it lives.
  factory ErrorState.fromApi(
    Object? error, {
    required String title,
    VoidCallback? onRetry,
    String retryLabel = 'Retry',
    Key? retryButtonKey,
  }) {
    final api = error is ApiException ? error : null;

    // `isRetryable` is the single source of truth for "can this request ever
    // succeed if repeated?", defined next to the type enum so the two cannot
    // drift apart.
    final effectiveRetry = (api == null || api.isRetryable) ? onRetry : null;

    return ErrorState(
      title: title,
      message: friendlyErrorMessage(error),
      onRetry: effectiveRetry,
      retryLabel: retryLabel,
      icon: iconForApiError(error),
      retryButtonKey: retryButtonKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.error_outline, size: 56, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              // The title is the whole message. Announcing the icon as well
              // would read out "error outline" before the useful part.
              liveRegion: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
            // Only when there is something to re-read. See the class doc: a
            // button that cannot work is worse than no button.
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              RetryButton(
                onPressed: onRetry,
                label: retryLabel,
                buttonKey: retryButtonKey,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's ONE retry button.
///
/// Separate from [ErrorState] so it can be reused on its own — a failed inline
/// section, a failed sheet, a submit that failed — without dragging the
/// full-screen layout along with it.
///
/// Min height 48px: this is a control a customer taps while frustrated, often
/// one-handed, often having just decided whether to trust the app at all.
class RetryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  /// Optional key, for screens whose tests address the retry control directly.
  final Key? buttonKey;

  /// Filled (primary) or outlined. Outlined reads as secondary, which is right
  /// for an error state where the button is the customer's main hope — so
  /// filled is the default and outlined is the exception.
  final bool outlined;

  const RetryButton({
    super.key,
    required this.onPressed,
    this.label = 'Retry',
    this.outlined = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.refresh, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Text(label),
      ],
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: outlined
          ? OutlinedButton(
              key: buttonKey,
              onPressed: onPressed,
              child: child,
            )
          : FilledButton(
              key: buttonKey,
              onPressed: onPressed,
              child: child,
            ),
    );
  }
}

/// The icon that matches a failure's KIND.
///
/// Split out so one failure always looks the same wherever it appears — an
/// offline error showing a generic "!" on one screen and a wifi-off icon on
/// another teaches the customer that the app does not know what went wrong.
IconData iconForApiError(Object? error) {
  if (error is! ApiException) return Icons.error_outline;
  switch (error.type) {
    case ApiErrorType.offline:
      return Icons.wifi_off_rounded;
    case ApiErrorType.timeout:
      return Icons.timer_off_outlined;
    case ApiErrorType.sessionExpired:
      return Icons.lock_clock_outlined;
    case ApiErrorType.accessDenied:
      return Icons.lock_outline;
    case ApiErrorType.notFound:
      return Icons.search_off_rounded;
    case ApiErrorType.rateLimited:
      return Icons.hourglass_bottom_rounded;
    case ApiErrorType.validation:
      return Icons.rule_rounded;
    case ApiErrorType.conflict:
      return Icons.merge_type_rounded;
    case ApiErrorType.requestCancelled:
      return Icons.cancel_outlined;
    case ApiErrorType.partialFailure:
      // Some content DID arrive: the icon must not say "nothing here".
      return Icons.report_gmailerrorred_rounded;
    case ApiErrorType.serverError:
    case ApiErrorType.unknown:
      return Icons.cloud_off_rounded;
  }
}