import 'package:flutter/material.dart';

/// Reusable keyboard and focus behaviour for text-entry forms.
///
/// WHY THIS EXISTS
/// ---------------
/// The app has 17 text inputs and only 4 declared a `textInputAction`, with
/// zero `onEditingComplete` and no `FocusTraversalGroup` anywhere. That leaves
/// the three behaviours a form is judged on — next, done, and scroll-to-field —
/// to whatever the platform default happens to be, which on a single-line field
/// is usually "do nothing useful".
///
/// ## What actually goes wrong without this
/// On a phone the IME shows a return key whose *label* comes from
/// `textInputAction`. With it unset the customer taps a key marked ⏎ or "done"
/// on the FIRST field of a three-field form and the keyboard closes — so they
/// have to tap each field again. On a hardware keyboard or a tablet with a
/// keyboard case, Tab order is not the visual order unless a traversal policy
/// says so.
///
/// ## The three behaviours, and why each is configured rather than assumed
/// * **next** — moves focus to the following field. Never "submit": submitting
///   from field one of three is a data-loss bug, because the later fields are
///   still empty and the validator rejects a form the customer believed they
///   had finished.
/// * **done** — on the LAST field only, and it closes the keyboard without
///   submitting. Submission stays an explicit button press, so an accidental
///   done never writes a half-typed value.
/// * **scroll-to-field** — [FormKeyboard.scrollPaddingFor] gives the focused
///   field room to sit above the keyboard. Flutter's default padding is a flat
///   20dp, which on a 300dp-tall keyboard leaves the label under the keys.
class FormKeyboard {
  const FormKeyboard._();

  /// Padding Flutter adds around a focused field so it clears the keyboard.
  ///
  /// The default is `EdgeInsets.all(20)`, which is not enough once the field
  /// has a floating label and a helper or error line: the message is what the
  /// customer needs to read, and it is the part that ends up under the keys.
  static EdgeInsets scrollPaddingFor(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final direction = Directionality.of(context);
    // Bottom inset in a bottom-to-top locale becomes a TOP inset.
    return direction == TextDirection.rtl
        ? EdgeInsets.fromLTRB(20, viewInsets.bottom + 24, 20, 20)
        : EdgeInsets.fromLTRB(20, 20, 20, viewInsets.bottom + 24);
  }

  /// Dismisses the keyboard on a tap that is not on a field.
  ///
  /// Without this the only ways to close the keyboard are `done` or the system
  /// back gesture, so tapping the empty space below a short form appears to do
  /// nothing -- a common and easily-missed complaint on forms.
  ///
  /// `HitTestBehavior.opaque` so the whole background is a tap target; only a tap
  /// that does NOT land on a field reaches here, because children win the hit
  /// test first.
  static Widget dismissOnBackgroundTap({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => dismiss(null),
      child: child,
    );
  }

  /// Wraps a form's fields so tab order follows the eye.
  ///
  /// Without an explicit policy the order is incidental -- fine for a single
  /// `Column`, wrong the moment two fields share a `Row`, where depth-first
  /// traversal visits them in a different order than the eye does. Declaring it
  /// makes the intent reviewable rather than emergent.
  static FocusTraversalGroup ordered({required Widget child}) {
    return FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: child);
  }

  /// Clears focus so the IME dismisses.
  ///
  /// Unfocuses rather than popping: closing the keyboard must never close the
  /// screen underneath it.
  static void dismiss(FocusNode? node) {
    node?.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Moves focus to the next field, or dismisses at the end.
  ///
  /// The one-line version of next/done, for a form that builds its fields in a
  /// list and would otherwise repeat the same four lines per field.
  static void advance({required List<FocusNode> nodes, required int from}) {
    if (nodes.isEmpty) return;
    if (from + 1 < nodes.length) {
      nodes[from + 1].requestFocus();
    } else {
      // Terminal field: close the keyboard WITHOUT submitting. Submission stays
      // an explicit button press, so a stray done never writes a half-typed
      // value and never closes the screen underneath.
      dismiss(nodes.last);
    }
  }

  /// The IME action a field at [index] of [total] should show.
  ///
  /// `next` for everything but the last, `done` for the last. Getting this
  /// backwards is the classic form bug: a form whose LAST field says "next"
  /// strands the customer on a dead key with no way forward.
  static TextInputAction actionFor(int index, int total) =>
      index + 1 < total ? TextInputAction.next : TextInputAction.done;
}
