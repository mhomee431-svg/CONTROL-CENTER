import 'package:flutter/material.dart';

/// Asks "Discard changes?" before letting someone leave a form they filled in.
///
/// The shopkeeper is on a phone, in a shop, and can be interrupted. Losing a
/// typed-in product because a call came in is the exact failure this prevents,
/// and the two answers have to be obvious: **Stay** keeps the work, **Discard**
/// throws it away on purpose.
///
/// Implementation note that matters: with [PopScope] `canPop: false`, calling
/// `Navigator.pop()` again from inside the callback is ALSO blocked — the
/// widget is still telling the navigator it may not pop. So "Discard" flips
/// `canPop` back to true and pops on the next frame. Getting this wrong produces
/// a dialog whose Discard button does nothing, which is worse than no dialog.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    required this.hasUnsavedChanges,
    required this.child,
    this.title = 'Discard changes?',
    this.message =
        'You have unsaved changes. If you leave, they will be lost.',
    this.stayLabel = 'Stay',
    this.discardLabel = 'Discard',
    this.onDiscard,
    super.key,
  });

  /// Whether the form currently holds anything the shopkeeper would miss.
  ///
  /// Usually a field controller's `text.isNotEmpty`, or a flag the form sets
  /// itself. Compare against the INITIAL state, not against empty — a form the
  /// shopkeeper opened and cleared deliberately should not nag them.
  final bool hasUnsavedChanges;

  final Widget child;

  final String title;
  final String message;
  final String stayLabel;
  final String discardLabel;

  /// Called after the shopkeeper chooses Discard, before the pop.
  ///
  /// The hook for clearing a preserved draft. It runs on the confirmed path
  /// only, so choosing Stay leaves everything intact.
  final VoidCallback? onDiscard;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  /// Latched once the shopkeeper confirms, so the pop that follows is allowed.
  bool _popAllowed = false;

  @override
  Widget build(BuildContext context) {
    final guarded = widget.hasUnsavedChanges && !_popAllowed;
    return PopScope<Object?>(
      canPop: !guarded,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDiscardChangesDialog(
          context,
          title: widget.title,
          message: widget.message,
          stayLabel: widget.stayLabel,
          discardLabel: widget.discardLabel,
        );
        // Stay, or the dialog was dismissed by tapping outside: nothing moves.
        if (discard != true || !mounted) return;
        widget.onDiscard?.call();
        setState(() => _popAllowed = true);
        // Pop after the rebuild, while `canPop` is true.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: widget.child,
    );
  }
}

/// Show the confirmation. Returns true only for an explicit **Discard**.
///
/// A separate function so a screen that needs the same decision away from a
/// back gesture (an "Cancel" button, a tab switch) asks it identically rather
/// than writing a second dialog with slightly different buttons.
Future<bool?> showDiscardChangesDialog(
  BuildContext context, {
  String title = 'Discard changes?',
  String message = 'You have unsaved changes. If you leave, they will be lost.',
  String stayLabel = 'Stay',
  String discardLabel = 'Discard',
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('discard-changes-dialog'),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const Key('discard-changes-stay'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(stayLabel),
        ),
        FilledButton(
          key: const Key('discard-changes-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(discardLabel),
        ),
      ],
    ),
  );
}
