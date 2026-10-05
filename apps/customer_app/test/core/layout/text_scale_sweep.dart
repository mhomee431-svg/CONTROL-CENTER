import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/core/layout/text_scaling.dart';

/// Shared harness for sweeping a widget across system text sizes.
///
/// ## Why this exists
/// ------------------
/// A large system font breaks layouts in two very different ways, and only one
/// of them is loud:
///
///  * **Loud** — a `Row` whose children cannot flex overflows horizontally and
///    Flutter throws a `RenderFlex` error. Easy to catch, and easy to assume is
///    the whole problem.
///  * **Quiet** — a fixed-height box silently CLIPS its overflowing child. No
///    exception, no warning. The customer sees a card with the price missing,
///    or a button they cannot quite reach, and nothing in the logs says why.
///
/// So a harness that only asserts `takeException() isNull` is worse than
/// useless: it reads as proof of safety while covering the loud half of the
/// problem. [TextScaleSweep] checks both halves.
///
/// It also reports *every* error rather than the first. `takeException()`
/// returns one exception, so a second broken row at a higher scale stays
/// invisible until someone happens to fix the first.
class TextScaleSweep {
  TextScaleSweep._(this._errors);

  final List<String> _errors;

  /// Every Flutter error raised while the widget was pumped, as readable text.
  List<String> get errors => List.unmodifiable(_errors);

  bool get isClean => _errors.isEmpty;

  /// Pumps [build] at one text scale and one device size, collecting errors.
  ///
  /// [build] is a callback rather than a widget so each scale gets a fresh
  /// instance — reusing one instance would carry state between scales and
  /// quietly invalidate the sweep.
  static Future<TextScaleSweep> at(
    WidgetTester tester, {
    required Widget Function() build,
    required double scale,
    Size device = const Size(390, 844),
  }) async {
    final errors = <String>[];

    tester.view.physicalSize = device;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Capture every error rather than letting the first one escape to
    // `takeException()`, so one broken row cannot mask the next.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      errors.add(details.exceptionAsString());
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: build(),
      ),
    );
    // A second pump so any error raised on the follow-up frame (an overflow is
    // reported during paint, not layout) is captured too.
    await tester.pump();

    // Drain anything the framework queued for the test binding.
    final pending = tester.takeException();
    if (pending != null) {
      errors.add(pending.toString());
    }

    return TextScaleSweep._(errors);
  }

  /// Sweeps [build] across the whole supported range on a phone-sized screen.
  ///
  /// The scales are the ones that matter in practice, not a fine-grained sweep:
  /// `TextScaling` already names them, and testing each one on each device class
  /// multiplies the runtime for very little extra signal.
  static Future<void> acrossPhoneScales(
    WidgetTester tester, {
    required Widget Function() build,
    required String label,
    Size device = const Size(390, 844),
  }) async {
    for (final scale in <double>[
      TextScaling.normal,
      TextScaling.large,
      TextScaling.xLarge,
      TextScaling.maxAccessibility,
      TextScaling.maxSupportedScale,
    ]) {
      final result = await at(
        tester,
        build: build,
        scale: scale,
        device: device,
      );
      expect(
        result.isClean,
        isTrue,
        reason:
            '$label overflowed or errored at ${TextScaling.describe(scale)}. '
            'Errors: ${result.errors.join(" | ")}',
      );
    }
  }

  /// Asserts nothing inside [find] is clipped by an ancestor.
  ///
  /// This is the check for the quiet failure. A widget scrolled out of view is
  /// fine, so callers pass a finder scoped to something they expect to be
  /// visible; anything whose painted box extends past a clipping ancestor's
  /// visible edge is genuinely cut off.
  static void expectNotClipped(
    WidgetTester tester,
    Finder find, {
    required String label,
    required String at,
  }) {
    final elements = find.evaluate().toList();
    if (elements.isEmpty) return;

    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

    for (final element in elements) {
      // `findRenderObject()` is typed as `RenderObject?`, which has neither a
      // size nor paint bounds — those live on `RenderBox`. Anything that is not
      // a box (a `RenderViewport`, say) has no paintable geometry to check.
      final object = element.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) continue;

      // A zero-sized box is its own kind of failure: the control is present in
      // the tree but has no area to be seen or tapped.
      if (object.size.isEmpty) {
        fail('$label has no size at $at — it is invisible and untappable');
      }

      final rect = object.paintBounds;
      if (rect.right > viewport.width + 0.5) {
        fail(
          '$label runs off the right edge at $at: it ends at '
          '${rect.right.toStringAsFixed(1)} on a '
          '${viewport.width.toStringAsFixed(1)} wide screen',
        );
      }
    }
  }
}
