import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Turns an open-ended wait into a bounded, actionable one.
///
/// WHY THIS EXISTS
/// ---------------
/// Every loading branch in this app is covered by a network timeout
/// (`ApiClient` uses 15 s connect/receive/send, plus an exponential retry), so a
/// spinner CANNOT literally spin forever. What it can do is spin for fifteen
/// seconds with no explanation — and a spinner that has been on screen long
/// enough for a customer to wonder whether the app is broken is the failure
/// this widget fixes. Past [after] it adds one honest line and, when the caller
/// can re-issue the request, a retry.
///
/// It renders NOTHING before [after] elapses, so a normal fast load is
/// untouched — this is not a second loading state, it is a footnote to the
/// first one.
///
/// The timer is cancelled in [dispose]. That is not tidiness: a live timer left
/// behind after a route pops makes a Flutter test fail with "A Timer is still
/// pending", and the fix belongs in the widget rather than in every test.
class SlowLoadNotice extends StatefulWidget {
  /// How long the wait must last before the notice appears. The default sits
  /// just above the client's 15 s ceiling minus a typical success budget: long
  /// enough that a normal load never shows it, short enough that the customer
  /// is not left guessing for the whole timeout.
  final Duration after;

  /// What to say. Deliberately caller-supplied so a search can say "searching"
  /// while a map says "loading the map" — one generic sentence for every screen
  /// tells the customer nothing about what is slow.
  final String message;

  /// Re-issues the request. Null when the caller has no retry to offer, in
  /// which case no button is rendered (a dead Retry is worse than none).
  final VoidCallback? onRetry;

  const SlowLoadNotice({
    super.key,
    this.after = const Duration(seconds: 8),
    required this.message,
    this.onRetry,
  });

  @override
  State<SlowLoadNotice> createState() => _SlowLoadNoticeState();
}

class _SlowLoadNoticeState extends State<SlowLoadNotice> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        if (widget.onRetry != null) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('slowLoadRetry'),
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ],
    );
  }
}
